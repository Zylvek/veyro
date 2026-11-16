//! Internal XEC session state — mirrors `bch_session` (per-coin slot so
//! BTC/LTC/BCH/XEC sessions can be open simultaneously).

use std::sync::{Mutex, MutexGuard};

use anyhow::{anyhow, Result};
use zeroize::Zeroizing;

use chains::bitcoin::scan::{Discovery, WalletUtxo};
use chains::xec::{XecAccount, XecGateway};

/// Everything the XEC feature needs between unlock and lock.
pub struct XecSession {
    pub server_url: String,
    pub account: u32,
    /// BIP39 seed — zeroized when the session drops.
    #[allow(dead_code)]
    pub seed: Zeroizing<[u8; 64]>,
    pub account_pub: XecAccount,
    pub gateway: XecGateway,
    pub discovery: Option<Discovery>,
    pub utxos: Option<Vec<WalletUtxo>>,
}

impl std::fmt::Debug for XecSession {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("XecSession")
            .field("server_url", &self.server_url)
            .field("account", &self.account)
            .field("seed", &"<64 secret bytes>")
            .finish_non_exhaustive()
    }
}

static XEC_SESSION: Mutex<Option<XecSession>> = Mutex::new(None);

pub fn with_lock() -> Result<MutexGuard<'static, Option<XecSession>>> {
    XEC_SESSION
        .lock()
        .map_err(|_| anyhow!("XEC session mutex poisoned by a previous panic"))
}

pub fn with_session<T>(f: impl FnOnce(&XecSession) -> Result<T>) -> Result<T> {
    let guard = with_lock()?;
    let session = guard
        .as_ref()
        .ok_or_else(|| anyhow!("no XEC session — unlock a wallet first"))?;
    f(session)
}

pub fn snapshot() -> Result<(XecGateway, XecAccount)> {
    let guard = with_lock()?;
    let session = guard
        .as_ref()
        .ok_or_else(|| anyhow!("no XEC session — unlock a wallet first"))?;
    Ok((session.gateway.clone(), session.account_pub.clone()))
}

pub fn store_sync(discovery: Discovery, utxos: Vec<WalletUtxo>) -> Result<()> {
    let mut guard = with_lock()?;
    let session = guard
        .as_mut()
        .ok_or_else(|| anyhow!("no XEC session — unlock a wallet first"))?;
    session.discovery = Some(discovery);
    session.utxos = Some(utxos);
    Ok(())
}

pub fn after_send() -> Result<()> {
    let mut guard = with_lock()?;
    if let Some(session) = guard.as_mut() {
        session.utxos = None;
        if let Some(discovery) = session.discovery.as_mut() {
            let next = discovery.internal.next_index();
            discovery.internal.last_used = Some(next);
        }
    }
    Ok(())
}

pub fn store_gateway(gateway: XecGateway) -> Result<()> {
    let mut guard = with_lock()?;
    let session = guard
        .as_mut()
        .ok_or_else(|| anyhow!("no XEC session — unlock a wallet first"))?;
    session.gateway = gateway;
    Ok(())
}
