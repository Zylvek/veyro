//! Non-secret session state exposed to Dart. The session itself (including
//! the zeroized seed) lives in the crate-private `btc_session` module —
//! deliberately OUTSIDE the `crate::api` tree so the flutter_rust_bridge
//! codegen can never render it (and its secrets) into the Dart surface.

use anyhow::Result;

use crate::btc_session::with_lock;

/// Non-secret session state for the UI; `None` when locked.
#[derive(Debug)]
pub struct BtcSessionStateDto {
    pub network_code: u32,
    pub network_display: String,
    pub server_url: String,
    pub account: u32,
    /// base58 xpub of `m/84'/coin'/account'` (watch-only handle).
    pub account_xpub: String,
    /// Whether a successful sync has produced a spendable set.
    pub has_spendables: bool,
}

/// Non-secret session state for the UI; `None` when locked.
pub fn btc_session_state() -> Result<Option<BtcSessionStateDto>> {
    let guard = with_lock()?;
    Ok(guard.as_ref().map(|s| BtcSessionStateDto {
        network_code: s.network.code(),
        network_display: s.network.display_name().to_string(),
        server_url: s.server_url.clone(),
        account: s.account,
        account_xpub: s.account_pub.account_xpub().to_string(),
        has_spendables: s.utxos.as_ref().is_some_and(|u| !u.is_empty()),
    }))
}
