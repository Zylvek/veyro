//! Internal BTC session state (NOT part of the flutter_rust_bridge API tree —
//! this module is `crate`-private and outside `crate::api`, so the generated
//! Dart surface can never reference it or its seed).
//!
//! Why a process-global: the UI unlocks once and then issues many operations
//! (sync, send, status) — the same pattern as the storage module. The session
//! holds the BIP39 seed **only inside Rust** (`Zeroizing`, wiped on
//! lock/close): it never crosses the FFI boundary, keeping the milestone-9
//! secret contract intact.
//!
//! Lock discipline: helpers snapshot cheap `Clone` pieces (gateway, account
//! keys) while holding the mutex and then release it — **network I/O never
//! runs under the session lock**, so a slow Electrum call cannot block
//! `btc_lock` or a concurrent status check.

use std::sync::{Mutex, MutexGuard};

use anyhow::{anyhow, Result};
use zeroize::Zeroizing;

use chains::bitcoin::keys::AccountPubkeys;
use chains::bitcoin::scan::{Discovery, WalletUtxo};
use chains::electrum::{BtcNetwork, ElectrumGateway};

/// Everything the BTC feature needs between unlock and lock. `Debug` is
/// hand-written because the seed must never appear in logs.
pub struct BtcSession {
    pub network: BtcNetwork,
    pub server_url: String,
    pub account: u32,
    /// BIP39 seed — the only secret here, zeroized when the session drops.
    pub seed: Zeroizing<[u8; 64]>,
    /// Watch-only public material (safe in any log/display).
    pub account_pub: AccountPubkeys,
    /// Live, network-verified Electrum gateway (Clone, cheap).
    pub gateway: ElectrumGateway,
    /// Last successful discovery (sync). `None` before the first sync.
    pub discovery: Option<Discovery>,
    /// Spendable outputs from the last sync. Reset after every successful
    /// send (stale UTXOs are a double-spend risk) and before the first sync.
    pub utxos: Option<Vec<WalletUtxo>>,
}

impl std::fmt::Debug for BtcSession {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BtcSession")
            .field("network", &self.network)
            .field("server_url", &self.server_url)
            .field("account", &self.account)
            .field("seed", &"<64 secret bytes>")
            .finish_non_exhaustive()
    }
}

static BTC_SESSION: Mutex<Option<BtcSession>> = Mutex::new(None);

pub fn with_lock() -> Result<MutexGuard<'static, Option<BtcSession>>> {
    BTC_SESSION
        .lock()
        .map_err(|_| anyhow!("BTC session mutex poisoned by a previous panic"))
}

/// Is there an open BTC session right now (no ownership taken).
pub fn has_session() -> Result<bool> {
    Ok(with_lock()?.is_some())
}

/// Run `f` with the open session (read-only use).
pub fn with_session<T>(f: impl FnOnce(&BtcSession) -> Result<T>) -> Result<T> {
    let guard = with_lock()?;
    let session = guard
        .as_ref()
        .ok_or_else(|| anyhow!("no BTC session — unlock a wallet first"))?;
    f(session)
}

/// Snapshot the pieces needed for a network call, then release the lock.
pub fn snapshot() -> Result<(ElectrumGateway, AccountPubkeys, BtcNetwork)> {
    let guard = with_lock()?;
    let session = guard
        .as_ref()
        .ok_or_else(|| anyhow!("no BTC session — unlock a wallet first"))?;
    Ok((
        session.gateway.clone(),
        session.account_pub.clone(),
        session.network,
    ))
}

/// Store discovery/UTXO results of a sync back into the session.
pub fn store_sync(discovery: Discovery, utxos: Vec<WalletUtxo>) -> Result<()> {
    let mut guard = with_lock()?;
    let session = guard
        .as_mut()
        .ok_or_else(|| anyhow!("no BTC session — unlock a wallet first"))?;
    session.discovery = Some(discovery);
    session.utxos = Some(utxos);
    Ok(())
}

/// Replace the session gateway (after a dead-connection reconnect) so all
/// further calls reuse the fresh, protocol-verified connection.
pub fn store_gateway(gateway: ElectrumGateway) -> Result<()> {
    let mut guard = with_lock()?;
    let session = guard
        .as_mut()
        .ok_or_else(|| anyhow!("no BTC session — unlock a wallet first"))?;
    session.gateway = gateway;
    Ok(())
}

/// Invalidate stale spendables (after a successful send). The discovery data
/// stays — receive addresses and history do not depend on UTXOs.
pub fn invalidate_utxos() -> Result<()> {
    let mut guard = with_lock()?;
    if let Some(session) = guard.as_mut() {
        session.utxos = None;
    }
    Ok(())
}

/// Network code (0/1/2) → network. Mapping pinned in docs/coins/BTC.md
/// (code 0 mainnet, 1 testnet3, 2 testnet4).
pub fn network_from_code(code: u32) -> Result<BtcNetwork> {
    BtcNetwork::from_code(code).ok_or_else(|| {
        anyhow!("unknown Bitcoin network code {code} (0 mainnet, 1 testnet3, 2 testnet4)")
    })
}
