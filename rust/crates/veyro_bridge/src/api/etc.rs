//! ETC operations exposed to the UI. Другой профиль (EVM-стек, паспорт
//! docs/coins/ETC.md): публичный JSON-RPC через HTTPS (TLS-only), fund-safety
//! = chainId + генезис при каждом connect; один адрес на аккаунт (конвенция
//! EVM: m/44'/61'/0'/0/0), nonce вместо change-индексов; история нативных
//! переводов — BlockScout REST v2 (третья сторона, как Electrum-сервер).
//! Все Wei-величины пересекают FFI как десятичные Strings (u128 честно).

use anyhow::{anyhow, Result};
use zeroize::Zeroizing;

use chains::etc::{
    blockscout_history, etc_failover_candidates, validate_eip55, EtcGateway, EtcNetwork,
    LegacyTxIntent, ETC_MAINNET_GENESIS_HEX, TRANSFER_GAS,
};
use key_manager::from_phrase;
use wallet_core::WalletManager;

use crate::etc_session::{
    after_send, snapshot, store_gateway, store_snapshot, with_lock, with_session,
};
use crate::production_kdf;

/// BlockScout REST v2 (публичный, проверен 11.11.2026; третья сторона —
/// видит адреса запросов, не ключи; как Electrum-сервер).
const BLOCKSCOUT_BASE: &str = "https://etc.blockscout.com/api/v2";

/// Server identity shown on the network-info screen.
#[derive(Debug)]
pub struct EtcUnlockDto {
    pub network_display: String,
    pub server_url: String,
    pub chain_id: u64,
    pub genesis_hash_hex: String,
    pub tip_height: u64,
    /// EIP-55 адрес аккаунта (m/44'/61'/0'/0/0).
    pub account_address: String,
    pub path: String,
}

/// The candidate public RPC servers (core-owned, verified 11.11.2026).
pub fn etc_servers() -> Vec<String> {
    EtcNetwork::Mainnet
        .preset_servers()
        .iter()
        .map(|s| s.to_string())
        .collect()
}

/// Unlock a wallet for ETC operations.
pub fn etc_unlock(
    wallets_dir: String,
    wallet_id: String,
    password: String,
    rpc_url: String,
) -> Result<EtcUnlockDto> {
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

    let gateway = EtcGateway::connect(&rpc_url, EtcNetwork::Mainnet)?;
    let tip_height = gateway.block_number()?;

    let (_account, address20, address_eip55) =
        crate::etc_session::derive_account(seed.as_bytes(), 0)?;

    crate::session_password::store_for(&wallet_id, &effective)?;

    let mut guard = with_lock()?;
    *guard = Some(crate::etc_session::EtcSession {
        server_url: gateway.url().to_string(),
        account: 0,
        seed: Zeroizing::new(*seed.as_bytes()),
        address20,
        address_eip55: address_eip55.clone(),
        gateway,
        last_nonce: None,
    });

    Ok(EtcUnlockDto {
        network_display: EtcNetwork::Mainnet.display_name().to_string(),
        server_url: rpc_url.clone(),
        chain_id: EtcNetwork::Mainnet.chain_id(),
        genesis_hash_hex: ETC_MAINNET_GENESIS_HEX.to_string(),
        tip_height,
        account_address: address_eip55.clone(),
        path: "m/44'/61'/0'/0/0".to_string(),
    })
}

/// Lock the session.
pub fn etc_lock() -> Result<()> {
    let mut guard = with_lock()?;
    *guard = None;
    drop(guard);
    crate::session_password::erase_if_all_locked()?;
    Ok(())
}

#[derive(Debug)]
pub struct EtcSessionStateDto {
    pub network_display: String,
    pub server_url: String,
    pub account: u32,
    pub account_address: String,
}

pub fn etc_session_state() -> Result<Option<EtcSessionStateDto>> {
    let guard = with_lock()?;
    Ok(guard.as_ref().map(|s| EtcSessionStateDto {
        network_display: EtcNetwork::Mainnet.display_name().to_string(),
        server_url: s.server_url.clone(),
        account: s.account,
        account_address: s.address_eip55.clone(),
    }))
}

