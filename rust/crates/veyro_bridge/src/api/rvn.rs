//! RVN operations exposed to the UI. 1:1 with `bch.rs`/`xec.rs` (Electrum
//! TLS + legacy UTXO profile; SIGHASH_ALL signing from the shared cash
//! module's legacy path — Ravencoin did NOT fork UAHF, no forkid flag).
//! Docs/coins/RVN.md: BIP44 m/44'/175' (official nExtCoinType), base58
//! P2PKH `R…` (60) / P2SH `r…` (122).

use anyhow::{anyhow, Result};

use chains::bitcoin::keys::{BRANCH_EXTERNAL, BRANCH_INTERNAL};
use chains::bitcoin::scan::{
    collect_utxos, discover, history_with_amounts, tx_status, wallet_balance, HistoryDirection,
    TxStatus,
};
use chains::bitcoin::tx::estimate_fee_rates_with_fallback;
use chains::electrum::Gateway;
use chains::raven::{
    rvn_failover_candidates, rvn_plan_transfer_on, rvn_signed_transfer, RvnAccount, RvnGateway,
    RvnNetwork, GENESIS_MAINNET_HEX,
};
use chains::ChainError;
use zeroize::Zeroizing;

use key_manager::from_phrase;
use wallet_core::WalletManager;

use crate::production_kdf;
use crate::raven_session::{
    after_send, snapshot, store_gateway, store_sync, with_lock, with_session,
};

/// Server identity shown on the network-info screen.
#[derive(Debug)]
pub struct RvnUnlockDto {
    pub network_display: String,
    pub server_url: String,
    pub server_version: String,
    pub protocol_min: String,
    pub protocol_max: String,
    pub genesis_hash_hex: String,
    pub tip_height: u32,
    /// base58 xpub of `m/44'/175'/account'`.
    pub account_xpub: String,
}

/// The candidate Electrum-RVN servers (core-owned, official client list).
pub fn rvn_servers() -> Vec<String> {
    chains::raven::SERVER_MAINNET_CANDIDATES
        .iter()
        .map(|s| s.to_string())
        .collect()
}

/// Unlock a wallet for RVN operations.
pub fn rvn_unlock(
    wallets_dir: String,
    wallet_id: String,
    password: String,
    server_url: String,
) -> Result<RvnUnlockDto> {
    let effective: Zeroizing<String> = if password.trim().is_empty() {
        crate::session_password::get_for(&wallet_id)?.ok_or_else(|| {
            anyhow!("no cached password — prompt the user for the wallet password")
        })?
    } else {
        Zeroizing::new(password)
    };

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

    let gateway = RvnGateway::connect(&server_url)?;
    let (server_version, protocol_min, protocol_max, server_genesis) = gateway.server_features()?;
    let server_genesis_hex = hex::encode(server_genesis);
    if server_genesis_hex != GENESIS_MAINNET_HEX {
        return Err(anyhow!(
            "server {server_url} serves a different network (genesis {server_genesis_hex} instead of {GENESIS_MAINNET_HEX} for Ravencoin mainnet) — refusing to use it"
        ));
    }
    let tip_height = gateway.tip_height()?;

    let account_pub = RvnAccount::from_seed(seed.as_bytes(), RvnNetwork::Mainnet, 0)
        .map_err(|e| anyhow!("{e}"))?;
    let account_xpub = account_pub.account_xpub().to_string();

    crate::session_password::store_for(&wallet_id, &effective)?;

    let mut guard = with_lock()?;
    *guard = Some(crate::raven_session::RvnSession {
        server_url: gateway.url().to_string(),
        account: 0,
        seed: Zeroizing::new(*seed.as_bytes()),
        account_pub,
        gateway,
        discovery: None,
        utxos: None,
    });

    Ok(RvnUnlockDto {
        network_display: "Ravencoin mainnet".to_string(),
        server_url: server_url.clone(),
        server_version,
        protocol_min,
        protocol_max,
        genesis_hash_hex: server_genesis_hex,
        tip_height,
        account_xpub,
    })
}

/// Lock the session.
pub fn rvn_lock() -> Result<()> {
    let mut guard = with_lock()?;
    *guard = None;
    drop(guard);
    crate::session_password::erase_if_all_locked()?;
    Ok(())
}

