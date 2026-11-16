//! BCH operations exposed to the UI. 1:1 with `ltc.rs` (the coin shares the
//! Electrum protocol and the same scan pipeline); the signing differs
//! (UAHF forkid digest) and is delegated to `chains::cash::bch_signed_transfer`.
//!
//! Owner decision recorded 16.11.2026: no manual server config — the
//! candidate list lives in the core (`SERVER_MAINNET_CANDIDATES`,
//! genesis-checked on connect), transient failures rotate candidates with
//! the failed server last (same polite retry as BTC/LTC).

use anyhow::{anyhow, Result};

use chains::bitcoin::keys::{BRANCH_EXTERNAL, BRANCH_INTERNAL};
use chains::bitcoin::scan::{
    collect_utxos, discover, history_with_amounts, tx_status, wallet_balance, HistoryDirection,
    TxStatus,
};
use chains::bitcoin::tx::{estimate_fee_rates_with_fallback, idempotent_broadcast};
use chains::cash::{
    bch_failover_candidates, bch_plan_transfer_addr, bch_signed_transfer, BchAccount, BchGateway,
    BchNetwork, GENESIS_MAINNET_HEX,
};
use chains::electrum::Gateway;
use chains::ChainError;
use zeroize::Zeroizing;

use key_manager::from_phrase;
use wallet_core::WalletManager;

use crate::bch_session::{
    after_send, snapshot, store_gateway, store_sync, with_lock, with_session,
};
use crate::production_kdf;

/// Server identity shown on the network-info screen. All public data.
#[derive(Debug)]
pub struct BchUnlockDto {
    pub network_display: String,
    pub server_url: String,
    pub server_version: String,
    pub protocol_min: String,
    pub protocol_max: String,
    /// Genesis hash as reported by the server (verified before use).
    pub genesis_hash_hex: String,
    pub tip_height: u32,
    /// base58 xpub of `m/44'/145'/account'` (watch-only handle).
    pub account_xpub: String,
}

/// The candidate Electrum-BCH servers (core-owned list, order = liveness).
pub fn bch_servers() -> Vec<String> {
    chains::cash::SERVER_MAINNET_CANDIDATES
        .iter()
        .map(|s| s.to_string())
        .collect()
}

/// Unlock a wallet for BCH operations (per app run; `bch_lock` wipes the
/// in-Rust seed).
///
/// Unified app session (owner decision 15.11.2026): an EMPTY password means
/// «reuse the cached one» — the password cache lives inside Rust (zeroized,
/// never crosses FFI) and is wiped when the last coin session locks. A
/// successful unlock (re)populates the cache.
pub fn bch_unlock(
    wallets_dir: String,
    wallet_id: String,
    password: String,
    server_url: String,
) -> Result<BchUnlockDto> {
    let effective: Zeroizing<String> = if password.trim().is_empty() {
        crate::session_password::get_for(&wallet_id)?.ok_or_else(|| {
            anyhow!("no cached password — prompt the user for the wallet password")
        })?
    } else {
        Zeroizing::new(password)
    };

    // 1. Decrypt inside Rust; only the derived seed stays (zeroized).
    //    Failed decryptions are throttled the same way as BTC.
    let manager = WalletManager::open(&wallets_dir, production_kdf())?;
    let secrets = match manager.reveal_secrets(&wallet_id, &effective) {
        Ok(secrets) => secrets,
        Err(e) => {
            crate::unlock_throttle::register_failure(&wallet_id);
            return Err(anyhow!("{e}"));
        }
    };
    crate::unlock_throttle::register_success(&wallet_id);
    let mnemonic = from_phrase(&secrets.phrase)?;
    let seed = mnemonic.to_seed(&secrets.passphrase);

    // 2. Connect and enforce the fund-safety network check (genesis —
    //    BCH mainnet genesis is the BTC one; a server serving any other
    //    chain/network is refused).
    let gateway = BchGateway::connect(&server_url)?;
    let (server_version, protocol_min, protocol_max, server_genesis) = gateway.server_features()?;
    let server_genesis_hex = hex::encode(server_genesis);
    if server_genesis_hex != GENESIS_MAINNET_HEX {
        return Err(anyhow!(
            "server {server_url} serves a different network (genesis {server_genesis_hex} instead of {GENESIS_MAINNET_HEX} for Bitcoin Cash mainnet) — refusing to use it"
        ));
    }
    let tip_height = gateway.tip_height()?;

    // 3. Watch-only account keys; hardened derivation already happened,
    //    private keys dropped inside `from_seed`.
    let account_pub = BchAccount::from_seed(seed.as_bytes(), BchNetwork::Mainnet, 0)
        .map_err(|e| anyhow!("{e}"))?;
    let account_xpub = account_pub.account_xpub().to_string();

    // Full success → THIS wallet now unlocks silently on other coins too.
    crate::session_password::store_for(&wallet_id, &effective)?;

    let mut guard = with_lock()?;
    *guard = Some(crate::bch_session::BchSession {
        server_url: gateway.url().to_string(),
        account: 0,
        seed: Zeroizing::new(*seed.as_bytes()),
        account_pub,
        gateway,
        discovery: None,
        utxos: None,
    });

    Ok(BchUnlockDto {
        network_display: "Bitcoin Cash mainnet".to_string(),
        server_url: server_url.clone(),
        server_version,
        protocol_min,
        protocol_max,
        genesis_hash_hex: server_genesis_hex,
        tip_height,
        account_xpub,
    })
}

