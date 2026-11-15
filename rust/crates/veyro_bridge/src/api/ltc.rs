//! LTC operations exposed to the UI. Thin wrappers over the `chains` crate
//! (same shape as `btc.rs`); the receive-only milestone: unlock, balance +
//! discovery sync, receive address, history. Sends arrive with the LTC send
//! milestone (same sighash model, separate review).
//!
//! Server selection follows the owner decision ("autopick, no manual
//! server config"): the candidate list lives in the core
//! (`SERVERS_MAINNET`, genesis-checked on connect), the UI gets it via
//! [`ltc_servers`] and retries transient failures the same polite way it
//! does for BTC.

use anyhow::{anyhow, Result};

use chains::bitcoin::keys::{BRANCH_EXTERNAL, BRANCH_INTERNAL};
use chains::bitcoin::scan::{
    discover, history_with_amounts, tx_status, wallet_balance, HistoryDirection, TxStatus,
};
use chains::electrum::Gateway;
use chains::litecoin::{LtcAccount, LtcGateway, GENESIS_MAINNET_HEX};
use zeroize::Zeroizing;

use key_manager::from_phrase;
use wallet_core::WalletManager;

use crate::ltc_session::{snapshot, store_gateway, store_sync, with_lock, with_session};
use crate::production_kdf;

/// Server identity shown on the network-info screen. All public data.
#[derive(Debug)]
pub struct LtcUnlockDto {
    pub network_display: String,
    pub server_url: String,
    pub server_version: String,
    pub protocol_min: String,
    pub protocol_max: String,
    /// Genesis hash as reported by the server (verified before use).
    pub genesis_hash_hex: String,
    pub tip_height: u32,
    /// base58 xpub of `m/84'/2'/account'` (watch-only handle).
    pub account_xpub: String,
}

/// The candidate Electrum-LTC servers (core-owned list, order = liveness).
pub fn ltc_servers() -> Vec<String> {
    chains::litecoin::SERVERS_MAINNET
        .iter()
        .map(|s| s.to_string())
        .collect()
}

/// Unlock a wallet for LTC operations (must be re-done per app run;
/// `ltc_lock` wipes the in-Rust seed). The genesis check is the fund-safety
/// gate: a server that does not serve the LTC mainnet genesis is refused.
pub fn ltc_unlock(
    wallets_dir: String,
    wallet_id: String,
    password: String,
    server_url: String,
) -> Result<LtcUnlockDto> {
    // 1. Decrypt inside Rust; only the derived seed stays (zeroized).
    let manager = WalletManager::open(&wallets_dir, production_kdf())?;
    let secrets = manager.reveal_secrets(&wallet_id, &password)?;
    let mnemonic = from_phrase(&secrets.phrase)?;
    let seed = mnemonic.to_seed(&secrets.passphrase);

    // 2. Connect and enforce the fund-safety network check (genesis).
    let gateway = LtcGateway::connect(&server_url)?;
    let (server_version, protocol_min, protocol_max, server_genesis) = gateway.server_features()?;
    let server_genesis_hex = hex::encode(server_genesis);
    if server_genesis_hex != GENESIS_MAINNET_HEX {
        return Err(anyhow!(
            "server {server_url} serves a different network (genesis {server_genesis_hex} instead of {GENESIS_MAINNET_HEX} for Litecoin mainnet) — refusing to use it"
        ));
    }
    let tip_height = gateway.tip_height()?;

    // 3. Watch-only account keys; the hardened derivation already happened
    //    and the private keys are dropped inside `from_seed`.
    let account_pub = LtcAccount::from_seed(seed.as_bytes(), 0).map_err(|e| anyhow!("{e}"))?;
    let account_xpub = account_pub.account_xpub().to_string();

    let mut guard = with_lock()?;
    *guard = Some(crate::ltc_session::LtcSession {
        server_url: gateway.url().to_string(),
        account: 0,
        seed: Zeroizing::new(*seed.as_bytes()),
        account_pub,
        gateway,
        discovery: None,
    });

    Ok(LtcUnlockDto {
        network_display: "Litecoin mainnet".to_string(),
        server_url: server_url.clone(),
        server_version,
        protocol_min,
        protocol_max,
        genesis_hash_hex: server_genesis_hex,
        tip_height,
        account_xpub,
    })
}

