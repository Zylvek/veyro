//! Internal RVN session state — mirrors `xec_session` (per-coin slot so
//! BTC/LTC/BCH/XEC/RVN sessions can be open simultaneously).

use std::sync::{Mutex, MutexGuard};

use anyhow::{anyhow, Result};
use zeroize::Zeroizing;

use chains::bitcoin::scan::{Discovery, WalletUtxo};
use chains::raven::{RvnAccount, RvnGateway};

/// Everything the RVN feature needs between unlock and lock.
pub struct RvnSession {
    pub server_url: String,
    pub account: u32,
    /// BIP39 seed — zeroized when the session drops.
    #[allow(dead_code)]
    pub seed: Zeroizing<[u8; 64]>,
    pub account_pub: RvnAccount,
    pub gateway: RvnGateway,
    pub discovery: Option<Discovery>,
    pub utxos: Option<Vec<WalletUtxo>>,
}

impl std::fmt::Debug for RvnSession {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RvnSession")
            .field("server_url", &self.server_url)
            .field("account", &self.account)
            .field("seed", &"<64 secret bytes>")
            .finish_non_exhaustive()
    }
}

static RVN_SESSION: Mutex<Option<RvnSession>> = Mutex::new(None);

pub fn with_lock() -> Result<MutexGuard<'static, Option<RvnSession>>> {
    RVN_SESSION
        .lock()
        .map_err(|_| anyhow!("RVN session mutex poisoned by a previous panic"))
}

pub fn with_session<T>(f: impl FnOnce(&RvnSession) -> Result<T>) -> Result<T> {
    let guard = with_lock()?;
    let session = guard
        .as_ref()
        .ok_or_else(|| anyhow!("no RVN session — unlock a wallet first"))?;
    f(session)
}

pub fn snapshot() -> Result<(RvnGateway, RvnAccount)> {
    let guard = with_lock()?;
    let session = guard
        .as_ref()
        .ok_or_else(|| anyhow!("no RVN session — unlock a wallet first"))?;
    Ok((session.gateway.clone(), session.account_pub.clone()))
}

pub fn store_sync(discovery: Discovery, utxos: Vec<WalletUtxo>) -> Result<()> {
    let mut guard = with_lock()?;
    let session = guard
        .as_mut()
        .ok_or_else(|| anyhow!("no RVN session — unlock a wallet first"))?;
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

pub fn store_gateway(gateway: RvnGateway) -> Result<()> {
    let mut guard = with_lock()?;
    let session = guard
        .as_mut()
        .ok_or_else(|| anyhow!("no RVN session — unlock a wallet first"))?;
    session.gateway = gateway;
    Ok(())
}