/// Lock the session: the seed is zeroized and dropped. Last locked coin
/// session ⇒ password cache is wiped too (full logout).
pub fn bch_lock() -> Result<()> {
    let mut guard = with_lock()?;
    *guard = None; // BchSession drops → Zeroizing wipes the seed
    drop(guard);
    crate::session_password::erase_if_all_locked()?;
    Ok(())
}

/// Non-secret session state for the UI; `None` when locked.
#[derive(Debug)]
pub struct BchSessionStateDto {
    pub network_display: String,
    pub server_url: String,
    pub account: u32,
    /// base58 xpub of `m/44'/145'/account'` (watch-only handle).
    pub account_xpub: String,
}

/// Non-secret session state for the UI; `None` when locked.
pub fn bch_session_state() -> Result<Option<BchSessionStateDto>> {
    let guard = with_lock()?;
    Ok(guard.as_ref().map(|s| BchSessionStateDto {
        network_display: "Bitcoin Cash mainnet".to_string(),
        server_url: s.server_url.clone(),
        account: s.account,
        account_xpub: s.account_pub.account_xpub().to_string(),
    }))
}

/// One derived address (public data only).
#[derive(Debug)]
pub struct BchAddressDto {
    pub address: String,
    /// 0 = receiving, 1 = change.
    pub branch: u32,
    pub index: u32,
    /// Path text, e.g. `m/44'/145'/0'/0/3`.
    pub path: String,
    /// `true` when the address has on-chain history (from discovery).
    pub used: bool,
}

fn address_dto(address: &chains::bitcoin::keys::DerivedAddress, used: bool) -> BchAddressDto {
    BchAddressDto {
        address: address.address.clone(),
        branch: address.branch,
        index: address.index,
        path: address.path.clone(),
        used,
    }
}

fn derive_dto(account: &BchAccount, branch: u32, index: u32, used: bool) -> Result<BchAddressDto> {
    let address = account
        .derive_address(branch, index)
        .map_err(|e| anyhow!("{e}"))?;
    Ok(address_dto(&address, used))
}

/// Result of a full sync. `next_receive` is the fresh address to show in the
/// Receive screen (the first index past the last used one, gap-limit kept).
#[derive(Debug)]
pub struct BchSyncDto {
    pub confirmed_sat: u64,
    /// Mempool delta (can be negative, e.g. a spend of confirmed coins).
    pub unconfirmed_delta_sat: i64,
    pub utxo_count: u32,
    /// Every scanned address that has on-chain history.
    pub used_addresses: Vec<BchAddressDto>,
    pub next_receive: BchAddressDto,
    pub next_change: BchAddressDto,
    pub tip_height: u32,
    pub server_url: String,
}