/// Lock the session: the seed is zeroized and dropped.
pub fn ltc_lock() -> Result<()> {
    let mut guard = with_lock()?;
    *guard = None; // LtcSession drops → Zeroizing wipes the seed
    Ok(())
}

/// Non-secret session state for the UI; `None` when locked.
#[derive(Debug)]
pub struct LtcSessionStateDto {
    pub network_display: String,
    pub server_url: String,
    pub account: u32,
    /// base58 xpub of `m/84'/2'/account'` (watch-only handle).
    pub account_xpub: String,
}

/// Non-secret session state for the UI; `None` when locked.
pub fn ltc_session_state() -> Result<Option<LtcSessionStateDto>> {
    let guard = with_lock()?;
    Ok(guard.as_ref().map(|s| LtcSessionStateDto {
        network_display: "Litecoin mainnet".to_string(),
        server_url: s.server_url.clone(),
        account: s.account,
        account_xpub: s.account_pub.account_xpub().to_string(),
    }))
}

/// One derived address (public data only).
#[derive(Debug)]
pub struct LtcAddressDto {
    pub address: String,
    /// 0 = receiving, 1 = change.
    pub branch: u32,
    pub index: u32,
    /// Path text, e.g. `m/84'/2'/0'/0/3`.
    pub path: String,
    /// `true` when the address has on-chain history (from discovery).
    pub used: bool,
}

fn address_dto(address: &chains::bitcoin::keys::DerivedAddress, used: bool) -> LtcAddressDto {
    LtcAddressDto {
        address: address.address.clone(),
        branch: address.branch,
        index: address.index,
        path: address.path.clone(),
        used,
    }
}

fn derive_dto(account: &LtcAccount, branch: u32, index: u32, used: bool) -> Result<LtcAddressDto> {
    let address = account
        .derive_address(branch, index)
        .map_err(|e| anyhow!("{e}"))?;
    Ok(address_dto(&address, used))
}

/// Result of a full sync. `next_receive` is the fresh address to show in the
/// Receive screen (the first index past the last used one, gap-limit kept).
#[derive(Debug)]
pub struct LtcSyncDto {
    pub confirmed_sat: u64,
    /// Mempool delta (can be negative, e.g. a spend of confirmed coins).
    pub unconfirmed_delta_sat: i64,
    pub utxo_count: u32,
    /// Every scanned address that has on-chain history.
    pub used_addresses: Vec<LtcAddressDto>,
    pub next_receive: LtcAddressDto,
    pub next_change: LtcAddressDto,
    pub tip_height: u32,
    pub server_url: String,
}

/// Discover all wallet addresses (gap-limited), compute the balance.
pub fn ltc_sync(gap_limit: u32) -> Result<LtcSyncDto> {
    let (gateway, account_pub) = snapshot()?;
    match attempt_sync(&gateway, &account_pub, gap_limit) {
        Ok(dto) => Ok(dto),
        Err(e) => {
            // Public servers sometimes drop fresh connections (the same
            // flaky EOF story as BTC): rebuild the gateway with the honest
            // handshake backoff and retry exactly once.
            if !transient_sync_error(&e) {
                return Err(anyhow!("{e}"));
            }
            let fresh = LtcGateway::connect(gateway.url()).map_err(|e| anyhow!("{e}"))?;
            store_gateway(fresh)?;
            let (gateway, account_pub) = snapshot()?;
            attempt_sync(&gateway, &account_pub, gap_limit)
        }
    }
}

