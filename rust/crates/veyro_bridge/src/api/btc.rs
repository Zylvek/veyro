//! BTC operations exposed to the UI. Every function is a thin wrapper over
//! the `chains` crate — the logic (and all tests) live there.
//!
//! Flow from the UI's perspective:
//! 1. `btc_unlock` — decrypts the wallet **inside Rust**, connects to the
//!    user's Electrum server, verifies the genesis hash (fund-safety: a
//!    server on a different network is refused) and keeps the seed in a
//!    zeroizing session; nothing secret crosses this boundary;
//! 2. `btc_sync` — gap-limited discovery, balance, spendables, and the next
//!    receive address for the "Receive" screen;
//! 3. `btc_fees` — the three sat/vB presets;
//! 4. `btc_send` — plan (validate + coin selection + fee), local BIP143
//!    signature, idempotent broadcast; spendables are invalidated after a
//!    successful send so a stale-UTXO double spend is impossible without
//!    a fresh sync;
//! 5. `btc_tx_status` / `btc_history` / `btc_receive_address` — views.

use anyhow::{anyhow, Result};

use chains::bitcoin::keys::{AccountPubkeys, BRANCH_EXTERNAL, BRANCH_INTERNAL};
use chains::bitcoin::scan::{
    collect_utxos, discover, history_with_amounts, tx_status, wallet_balance, HistoryDirection,
    TxStatus,
};
use chains::bitcoin::tx::{
    estimate_fee_rates_with_fallback, idempotent_broadcast, plan_transfer, SignedTransferBuilder,
};
use chains::electrum::{ElectrumGateway, Gateway};
use zeroize::Zeroizing;

use key_manager::from_phrase;
use wallet_core::WalletManager;

use crate::btc_session::{
    invalidate_utxos, network_from_code, snapshot, store_sync, with_lock, with_session, BtcSession,
};
use crate::production_kdf;

/// Server identity shown on the network-info screen. All public data.
#[derive(Debug)]
pub struct BtcUnlockDto {
    pub network_code: u32,
    pub network_display: String,
    pub server_url: String,
    pub server_version: String,
    pub protocol_min: String,
    pub protocol_max: String,
    /// Genesis hash as reported by the server (verified before use).
    pub genesis_hash_hex: String,
    pub tip_height: u32,
    /// base58 xpub of the BIP84 account (watch-only handle).
    pub account_xpub: String,
}

/// Unlock a wallet for BTC operations (must be re-done per app run; `btc_lock`
/// wipes the in-Rust seed).
///
/// `network_code`: 0 mainnet, 1 testnet3, 2 testnet4.
/// `server_url`: `ssl://host:port` or `tcp://host:port` (public Electrum
/// servers; verified examples in docs/coins/BTC.md).
pub fn btc_unlock(
    wallets_dir: String,
    wallet_id: String,
    password: String,
    network_code: u32,
    server_url: String,
) -> Result<BtcUnlockDto> {
    let network = network_from_code(network_code)?;

    // 1. Decrypt inside Rust; only the derived seed stays (zeroized both in
    //    the vault payload and in the session copy below).
    let manager = WalletManager::open(&wallets_dir, production_kdf())?;
    let secrets = manager.reveal_secrets(&wallet_id, &password)?;
    let mnemonic = from_phrase(&secrets.phrase)?;
    let seed = mnemonic.to_seed(&secrets.passphrase);

    // 2. Connect and enforce the fund-safety network check (genesis).
    let gateway = ElectrumGateway::connect(&server_url, network)?;
    let (server_version, protocol_min, protocol_max, server_genesis) = gateway.server_features()?;
    if server_genesis != network.genesis_hash() {
        return Err(anyhow!(
            "server {} serves a different network (genesis {} instead of {} for {}) — refusing to use it",
            server_url,
            hex::encode(server_genesis),
            hex::encode(network.genesis_hash()),
            network.display_name(),
        ));
    }
    let tip_height = gateway.tip_height()?;

    // 3. Watch-only account keys; the hardened derivation already happened
    //    and the private keys are dropped inside `from_seed`.
    let account_pub =
        AccountPubkeys::from_seed(seed.as_bytes(), network, 0).map_err(|e| anyhow!("{e}"))?;
    let account_xpub = account_pub.account_xpub().to_string();

    let mut guard = with_lock()?;
    *guard = Some(BtcSession {
        network,
        server_url: server_url.clone(),
        account: 0,
        seed: Zeroizing::new(*seed.as_bytes()),
        account_pub,
        gateway,
        discovery: None,
        utxos: None,
    });

    Ok(BtcUnlockDto {
        network_code: network.code(),
        network_display: network.display_name().to_string(),
        server_url,
        server_version,
        protocol_min,
        protocol_max,
        genesis_hash_hex: hex::encode(server_genesis),
        tip_height,
        account_xpub,
    })
}