/// Discover all wallet addresses (gap-limited), compute the balance.
///
/// Same retry discipline as BTC/LTC: ONE reconnect retry against the next
/// core-owned candidate (the failed server goes last).
pub fn bch_sync(gap_limit: u32) -> Result<BchSyncDto> {
    let (gateway, account_pub) = snapshot()?;
    match attempt_sync(&gateway, &account_pub, gap_limit) {
        Ok(dto) => Ok(dto),
        Err(e) => {
            if !crate::is_transient_sync_error(&e) {
                return Err(anyhow!("{e}"));
            }
            let mut last_err = e;
            for url in bch_failover_candidates(gateway.url()).iter().take(2) {
                let fresh = match BchGateway::connect(url) {
                    Ok(g) => g,
                    Err(ce) => {
                        last_err = ce;
                        continue;
                    }
                };
                store_gateway(fresh).map_err(|err| anyhow!("{err}"))?;
                let (gateway, account_pub) = snapshot()?;
                match attempt_sync(&gateway, &account_pub, gap_limit) {
                    Ok(dto) => return Ok(dto),
                    Err(ce) => {
                        if !crate::is_transient_sync_error(&ce) {
                            return Err(anyhow!("{ce}"));
                        }
                        last_err = ce;
                    }
                }
            }
            Err(anyhow!("{last_err}"))
        }
    }
}

fn attempt_sync(
    gateway: &BchGateway,
    account_pub: &BchAccount,
    gap_limit: u32,
) -> Result<BchSyncDto, ChainError> {
    let discovery = discover(gateway, account_pub, gap_limit)?;
    let balance = wallet_balance(gateway, &discovery)?;
    // UTXO set: the exact spendable set the send layer consumes; a
    // successful send invalidates it (double-spend guard, same as BTC/LTC).
    let utxos = collect_utxos(gateway, &discovery)?;
    let utxo_count = utxos.len() as u32;
    let used_addresses: Vec<BchAddressDto> = discovery
        .slots()
        .filter(|s| s.used)
        .map(|s| BchAddressDto {
            address: s.address.clone(),
            branch: s.branch,
            index: s.index,
            path: s.path.clone(),
            used: true,
        })
        .collect();

    let tip_height = gateway.tip_height()?;
    let next_receive = account_pub
        .derive_address(BRANCH_EXTERNAL, discovery.external.next_index())
        .map(|a| address_dto(&a, false))?;
    let next_change = account_pub
        .derive_address(BRANCH_INTERNAL, discovery.internal.next_index())
        .map(|a| address_dto(&a, false))?;
    store_sync(discovery, utxos).map_err(|e| ChainError::Internal(format!("{e}")))?;

    Ok(BchSyncDto {
        confirmed_sat: balance.confirmed_sat,
        unconfirmed_delta_sat: balance.unconfirmed_delta_sat,
        utxo_count,
        used_addresses,
        next_receive,
        next_change,
        tip_height,
        server_url: gateway.url().to_string(),
    })
}

/// The fresh receiving address (from the last sync; index 0 before it).
pub fn bch_receive_address() -> Result<BchAddressDto> {
    with_session(|s| {
        let next_index = s
            .discovery
            .as_ref()
            .map(|d| d.external.next_index())
            .unwrap_or(0);
        derive_dto(&s.account_pub, BRANCH_EXTERNAL, next_index, false)
    })
}

/// Transaction status as seen by the server right now.
#[derive(Debug)]
pub struct BchTxStatusDto {
    /// "unknown" (not under any scanned address) | "mempool" | "confirmed".
    pub state: String,
    pub height: Option<u32>,
    /// `tip − height + 1`; `None` in the mempool/unknown states.
    pub confirmations: Option<u32>,
    pub txid: String,
}