#[derive(Debug)]
pub struct EtcAddressDto {
    pub address: String,
    pub index: u32,
    pub path: String,
}

/// EVM-конвенция: один адрес аккаунта (m/44'/61'/account'/0/0), повторное
/// использование честно (не UTXO-цепь; ротация только по аккаунтам).
pub fn etc_receive_address() -> Result<EtcAddressDto> {
    with_session(|s| {
        Ok(EtcAddressDto {
            address: s.address_eip55.clone(),
            index: 0,
            path: format!("m/44'/61'/{}/'/0/0", s.account),
        })
    })
}

#[derive(Debug)]
pub struct EtcSyncDto {
    /// eth_getBalance "latest" (wei, decimal String).
    pub confirmed_wei: String,
    /// pending − latest (мем-дельта, может быть отрицательной).
    pub pending_delta_wei: String,
    /// Актуальный nonce (pending) — именно он пойдёт в следующую отправку.
    pub nonce: u64,
    pub tip_height: u64,
    pub server_url: String,
    pub account_address: String,
}

fn attempt_sync(
    gateway: &EtcGateway,
    address20: &[u8; 20],
    address_eip55: &str,
) -> Result<EtcSyncDto, chains::ChainError> {
    let latest = gateway.balance_wei(address20, false)?;
    let pending = gateway.balance_wei(address20, true)?;
    let nonce = gateway.nonce(address20)?;
    let tip_height = gateway.block_number()?;
    Ok(EtcSyncDto {
        confirmed_wei: latest.to_string(),
        pending_delta_wei: (pending as i128 - latest as i128).to_string(),
        nonce,
        tip_height,
        server_url: gateway.url().to_string(),
        account_address: address_eip55.to_string(),
    })
}