fn transient_sync_error(e: &anyhow::Error) -> bool {
    let text = format!("{e}").to_lowercase();
    text.contains("electrum")
        || text.contains("unexpected end of file")
        || text.contains("eof while parsing")
        || text.contains("all errored")
        || text.contains("timed out")
        || text.contains("connection")
}

fn attempt_sync(
    gateway: &LtcGateway,
    account_pub: &LtcAccount,
    gap_limit: u32,
) -> Result<LtcSyncDto> {
    let discovery = discover(gateway, account_pub, gap_limit).map_err(|e| anyhow!("{e}"))?;
    let balance = wallet_balance(gateway, &discovery).map_err(|e| anyhow!("{e}"))?;
    // UTXO set is part of the sync story (balance == Σ utxo values stays
    // observable); the send layer of LTC will consume it later.
    let utxos =
        chains::bitcoin::scan::collect_utxos(gateway, &discovery).map_err(|e| anyhow!("{e}"))?;
    let utxo_count = utxos.len() as u32;
    let used_addresses: Vec<LtcAddressDto> = discovery
        .slots()
        .filter(|s| s.used)
        .map(|s| LtcAddressDto {
            address: s.address.clone(),
            branch: s.branch,
            index: s.index,
            path: s.path.clone(),
            used: true,
        })
        .collect();
    // Honest UTXO count for the receive-only view (the collect step is the
    // scan module's; no send layer consumes it yet).

    let next_receive = derive_dto(
        account_pub,
        BRANCH_EXTERNAL,
        discovery.external.next_index(),
        false,
    )?;
    let next_change = derive_dto(
        account_pub,
        BRANCH_INTERNAL,
        discovery.internal.next_index(),
        false,
    )?;

    let tip_height = gateway.tip_height()?;

    store_sync(discovery)?;

    Ok(LtcSyncDto {
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
pub fn ltc_receive_address() -> Result<LtcAddressDto> {
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
pub struct LtcTxStatusDto {
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
            .ok_or_else(|| anyhow!("no scanned addresses — run ltc_sync first"))?
            .slots()
            .map(|slot| slot.script_pubkey.clone())
            .collect::<Vec<_>>())
    })
}

/// Check a transaction's confirmation status (requires a prior `ltc_sync`).
pub fn ltc_tx_status(txid: String) -> Result<LtcTxStatusDto> {
    let txid: ::bitcoin::Txid = txid
        .parse()
        .map_err(|e| anyhow!("invalid txid {txid:?}: {e}"))?;
    let (gateway, _account) = snapshot()?;
    let scripts = scanned_scripts()?;
    let status = tx_status(&gateway, &scripts, txid).map_err(|e| anyhow!("{e}"))?;
    Ok(match status {
        TxStatus::Unknown => LtcTxStatusDto {
            state: "unknown".to_string(),
            height: None,
            confirmations: None,
            txid: txid.to_string(),
        },
        TxStatus::Mempool => LtcTxStatusDto {
            state: "mempool".to_string(),
            height: None,
            confirmations: None,
            txid: txid.to_string(),
        },
        TxStatus::Confirmed {
            height,
            confirmations,
        } => LtcTxStatusDto {
            state: "confirmed".to_string(),
            height: Some(height),
            confirmations: Some(confirmations),
            txid: txid.to_string(),
        },
    })
}

/// One wallet transaction with its amounts (litoshi amounts).
#[derive(Debug)]
pub struct LtcHistoryItemDto {
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

/// The wallet history with computed amounts (requires a prior `ltc_sync`).
/// Capped by the scan module's MAX_HISTORY_ITEMS safety valve.
pub fn ltc_history() -> Result<Vec<LtcHistoryItemDto>> {
    let (gateway, _account) = snapshot()?;
    let discovery = with_session(|s| Ok(s.discovery.clone()))?
        .ok_or_else(|| anyhow!("no scanned addresses — run ltc_sync first"))?;
    let items = history_with_amounts(&gateway, &discovery).map_err(|e| anyhow!("{e}"))?;
    Ok(items
        .into_iter()
        .map(|item| LtcHistoryItemDto {
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