/// Lock the session: the seed is zeroized and dropped, nothing else survives.
pub fn btc_lock() -> Result<()> {
    let mut guard = with_lock()?;
    *guard = None; // BtcSession drops → Zeroizing wipes the seed
    Ok(())
}

/// One derived address (public data only).
#[derive(Debug)]
pub struct BtcAddressDto {
    pub address: String,
    /// 0 = receiving, 1 = change.
    pub branch: u32,
    pub index: u32,
    /// BIP84 path, e.g. `m/84'/1'/0'/0/3`.
    pub path: String,
    /// `true` when the address has on-chain history (from discovery).
    pub used: bool,
}

fn address_dto(address: &chains::bitcoin::keys::DerivedAddress, used: bool) -> BtcAddressDto {
    BtcAddressDto {
        address: address.address.clone(),
        branch: address.branch,
        index: address.index,
        path: address.path.clone(),
        used,
    }
}

fn derive_dto(
    account: &AccountPubkeys,
    branch: u32,
    index: u32,
    used: bool,
) -> Result<BtcAddressDto> {
    let address = account
        .derive_address(branch, index)
        .map_err(|e| anyhow!("{e}"))?;
    Ok(address_dto(&address, used))
}

/// Result of a full sync. `next_receive` is the fresh address to show in the
/// Receive screen (the first index past the last used one, gap-limit kept).
#[derive(Debug)]
pub struct BtcSyncDto {
    pub network_code: u32,
    pub confirmed_sat: u64,
    /// Mempool delta (can be negative, e.g. a spend of confirmed coins).
    pub unconfirmed_delta_sat: i64,
    pub utxo_count: u32,
    /// Every scanned address that has on-chain history.
    pub used_addresses: Vec<BtcAddressDto>,
    pub next_receive: BtcAddressDto,
    pub next_change: BtcAddressDto,
    pub tip_height: u32,
    pub server_url: String,
}

/// Discover all wallet addresses (gap-limited), compute the balance and the
/// spendable set. Run this after unlock (and after every send, see
/// `btc_send`).
pub fn btc_sync(gap_limit: u32) -> Result<BtcSyncDto> {
    let (gateway, account_pub, network) = snapshot()?;

    let discovery = discover(&gateway, &account_pub, gap_limit).map_err(|e| anyhow!("{e}"))?;
    let balance = wallet_balance(&gateway, &discovery).map_err(|e| anyhow!("{e}"))?;
    let utxos = collect_utxos(&gateway, &discovery).map_err(|e| anyhow!("{e}"))?;
    let utxo_count = utxos.len() as u32;
    let used_addresses = discovery
        .slots()
        .filter(|s| s.used)
        .map(|s| BtcAddressDto {
            address: s.address.clone(),
            branch: s.branch,
            index: s.index,
            path: s.path.clone(),
            used: true,
        })
        .collect();

    let next_receive = derive_dto(
        &account_pub,
        BRANCH_EXTERNAL,
        discovery.external.next_index(),
        false,
    )?;
    let next_change = derive_dto(
        &account_pub,
        BRANCH_INTERNAL,
        discovery.internal.next_index(),
        false,
    )?;

    store_sync(discovery, utxos)?;

    Ok(BtcSyncDto {
        network_code: network.code(),
        confirmed_sat: balance.confirmed_sat,
        unconfirmed_delta_sat: balance.unconfirmed_delta_sat,
        utxo_count,
        used_addresses,
        next_receive,
        next_change,
        tip_height: gateway.tip_height()?,
        server_url: gateway.url().to_string(),
    })
}

/// The fresh receiving address (from the last sync; index 0 before it).
pub fn btc_receive_address() -> Result<BtcAddressDto> {
    with_session(|s| {
        let next_index = s
            .discovery
            .as_ref()
            .map(|d| d.external.next_index())
            .unwrap_or(0);
        derive_dto(&s.account_pub, BRANCH_EXTERNAL, next_index, false)
    })
}