#[derive(Debug)]
pub struct RvnSessionStateDto {
    pub network_display: String,
    pub server_url: String,
    pub account: u32,
    pub account_xpub: String,
}

pub fn rvn_session_state() -> Result<Option<RvnSessionStateDto>> {
    let guard = with_lock()?;
    Ok(guard.as_ref().map(|s| RvnSessionStateDto {
        network_display: "Ravencoin mainnet".to_string(),
        server_url: s.server_url.clone(),
        account: s.account,
        account_xpub: s.account_pub.account_xpub().to_string(),
    }))
}

#[derive(Debug)]
pub struct RvnAddressDto {
    pub address: String,
    pub branch: u32,
    pub index: u32,
    pub path: String,
    pub used: bool,
}

fn address_dto(address: &chains::bitcoin::keys::DerivedAddress, used: bool) -> RvnAddressDto {
    RvnAddressDto {
        address: address.address.clone(),
        branch: address.branch,
        index: address.index,
        path: address.path.clone(),
        used,
    }
}

#[derive(Debug)]
pub struct RvnSyncDto {
    pub confirmed_sat: u64,
    pub unconfirmed_delta_sat: i64,
    pub utxo_count: u32,
    pub used_addresses: Vec<RvnAddressDto>,
    pub next_receive: RvnAddressDto,
    pub next_change: RvnAddressDto,
    pub tip_height: u32,
    pub server_url: String,
}