pub fn etc_sync() -> Result<EtcSyncDto> {
    let (gateway, address20, address_eip55) = snapshot()?;
    match attempt_sync(&gateway, &address20, &address_eip55) {
        Ok(dto) => {
            store_snapshot(Some(dto.nonce)).map_err(|e| anyhow!("{e}"))?;
            Ok(dto)
        }
        Err(e) => {
            if !crate::is_transient_sync_error(&e) {
                return Err(anyhow!("{e}"));
            }
            let mut last_err = e;
            for url in etc_failover_candidates(EtcNetwork::Mainnet, gateway.url())
                .iter()
                .take(2)
            {
                let fresh = match EtcGateway::connect(url, EtcNetwork::Mainnet) {
                    Ok(g) => g,
                    Err(ce) => {
                        last_err = ce;
                        continue;
                    }
                };
                store_gateway(fresh).map_err(|err| anyhow!("{err}"))?;
                let (gateway, address20, address_eip55) = snapshot()?;
                match attempt_sync(&gateway, &address20, &address_eip55) {
                    Ok(dto) => {
                        store_snapshot(Some(dto.nonce)).map_err(|e| anyhow!("{e}"))?;
                        return Ok(dto);
                    }
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

#[derive(Debug)]
pub struct EtcHistoryItemDto {
    pub hash: String,
    pub from: String,
    pub to: String,
    /// wei, decimal String (u128 честно).
    pub value_wei: String,
    pub block: Option<u64>,
    /// "success" / "failed" / отсутствует → статус неизвестен (честно).
    pub status: Option<String>,
    pub fee_wei: Option<String>,
    pub timestamp: Option<String>,
}

#[derive(Debug)]
pub struct EtcHistoryDto {
    pub items: Vec<EtcHistoryItemDto>,
    pub total_entries: i64,
    pub truncated: bool,
}

/// История нативных переводов (BlockScout v2 — public REST, третья сторона).
pub fn etc_history() -> Result<EtcHistoryDto> {
    let (_gateway, address20, _addr) = snapshot()?;
    let (items, total) =
        blockscout_history(BLOCKSCOUT_BASE, &address20).map_err(|e| anyhow!("{e}"))?;
    let truncated = (items.len() as i64) < total as i64;
    Ok(EtcHistoryDto {
        items: items
            .into_iter()
            .map(|it| EtcHistoryItemDto {
                hash: it.hash,
                from: it.from,
                to: it.to,
                value_wei: it.value_wei.to_string(),
                block: it.block_number,
                status: it
                    .status_success
                    .map(|s| if s { "success".into() } else { "failed".into() }),
                fee_wei: it.fee_wei.map(|f| f.to_string()),
                timestamp: it.timestamp,
            })
            .collect(),
        total_entries: total as i64,
        truncated,
    })
}

#[derive(Debug)]
pub struct EtcFeesDto {
    /// eth_gasPrice (wei, decimal String).
    pub gas_price_wei: String,
    pub gas_limit: u64,
    /// true если сервер не оценил и мы честно взяли минимум перевода.
    pub fallback: bool,
}

pub fn etc_fees() -> Result<EtcFeesDto> {
    let (gateway, address20, _addr) = snapshot()?;
    let gas_price = gateway.gas_price_wei().map_err(|e| anyhow!("{e}"))?;
    let intent = LegacyTxIntent {
        nonce: 0,
        gas_price_wei: gas_price,
        gas_limit: TRANSFER_GAS,
        to: [0u8; 20], // форма для оценки; фактический to подставит send
        value_wei: 1,
        data: Vec::new(),
    };
    match gateway.estimate_gas(&address20, &intent) {
        Ok(g) if g >= TRANSFER_GAS => Ok(EtcFeesDto {
            gas_price_wei: gas_price.to_string(),
            gas_limit: g,
            fallback: false,
        }),
        Ok(_) => Ok(EtcFeesDto {
            gas_price_wei: gas_price.to_string(),
            gas_limit: TRANSFER_GAS,
            fallback: true,
        }),
        Err(_) => Ok(EtcFeesDto {
            gas_price_wei: gas_price.to_string(),
            gas_limit: TRANSFER_GAS,
            fallback: true,
        }),
    }
}

#[derive(Debug)]
pub struct EtcSendResultDto {
    pub txhash: String,
    pub raw_hex: String,
    pub already_known: bool,
    pub recipient: String,
    /// wei, decimal String.
    pub amount_wei: String,
    pub fee_wei: String,
    pub nonce: u64,
    pub gas_price_wei: String,
    pub gas_limit: u64,
    /// true = сервер не оценил газ, взяли честный минимум перевода.
    pub fallback: bool,
    pub status: String,
}

/// План+подпись+broadcast: nonce(pending) от сервера, честная оценка газа,
/// подпись от seed в сессии (Zeroizing), eth_sendRawTransaction; «already
/// known» переводится честно (повторная отправка той же транз безопасна).
pub fn etc_send(
    recipient: String,
    amount_wei: String,
    gas_price_wei_override: Option<String>,
) -> Result<EtcSendResultDto> {
    let (gateway, address20, _addr) = snapshot()?;
    let recipient_addr = validate_eip55(&recipient).map_err(|e| anyhow!("{e}"))?;
    let trimmed = amount_wei.trim();
    if trimmed.is_empty() || trimmed.starts_with('-') {
        return Err(anyhow!("invalid amount: {amount_wei}"));
    }
    let amount = trimmed
        .parse::<u128>()
        .map_err(|_| anyhow!("invalid amount: {amount_wei}"))?;
    if amount == 0 {
        return Err(anyhow!("invalid amount: 0"));
    }
    let gas_price: u128 = match gas_price_wei_override {
        Some(s) => s
            .trim()
            .parse()
            .map_err(|_| anyhow!("invalid gasPrice: {s}"))?,
        None => gateway.gas_price_wei().map_err(|e| anyhow!("{e}"))?,
    };
    // Честная оценка: по фактическому получателю; отказ → минимум+флаг.
    let intent_probe = LegacyTxIntent {
        nonce: 0,
        gas_price_wei: gas_price,
        gas_limit: TRANSFER_GAS,
        to: recipient_addr,
        value_wei: amount,
        data: Vec::new(),
    };
    let (gas_limit, fallback) = match gateway.estimate_gas(&address20, &intent_probe) {
        Ok(g) if g >= TRANSFER_GAS => (g, false),
        Ok(_) => (TRANSFER_GAS, true),
        Err(_) => (TRANSFER_GAS, true),
    };

    let nonce = gateway.nonce(&address20).map_err(|e| anyhow!("{e}"))?;
    let intent = LegacyTxIntent {
        nonce,
        gas_price_wei: gas_price,
        gas_limit,
        to: recipient_addr,
        value_wei: amount,
        data: Vec::new(),
    };
    let (raw_hex, _sig, _parity, txhash, _from) = {
        with_session(|s| {
            // Подпись от seed сессии; секрет никогда не выходит наружу.
            let (secret, _from_addr) =
                chains::etc::etc_secret_key(&s.seed, EtcNetwork::Mainnet, s.account, 0)
                    .map_err(|e| anyhow!("{e}"))?;
            chains::etc::etc_sign_transfer_parts(&secret, EtcNetwork::Mainnet.chain_id(), intent)
                .map_err(|e| anyhow!("{e}"))
        })?
    };

    let broadcast = match gateway.send_raw(&raw_hex) {
        Ok(_r) => Ok((false, "broadcast".to_string())),
        Err(e) => {
            let msg = e.to_string().to_ascii_lowercase();
            if msg.contains("already known") || msg.contains("already exists") {
                Ok((true, "mempool".to_string()))
            } else {
                Err(anyhow!("{e}"))
            }
        }
    };
    let (already_known, mut status) = match broadcast {
        Ok(v) => v,
        Err(e) => {
            after_send().map_err(|err| anyhow!("{err}"))?;
            return Err(e);
        }
    };
    after_send().map_err(|e| anyhow!("{e}"))?;

    // Честный статус: разово спросим mempool/receipt (подтверждение UI увидит
    // через etc_tx_status; здесь — мгновенный срез честного состояния).
    if let Ok(Some(receipt)) = gateway.receipt(&txhash) {
        status = if receipt.status_success {
            "confirmed".to_string()
        } else {
            "failed".to_string()
        };
    } else if status != "mempool" {
        if let Ok(true) = gateway.in_mempool(&txhash) {
            status = "mempool".to_string();
        }
    }

    Ok(EtcSendResultDto {
        txhash,
        raw_hex,
        already_known,
        recipient: chains::etc::eip55(&recipient_addr),
        amount_wei: amount.to_string(),
        fee_wei: (gas_price * gas_limit as u128).to_string(),
        nonce,
        gas_price_wei: gas_price.to_string(),
        gas_limit,
        fallback,
        status,
    })
}

#[derive(Debug)]
pub struct EtcTxStatusDto {
    /// "unknown" / "mempool" / "broadcast-only" / "success" / "failed"
    pub state: String,
    pub block: Option<u64>,
    pub txhash: String,
}

/// Статус транз: receipt (подтверждение) → mempool → честное unknown.
pub fn etc_tx_status(txhash: String) -> Result<EtcTxStatusDto> {
    let (gateway, _a, _addr) = snapshot()?;
    if let Some(receipt) = gateway.receipt(&txhash).map_err(|e| anyhow!("{e}"))? {
        return Ok(EtcTxStatusDto {
            state: if receipt.status_success {
                "success"
            } else {
                "failed"
            }
            .to_string(),
            block: receipt.block_number,
            txhash,
        });
    }
    if gateway.in_mempool(&txhash).map_err(|e| anyhow!("{e}"))? {
        return Ok(EtcTxStatusDto {
            state: "mempool".to_string(),
            block: None,
            txhash,
        });
    }
    Ok(EtcTxStatusDto {
        state: "unknown".to_string(),
        block: None,
        txhash,
    })
}
