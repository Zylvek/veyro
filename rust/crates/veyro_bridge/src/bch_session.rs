//! Internal BCH session state (NOT part of the flutter_rust_bridge API tree —
//! this module is `crate`-private and outside `crate::api`, so the generated
//! Dart surface can never reference it or its seed).
//!
//! Mirrors `ltc_session`: process-global locked slot, zeroized seed inside
//! Rust, network I/O never under the lock. A SEPARATE slot — BTC/LTC/BCH
//! sessions open simultaneously.

use std::sync::{Mutex, MutexGuard};

use anyhow::{anyhow, Result};
use zeroize::Zeroizing;

use chains::bitcoin::scan::{Discovery, WalletUtxo};
use chains::cash::{BchAccount, BchGateway};

/// Everything the BCH feature needs between unlock and lock. Same secret
/// discipline as `BtcSession` (Debug is hand-written; the seed never appears
/// in logs).
pub struct BchSession {
    pub server_url: String,
    pub account: u32,
    /// BIP39 seed — the only secret here, zeroized when the session drops.
    #[allow(dead_code)]
    pub seed: Zeroizing<[u8; 64]>,
    /// Watch-only public material (safe in any log/display).
    pub account_pub: BchAccount,
    /// Live, genesis-verified Electrum-BCH gateway (Clone, cheap).
    pub gateway: BchGateway,
    /// Last successful discovery (sync). `None` before the first sync.
    pub discovery: Option<Discovery>,
    /// Spendable outputs from the last sync (reset after a successful send).
    pub utxos: Option<Vec<WalletUtxo>>,
}

impl std::fmt::Debug for BchSession {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BchSession")
            .field("server_url", &self.server_url)
            .field("account", &self.account)
            .field("seed", &"<64 secret bytes>")
            .finish_non_exhaustive()
    }
}

static BCH_SESSION: Mutex<Option<BchSession>> = Mutex::new(None);

pub fn with_lock() -> Result<MutexGuard<'static, Option<BchSession>>> {
    BCH_SESSION
        .lock()
        .map_err(|_| anyhow!("BCH session mutex poisoned by a previous panic"))
}

/// Is there an open BCH session right now (no ownership taken).
#[allow(dead_code)]
pub fn has_session() -> Result<bool> {
    Ok(with_lock()?.is_some())
}

/// Run `f` with the open session (read-only use).
pub fn with_session<T>(f: impl FnOnce(&BchSession) -> Result<T>) -> Result<T> {
    let guard = with_lock()?;
    let session = guard
        .as_ref()
        .ok_or_else(|| anyhow!("no BCH session — unlock a wallet first"))?;
    f(session)
}

/// Snapshot the pieces needed for a network call, then release the lock.
pub fn snapshot() -> Result<(BchGateway, BchAccount)> {
    let guard = with_lock()?;
    let session = guard
        .as_ref()
        .ok_or_else(|| anyhow!("no BCH session — unlock a wallet first"))?;
    Ok((session.gateway.clone(), session.account_pub.clone()))
}

/// Store discovery/UTXO results of a sync back into the session.
pub fn store_sync(discovery: Discovery, utxos: Vec<WalletUtxo>) -> Result<()> {
    let mut guard = with_lock()?;
    let session = guard
        .as_mut()
        .ok_or_else(|| anyhow!("no BCH session — unlock a wallet first"))?;
    session.discovery = Some(discovery);
    session.utxos = Some(utxos);
    Ok(())
}

/// After a successful send: the spendable set is stale AND the just-used
/// change address must not serve the next send twice (same discipline as
/// BTC/LTC). Discovery's internal `last_used` is advanced so the next change
/// index is fresh even before the next full sync.
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

/// Replace the session gateway (after a dead-connection reconnect).
pub fn store_gateway(gateway: BchGateway) -> Result<()> {
    let mut guard = with_lock()?;
    let session = guard
        .as_mut()
        .ok_or_else(|| anyhow!("no BCH session — unlock a wallet first"))?;
    session.gateway = gateway;
    Ok(())
}