/// Scripts of every scanned address (for status lookups). Errors when no
/// sync has happened yet.
fn scanned_scripts() -> Result<Vec<Vec<u8>>> {
    with_session(|s| {
        Ok(s.discovery
            .as_ref()
            .ok_or_else(|| anyhow!("no scanned addresses — run bch_sync first"))?
            .slots()
            .map(|slot| slot.script_pubkey.clone())
            .collect::<Vec<_>>())
    })
}

/// Check a transaction's confirmation status (requires a prior `bch_sync`).
pub fn bch_tx_status(txid: String) -> Result<BchTxStatusDto> {
    let txid: ::bitcoin::Txid = txid
        .parse()
        .map_err(|e| anyhow!("invalid txid {txid:?}: {e}"))?;
    let (gateway, _account) = snapshot()?;
    let scripts = scanned_scripts()?;
    let status = tx_status(&gateway, &scripts, txid).map_err(|e| anyhow!("{e}"))?;
    Ok(match status {
        TxStatus::Unknown => BchTxStatusDto {
            state: "unknown".to_string(),
            height: None,
            confirmations: None,
            txid: txid.to_string(),
        },
        TxStatus::Mempool => BchTxStatusDto {
            state: "mempool".to_string(),
            height: None,
            confirmations: None,
            txid: txid.to_string(),
        },
        TxStatus::Confirmed {
            height,
            confirmations,
        } => BchTxStatusDto {
            state: "confirmed".to_string(),
            height: Some(height),
            confirmations: Some(confirmations),
            txid: txid.to_string(),
        },
    })
}