/// Fee presets in sat/vB (integers). `fallback == true` means the server had
/// no fee estimate (Electrum answers -1) and the values are the conservative
/// static presets — surfaced so the UI never presents a guess as measured.
#[derive(Debug)]
pub struct BtcFeeRatesDto {
    pub fast_sat_vb: u64,
    pub normal_sat_vb: u64,
    pub slow_sat_vb: u64,
    pub fallback: bool,
}

/// Fee presets for the 1/3/6-block depth (fast/normal/slow): live server
/// estimates when available, conservative fallback otherwise. Never an error
/// for a missing estimate — the missing one is always decidable.
pub fn btc_fees() -> Result<BtcFeeRatesDto> {
    let (gateway, _account, _network) = snapshot()?;
    let (rates, fallback) =
        estimate_fee_rates_with_fallback(&gateway).map_err(|e| anyhow!("{e}"))?;
    Ok(BtcFeeRatesDto {
        fast_sat_vb: rates.fast_sat_vb,
        normal_sat_vb: rates.normal_sat_vb,
        slow_sat_vb: rates.slow_sat_vb,
        fallback,
    })
}

/// Result of `btc_send`: everything the confirmation screen shows.
/// Note `already_known`: the server already had this transaction (an idempotent
/// replay) — the tx is NOT duplicated on the network.
#[derive(Debug)]
pub struct BtcSendResultDto {
    pub txid: String,
    /// Consensus hex of the signed transaction (display/record only).
    pub raw_hex: String,
    pub already_known: bool,
    pub recipient: String,
    pub amount_sat: u64,
    pub fee_sat: u64,
    pub vsize: u64,
    pub fee_sat_per_vb: u64,
    pub change_address: Option<String>,
    pub change_sat: Option<u64>,
    /// Status snapshot right after the broadcast ("mempool", or "unknown"
    /// when the server does not list it under the scanned addresses yet).
    pub status: String,
}

/// Scripts of every scanned address (for status lookups). Errors when no
/// sync has happened yet.
fn scanned_scripts() -> Result<Vec<Vec<u8>>> {
    with_session(|s| {
        Ok(s.discovery
            .as_ref()
            .ok_or_else(|| anyhow!("no scanned addresses — run btc_sync first"))?
            .slots()
            .map(|slot| slot.script_pubkey.clone())
            .collect::<Vec<_>>())
    })
}

/// Plan, sign (locally, BIP143) and broadcast a transfer.
///
/// Requires a successful `btc_sync` first — sends are built from the exact
/// spendable set discovered then; after a successful send the set is
/// invalidated (a stale set would double-spend), so run `btc_sync` again
/// before the next send. The recipient may be any standard address of the
/// session network (P2WPKH/P2SH/P2PKH/P2TR; network mismatch is enforced).
pub fn btc_send(recipient: String, amount_sat: u64, fee_sat_vb: u64) -> Result<BtcSendResultDto> {
    let (gateway, _account_pub, _network) = snapshot()?;

    // Tip height first (locktime): network call outside the session lock.
    let tip_height = gateway.tip_height()?;

    // Plan + sign under the lock — CPU-only work with the seed, no I/O.
    let signed = with_session(|s| {
        let utxos = s
            .utxos
            .as_ref()
            .ok_or_else(|| anyhow!("no spendable set — run btc_sync before sending"))?;
        let change_index = s
            .discovery
            .as_ref()
            .map(|d| d.internal.next_index())
            .unwrap_or(0);
        let change = s
            .account_pub
            .derive_address(BRANCH_INTERNAL, change_index)
            .map_err(|e| anyhow!("{e}"))?;
        let plan = plan_transfer(
            s.network, &recipient, amount_sat, fee_sat_vb, utxos, &change,
        )
        .map_err(|e| anyhow!("{e}"))?;
        let builder = SignedTransferBuilder {
            seed: &s.seed,
            network: s.network,
            account: s.account,
        };
        builder.sign(&plan, tip_height).map_err(|e| anyhow!("{e}"))
    })?;

    // Idempotent broadcast outside the lock.
    let outcome = idempotent_broadcast(&gateway, &signed).map_err(|e| anyhow!("{e}"))?;

    // Spend-safety: the spendable set is stale now; force a re-sync before
    // any further send (prevents a repeated send from the same coins).
    invalidate_utxos()?;

    let (already_known, status) = match outcome {
        chains::electrum::BroadcastOutcome::Sent(txid) => {
            // Best-effort fresh status right after the broadcast.
            let scripts = scanned_scripts().unwrap_or_default();
            let st = tx_status(&gateway, &scripts, txid)
                .map(|s| map_status(&s))
                .unwrap_or_else(|_| "unknown".to_string());
            (false, st)
        }
        chains::electrum::BroadcastOutcome::AlreadyKnown(_) => (true, "mempool".to_string()),
    };

    Ok(BtcSendResultDto {
        txid: signed.txid.to_string(),
        raw_hex: signed.raw_hex,
        already_known,
        recipient: signed.plan.recipient,
        amount_sat: signed.plan.recipient_amount_sat,
        fee_sat: signed.plan.fee_sat,
        vsize: signed.plan.vsize,
        fee_sat_per_vb: signed.plan.fee_sat_per_vb,
        change_address: signed.plan.change.as_ref().map(|c| c.0.clone()),
        change_sat: signed.plan.change.as_ref().map(|c| c.2),
        status,
    })
}

