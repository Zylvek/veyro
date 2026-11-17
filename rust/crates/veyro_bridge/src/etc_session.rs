//! Internal ETC session state — mirrors `raven_session` (per-coin slot:
//! BTC/LTC/BCH/XEC/RVN/ETC open simultaneously). EVM-профиль: один адрес
//! аккаунта, nonce вместо change-индексов, Wei u128 честно в Strings моста.

use std::sync::{Mutex, MutexGuard};

use anyhow::{anyhow, Result};
use zeroize::Zeroizing;

use chains::etc::{EtcAccount, EtcGateway};

/// Everything the ETC feature needs between unlock and lock.
pub struct EtcSession {
    pub server_url: String,
    pub account: u32,
    /// BIP39 seed — zeroized when the session drops.
    pub seed: Zeroizing<[u8; 64]>,
    /// Адрес аккаунта m/44'/61'/account'/0/0 (EVM: один адрес на аккаунт).
    pub address20: [u8; 20],
    pub address_eip55: String,
    pub gateway: EtcGateway,
    /// Кэш последнего синка; после любой отправки инвалидируется
    /// (пересчёт баланса/nonce — честный аналог invalidate-UTXO у BTC).
    pub last_nonce: Option<u64>,
}

impl std::fmt::Debug for EtcSession {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("EtcSession")
            .field("server_url", &self.server_url)
            .field("account", &self.account)
            .field("seed", &"<64 secret bytes>")
            .field("address", &self.address_eip55)
            .finish_non_exhaustive()
    }
}

static ETC_SESSION: Mutex<Option<EtcSession>> = Mutex::new(None);

pub fn with_lock() -> Result<MutexGuard<'static, Option<EtcSession>>> {
    ETC_SESSION
        .lock()
        .map_err(|_| anyhow!("ETC session mutex poisoned by a previous panic"))
}

pub fn with_session<T>(f: impl FnOnce(&EtcSession) -> Result<T>) -> Result<T> {
    let guard = with_lock()?;
    let session = guard
        .as_ref()
        .ok_or_else(|| anyhow!("no ETC session — unlock a wallet first"))?;
    f(session)
}

pub fn snapshot() -> Result<(EtcGateway, [u8; 20], String)> {
    let guard = with_lock()?;
    let session = guard
        .as_ref()
        .ok_or_else(|| anyhow!("no ETC session — unlock a wallet first"))?;
    Ok((
        session.gateway.clone(),
        session.address20,
        session.address_eip55.clone(),
    ))
}

pub fn store_snapshot(nonce: Option<u64>) -> Result<()> {
    let mut guard = with_lock()?;
    let session = guard
        .as_mut()
        .ok_or_else(|| anyhow!("no ETC session — unlock a wallet first"))?;
    session.last_nonce = nonce;
    Ok(())
}

/// Отправка инвалидирует кэш (следующий sync пересчитает balance/nonce).
pub fn after_send() -> Result<()> {
    let mut guard = with_lock()?;
    if let Some(session) = guard.as_mut() {
        session.last_nonce = None;
    }
    Ok(())
}

pub fn store_gateway(gateway: EtcGateway) -> Result<()> {
    let mut guard = with_lock()?;
    let session = guard
        .as_mut()
        .ok_or_else(|| anyhow!("no ETC session — unlock a wallet first"))?;
    session.gateway = gateway;
    Ok(())
}

/// Деривация адреса аккаунта из seed (m/44'/61'/account'/0/0).
pub fn derive_account(seed: &[u8; 64], account: u32) -> Result<(EtcAccount, [u8; 20], String)> {
    let acc = chains::etc::EtcAccount::from_seed(seed, chains::etc::EtcNetwork::Mainnet, account)
        .map_err(|e| anyhow!("{e}"))?;
    let addr = acc.derive_address(0).map_err(|e| anyhow!("{e}"))?;
    Ok((acc, addr.addr20, addr.address.clone()))
}