pub fn rvn_sync(gap_limit: u32) -> Result<RvnSyncDto> {
    let (gateway, account_pub) = snapshot()?;
    match attempt_sync(&gateway, &account_pub, gap_limit) {
        Ok(dto) => Ok(dto),
        Err(e) => {
            if !crate::is_transient_sync_error(&e) {
                return Err(anyhow!("{e}"));
            }
            let mut last_err = e;
            for url in rvn_failover_candidates(RvnNetwork::Mainnet, gateway.url())
                .iter()
                .take(2)
            {
                let fresh = match RvnGateway::connect(url) {
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
    gateway: &RvnGateway,
    account_pub: &RvnAccount,
    gap_limit: u32,
) -> Result<RvnSyncDto, ChainError> {
    let discovery = discover(gateway, account_pub, gap_limit)?;
    let balance = wallet_balance(gateway, &discovery)?;
    let utxos = collect_utxos(gateway, &discovery)?;
    let utxo_count = utxos.len() as u32;
    let used_addresses: Vec<RvnAddressDto> = discovery
        .slots()
        .filter(|s| s.used)
        .map(|s| RvnAddressDto {
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

    Ok(RvnSyncDto {
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

pub fn rvn_receive_address() -> Result<RvnAddressDto> {
    with_session(|s| {
        let next_index = s
            .discovery
            .as_ref()
            .map(|d| d.external.next_index())
            .unwrap_or(0);
        let address = s
            .account_pub
            .derive_address(BRANCH_EXTERNAL, next_index)
            .map_err(|e| anyhow!("{e}"))?;
        Ok(address_dto(&address, false))
    })
}

#[derive(Debug)]
pub struct RvnTxStatusDto {
    pub state: String,
    pub height: Option<u32>,
    pub confirmations: Option<u32>,
    pub txid: String,
}

fn scanned_scripts() -> Result<Vec<Vec<u8>>> {
    with_session(|s| {
        Ok(s.discovery
            .as_ref()
            .ok_or_else(|| anyhow!("no scanned addresses — run rvn_sync first"))?
            .slots()
            .map(|slot| slot.script_pubkey.clone())
            .collect::<Vec<_>>())
    })
}

pub fn rvn_tx_status(txid: String) -> Result<RvnTxStatusDto> {
    let txid: ::bitcoin::Txid = txid
        .parse()
        .map_err(|e| anyhow!("invalid txid {txid:?}: {e}"))?;
    let (gateway, _account) = snapshot()?;
    let scripts = scanned_scripts()?;
    let status = tx_status(&gateway, &scripts, txid).map_err(|e| anyhow!("{e}"))?;
    Ok(match status {
        TxStatus::Unknown => RvnTxStatusDto {
            state: "unknown".to_string(),
            height: None,
            confirmations: None,
            txid: txid.to_string(),
        },
        TxStatus::Mempool => RvnTxStatusDto {
            state: "mempool".to_string(),
            height: None,
            confirmations: None,
            txid: txid.to_string(),
        },
        TxStatus::Confirmed {
            height,
            confirmations,
        } => RvnTxStatusDto {
            state: "confirmed".to_string(),
            height: Some(height),
            confirmations: Some(confirmations),
            txid: txid.to_string(),
        },
    })
}

#[derive(Debug)]
pub struct RvnHistoryItemDto {
    pub txid: String,
    pub height: i64,
    pub direction: String,
    pub received_sat: u64,
    pub sent_net_sat: u64,
    pub fee_sat: Option<u64>,
}

#[derive(Debug)]
pub struct RvnHistoryDto {
    pub items: Vec<RvnHistoryItemDto>,
    pub total_entries: i64,
    pub truncated: bool,
}

pub fn rvn_history() -> Result<RvnHistoryDto> {
    let (gateway, _account) = snapshot()?;
    let discovery = with_session(|s| Ok(s.discovery.clone()))?
        .ok_or_else(|| anyhow!("no scanned addresses — run rvn_sync first"))?;
    let resolution = history_with_amounts(&gateway, &discovery).map_err(|e| anyhow!("{e}"))?;
    Ok(RvnHistoryDto {
        items: resolution
            .items
            .into_iter()
            .map(|item| RvnHistoryItemDto {
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

#[derive(Debug)]
pub struct RvnFeeRatesDto {
    pub fast_sat_vb: u64,
    pub normal_sat_vb: u64,
    pub slow_sat_vb: u64,
    pub fallback: bool,
}

pub fn rvn_fees() -> Result<RvnFeeRatesDto> {
    let (gateway, _account) = snapshot()?;
    let (rates, fallback) =
        estimate_fee_rates_with_fallback(&gateway).map_err(|e| anyhow!("{e}"))?;
    Ok(RvnFeeRatesDto {
        fast_sat_vb: rates.fast_sat_vb,
        normal_sat_vb: rates.normal_sat_vb,
        slow_sat_vb: rates.slow_sat_vb,
        fallback,
    })
}

#[derive(Debug)]
pub struct RvnSendResultDto {
    pub txid: String,
    pub raw_hex: String,
    pub already_known: bool,
    pub recipient: String,
    pub amount_sat: u64,
    pub fee_sat: u64,
    pub size_bytes: u64,
    pub fee_sat_per_byte: u64,
    pub change_address: Option<String>,
    pub change_sat: Option<u64>,
    pub status: String,
}

/// Plan, sign (legacy SIGHASH_ALL; the shared digest module) and broadcast.
pub fn rvn_send(
    recipient: String,
    amount_sat: u64,
    fee_sat_per_byte: u64,
) -> Result<RvnSendResultDto> {
    let (gateway, _account_pub) = snapshot()?;
    let tip_height = gateway.tip_height()?;
    let signed = with_session(|s| {
        let utxos = s
            .utxos
            .as_ref()
            .ok_or_else(|| anyhow!("no spendable set — run rvn_sync before sending"))?;
        let change_index = s
            .discovery
            .as_ref()
            .map(|d| d.internal.next_index())
            .unwrap_or(0);
        let change = s
            .account_pub
            .derive_address(BRANCH_INTERNAL, change_index)
            .map_err(|e| anyhow!("{e}"))?;
        let plan = rvn_plan_transfer_on(
            RvnNetwork::Mainnet,
            &recipient,
            amount_sat,
            fee_sat_per_byte,
            utxos,
            &change,
        )
        .map_err(|e| anyhow!("{e}"))?;
        rvn_signed_transfer(&plan, &s.seed, RvnNetwork::Mainnet, s.account, tip_height)
            .map_err(|e| anyhow!("{e}"))
    })?;

    let outcome = match chains::bitcoin::tx::idempotent_broadcast(&gateway, &signed) {
        Ok(outcome) => outcome,
        Err(e) => {
            after_send().map_err(|err| anyhow!("{err}"))?;
            return Err(anyhow!("{e}"));
        }
    };
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

    Ok(RvnSendResultDto {
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
