//! Internal LTC session state (NOT part of the flutter_rust_bridge API tree —
//! this module is `crate`-private and outside `crate::api`, so the generated
//! Dart surface can never reference it or its seed).
//!
//! Mirrors `btc_session`: process-global locked slot, zeroized seed inside
//! Rust, network I/O never under the lock. Deliberately a SEPARATE slot so
//! BTC and LTC sessions can be open at the same time (the portfolio screen
//! shows both coins; locking one must not lock the other).

use std::sync::{Mutex, MutexGuard};

use anyhow::{anyhow, Result};
use zeroize::Zeroizing;

use chains::bitcoin::scan::{Discovery, WalletUtxo};
use chains::litecoin::{LtcAccount, LtcGateway};

/// Everything the LTC feature needs between unlock and lock. Same secret
/// discipline as `BtcSession` (Debug is hand-written; the seed never appears
/// in logs).
pub struct LtcSession {
    pub server_url: String,
    pub account: u32,
    /// BIP39 seed — the only secret here, zeroized when the session drops.
    /// Consumed by the signing builder inside `ltc_send` (the same local-
    /// signing contract as BTC).
    #[allow(dead_code)]
    pub seed: Zeroizing<[u8; 64]>,
    /// Watch-only public material (safe in any log/display).
    pub account_pub: LtcAccount,
    /// Live, genesis-verified Electrum-LTC gateway (Clone, cheap).
    pub gateway: LtcGateway,
    /// Last successful discovery (sync). `None` before the first sync.
    pub discovery: Option<Discovery>,
    /// Spendable outputs from the last sync (the send layer consumes this
    /// exact set; it is reset after a successful send — a stale set would
    /// double-spend). `None` before the first sync.
    pub utxos: Option<Vec<WalletUtxo>>,
}

impl std::fmt::Debug for LtcSession {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("LtcSession")
            .field("server_url", &self.server_url)
            .field("account", &self.account)
            .field("seed", &"<64 secret bytes>")
            .finish_non_exhaustive()
    }
}

static LTC_SESSION: Mutex<Option<LtcSession>> = Mutex::new(None);

pub fn with_lock() -> Result<MutexGuard<'static, Option<LtcSession>>> {
    LTC_SESSION
        .lock()
        .map_err(|_| anyhow!("LTC session mutex poisoned by a previous panic"))
}

/// Is there an open LTC session right now (no ownership taken).
pub fn has_session() -> Result<bool> {
    Ok(with_lock()?.is_some())
}

/// Run `f` with the open session (read-only use).
pub fn with_session<T>(f: impl FnOnce(&LtcSession) -> Result<T>) -> Result<T> {
    let guard = with_lock()?;
    let session = guard
        .as_ref()
        .ok_or_else(|| anyhow!("no LTC session — unlock a wallet first"))?;
    f(session)
}

/// Snapshot the pieces needed for a network call, then release the lock.
pub fn snapshot() -> Result<(LtcGateway, LtcAccount)> {
    let guard = with_lock()?;
    let session = guard
        .as_ref()
        .ok_or_else(|| anyhow!("no LTC session — unlock a wallet first"))?;
    Ok((session.gateway.clone(), session.account_pub.clone()))
}

/// Store discovery/UTXO results of a sync back into the session.
pub fn store_sync(discovery: Discovery, utxos: Vec<WalletUtxo>) -> Result<()> {
    let mut guard = with_lock()?;
    let session = guard
        .as_mut()
        .ok_or_else(|| anyhow!("no LTC session — unlock a wallet first"))?;
    session.discovery = Some(discovery);
    session.utxos = Some(utxos);
    Ok(())
}

/// Invalidate stale spendables (after a successful send). The discovery
/// data stays — receive addresses and history do not depend on UTXOs.
pub fn invalidate_utxos() -> Result<()> {
    let mut guard = with_lock()?;
    if let Some(session) = guard.as_mut() {
        session.utxos = None;
    }
    Ok(())
}

/// Replace the session gateway (after a dead-connection reconnect).
pub fn store_gateway(gateway: LtcGateway) -> Result<()> {
    let mut guard = with_lock()?;
    let session = guard
        .as_mut()
        .ok_or_else(|| anyhow!("no LTC session — unlock a wallet first"))?;
    session.gateway = gateway;
    Ok(())
}
