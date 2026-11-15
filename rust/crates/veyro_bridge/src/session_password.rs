//! In-process password cache («app entry IS the session»): the owner
//! unlocks the FIRST wallet explicitly; other coins' unlock flows reuse
//! the cached password without re-prompting (owner decision 15.11.2026:
//! «ya уже вошёл в сессию — зачем спрашивать пароль заново»).
//!
//! Secrets contract: the password NEVER crosses the FFI boundary — it
//! lives here (Zeroizing, wiped on drop) and is erased as soon as the
//! LAST coin session of the process locks (BTC and LTC both closed =
//! full logout). A fresh app start starts with an empty cache.

use anyhow::{anyhow, Result};
use zeroize::Zeroizing;

use crate::{btc_session, ltc_session};

static PASSWORD_CACHE: Mutex<Option<Zeroizing<String>>> = Mutex::new(None);

use std::sync::Mutex;

/// Is a reusable password cached right now.
pub fn cached() -> Result<bool> {
    let guard = PASSWORD_CACHE
        .lock()
        .map_err(|_| anyhow!("password cache mutex poisoned by a previous panic"))?;
    Ok(guard.is_some())
}

/// Copy the cached password into a new Zeroizing (the cache itself stays
/// for further coins).
pub fn get() -> Result<Option<Zeroizing<String>>> {
    let guard = PASSWORD_CACHE
        .lock()
        .map_err(|_| anyhow!("password cache mutex poisoned by a previous panic"))?;
    Ok(guard.clone())
}

/// Cache after a successful unlock (overwrites the previous one — the last
/// successful unlock wins, which also matches multi-wallet switching).
pub fn store(password: &Zeroizing<String>) -> Result<()> {
    let mut guard = PASSWORD_CACHE
        .lock()
        .map_err(|_| anyhow!("password cache mutex poisoned by a previous panic"))?;
    *guard = Some(password.clone());
    Ok(())
}

/// Wipe when the last coin session locks (both BTC and LTC closed).
pub fn erase_if_all_locked() -> Result<()> {
    let btc_open = btc_session::has_session()?;
    let ltc_open = ltc_session::has_session()?;
    if !btc_open && !ltc_open {
        let mut guard = PASSWORD_CACHE
            .lock()
            .map_err(|_| anyhow!("password cache mutex poisoned by a previous panic"))?;
        *guard = None; // Zeroizing wipes both copies
    }
    Ok(())
}