/// Transaction status as seen by the server right now.
#[derive(Debug)]
pub struct BtcTxStatusDto {
    /// "unknown" (not under any scanned address) | "mempool" | "confirmed".
    pub state: String,
    pub height: Option<u32>,
    /// `tip − height + 1`; `None` in the mempool/unknown states.
    pub confirmations: Option<u32>,
    pub txid: String,
}

fn map_status(status: &TxStatus) -> String {
    match status {
        TxStatus::Unknown => "unknown".to_string(),
        TxStatus::Mempool => "mempool".to_string(),
        TxStatus::Confirmed { .. } => "confirmed".to_string(),
    }
}

/// Check a transaction's confirmation status (requires a prior `btc_sync`).
pub fn btc_tx_status(txid: String) -> Result<BtcTxStatusDto> {
    let txid: ::bitcoin::Txid = txid
        .parse()
        .map_err(|e| anyhow!("invalid txid {txid:?}: {e}"))?;
    let (gateway, _account, _network) = snapshot()?;
    let scripts = scanned_scripts()?;
    let status = tx_status(&gateway, &scripts, txid).map_err(|e| anyhow!("{e}"))?;
    Ok(match status {
        TxStatus::Unknown => BtcTxStatusDto {
            state: "unknown".to_string(),
            height: None,
            confirmations: None,
            txid: txid.to_string(),
        },
        TxStatus::Mempool => BtcTxStatusDto {
            state: "mempool".to_string(),
            height: None,
            confirmations: None,
            txid: txid.to_string(),
        },
        TxStatus::Confirmed {
            height,
            confirmations,
        } => BtcTxStatusDto {
            state: "confirmed".to_string(),
            height: Some(height),
            confirmations: Some(confirmations),
            txid: txid.to_string(),
        },
    })
}

/// One wallet transaction with its amounts (satoshis only).
#[derive(Debug)]
pub struct BtcHistoryItemDto {
    pub txid: String,
    /// Block height; -1 = mempool.
    pub height: i64,
    /// "incoming" | "outgoing" | "internal".
    pub direction: String,
    /// Total value paid to wallet addresses.
    pub received_sat: u64,
    /// Net value that left the wallet (0 for incoming/internal).
    pub sent_net_sat: u64,
    pub fee_sat: Option<u64>,
}

/// The wallet history with computed amounts (requires a prior `btc_sync`).
/// Capped by the scan module's MAX_HISTORY_ITEMS safety valve.
pub fn btc_history() -> Result<Vec<BtcHistoryItemDto>> {
    let (gateway, _account, _network) = snapshot()?;
    let discovery = with_session(|s| Ok(s.discovery.clone()))?
        .ok_or_else(|| anyhow!("no scanned addresses — run btc_sync first"))?;
    let items = history_with_amounts(&gateway, &discovery).map_err(|e| anyhow!("{e}"))?;
    Ok(items
        .into_iter()
        .map(|item| BtcHistoryItemDto {
            txid: item.txid.to_string(),
            height: item.height,
            direction: match item.direction {
                Some(HistoryDirection::Incoming) => "incoming".to_string(),
                Some(HistoryDirection::Outgoing) => "outgoing".to_string(),
                Some(HistoryDirection::Internal) => "internal".to_string(),
                None => "unknown".to_string(),
            },
            received_sat: item.received_sat,
            sent_net_sat: item.sent_net_sat,
            fee_sat: item.fee_sat,
        })
        .collect())
}