/// One wallet transaction with its amounts (satoshi amounts).
#[derive(Debug)]
pub struct BchHistoryItemDto {
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

/// The wallet history with computed amounts (requires a prior `bch_sync`).
/// Honest truncation, same contract as BTC (see `BtcHistoryDto`).
#[derive(Debug)]
pub struct BchHistoryDto {
    pub items: Vec<BchHistoryItemDto>,
    pub total_entries: i64,
    pub truncated: bool,
}

pub fn bch_history() -> Result<BchHistoryDto> {
    let (gateway, _account) = snapshot()?;
    let discovery = with_session(|s| Ok(s.discovery.clone()))?
        .ok_or_else(|| anyhow!("no scanned addresses — run bch_sync first"))?;
    let resolution = history_with_amounts(&gateway, &discovery).map_err(|e| anyhow!("{e}"))?;
    Ok(BchHistoryDto {
        items: resolution
            .items
            .into_iter()
            .map(|item| BchHistoryItemDto {
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
            .collect(),
        total_entries: resolution.total_entries as i64,
        truncated: resolution.truncated,
    })
}

// ------------------------------------------------------------- sends ----

/// Fee presets in sat/byte (integers). `fallback == true` means the server
/// had no fee estimate and the conservative presets are used — surfaced so
/// the UI never presents a guess as a server measurement.
///
/// BCH has no BIP141 weights: the "sat/vB" field name is kept for the UI
/// shape (1:1 with BTC/LTC screens) while the core math is sat/byte.
#[derive(Debug)]
pub struct BchFeeRatesDto {
    pub fast_sat_vb: u64,
    pub normal_sat_vb: u64,
    pub slow_sat_vb: u64,
    pub fallback: bool,
}

/// Fee presets for the 1/3/6-block depth. The Electrum protocol unit is
/// "coin per kilobyte" and 1 BCH = 1e8 sats — the same integers as BTC.
pub fn bch_fees() -> Result<BchFeeRatesDto> {
    let (gateway, _account) = snapshot()?;
    let (rates, fallback) =
        estimate_fee_rates_with_fallback(&gateway).map_err(|e| anyhow!("{e}"))?;
    Ok(BchFeeRatesDto {
        fast_sat_vb: rates.fast_sat_vb,
        normal_sat_vb: rates.normal_sat_vb,
        slow_sat_vb: rates.slow_sat_vb,
        fallback,
    })
}

/// Result of `bch_send`: everything the confirmation screen shows.
#[derive(Debug)]
pub struct BchSendResultDto {
    pub txid: String,
    /// Consensus hex of the signed transaction (display/record only).
    pub raw_hex: String,
    pub already_known: bool,
    pub recipient: String,
    pub amount_sat: u64,
    pub fee_sat: u64,
    pub size_bytes: u64,
    pub fee_sat_per_byte: u64,
    pub change_address: Option<String>,
    pub change_sat: Option<u64>,
    /// Status snapshot right after the broadcast ("mempool" or "unknown").
    pub status: String,
}

/// Plan, sign (locally, UAHF forkid digest) and broadcast a BCH transfer.
///
/// Requires a successful `bch_sync` first (sends are built from the exact
/// spendable set discovered then; after a success the set is invalidated —
/// a stale set would double-spend). Recipient: `bitcoincash:q…` (P2KH, cashaddr
/// or legacy `1…`; `3…`/`p…` P2SH 20-byte hashes are accepted; MWEB-style
/// non-P2KH/P2SH forms are refused honestly.
pub fn bch_send(
    recipient: String,
    amount_sat: u64,
    fee_sat_per_byte: u64,
) -> Result<BchSendResultDto> {
    let (gateway, _account_pub) = snapshot()?;

    // Tip height first (locktime): network call outside the session lock.
    let tip_height = gateway.tip_height()?;

    // Plan + sign under the lock — CPU-only work with the seed, no I/O.
    let signed = with_session(|s| {
        let utxos = s
            .utxos
            .as_ref()
            .ok_or_else(|| anyhow!("no spendable set — run bch_sync before sending"))?;
        let change_index = s
            .discovery
            .as_ref()
            .map(|d| d.internal.next_index())
            .unwrap_or(0);
        let change = s
            .account_pub
            .derive_address(BRANCH_INTERNAL, change_index)
            .map_err(|e| anyhow!("{e}"))?;
        let plan = bch_plan_transfer_addr(&recipient, amount_sat, fee_sat_per_byte, utxos, &change)
            .map_err(|e| anyhow!("{e}"))?;
        bch_signed_transfer(&plan, &s.seed, BchNetwork::Mainnet, s.account, tip_height)
            .map_err(|e| anyhow!("{e}"))
    })?;

    // Idempotent broadcast outside the lock. Same rule as BTC/LTC: a FAILED
    // broadcast is still an attempt — the spendable set is invalidated
    // either way so no second send can silently reuse the same coins.
    let outcome = match idempotent_broadcast(&gateway, &signed) {
        Ok(outcome) => outcome,
        Err(e) => {
            after_send().map_err(|err| anyhow!("{err}"))?;
            return Err(anyhow!("{e}"));
        }
    };

    // Success: force a re-sync before any further send and advance the
    // change index (two consecutive sends never reuse a change address).
    after_send().map_err(|e| anyhow!("{e}"))?;

    let (already_known, status) = match outcome {
        chains::electrum::BroadcastOutcome::Sent(txid) => {
            let scripts = scanned_scripts().unwrap_or_default();
            let st = tx_status(&gateway, &scripts, txid)
                .map(|s| match s {
                    TxStatus::Unknown => "unknown".to_string(),
                    TxStatus::Mempool => "mempool".to_string(),
                    TxStatus::Confirmed { .. } => "confirmed".to_string(),
                })
                .unwrap_or_else(|_| "unknown".to_string());
            (false, st)
        }
        chains::electrum::BroadcastOutcome::AlreadyKnown(_) => (true, "mempool".to_string()),
    };

    Ok(BchSendResultDto {
        txid: signed.txid.to_string(),
        raw_hex: signed.raw_hex,
        already_known,
        recipient: signed.plan.recipient,
        amount_sat: signed.plan.recipient_amount_sat,
        fee_sat: signed.plan.fee_sat,
        size_bytes: signed.plan.vsize,
        fee_sat_per_byte: signed.plan.fee_sat_per_vb,
        change_address: signed.plan.change.as_ref().map(|c| c.0.clone()),
        change_sat: signed.plan.change.as_ref().map(|c| c.2),
        status,
    })
}
