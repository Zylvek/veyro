//! In-process password cache keyed BY WALLET («app entry IS the session»,
//! multi-wallet honest variant): the owner may have several wallets with
//! DIFFERENT passwords (e.g. «my» and «mu») — a single session-wide
//! password kept prompting for the other wallet and looked broken.
//! Map: wallet_id → password. Secrets stay INSIDE Rust (Zeroizing, never
//! cross FFI); the whole map is wiped when the LAST coin session locks
//! and on process exit. Fresh app start = empty map.

use std::collections::HashMap;
use std::sync::{Mutex, MutexGuard};

use anyhow::{anyhow, Result};
use zeroize::Zeroizing;

use crate::{btc_session, ltc_session};

/// wallet_id → password (Zeroizing wipes on drop; the whole map drops at
/// the last lock or process exit).
type PasswordMap = HashMap<String, Zeroizing<String>>;

static PASSWORDS: Mutex<Option<PasswordMap>> = Mutex::new(None);

fn with_lock() -> Result<MutexGuard<'static, Option<PasswordMap>>> {
    PASSWORDS
        .lock()
        .map_err(|_| anyhow!("password cache mutex poisoned by a previous panic"))
}

/// Is a reusable password cached for this wallet right now.
pub fn cached_for(wallet_id: &str) -> Result<bool> {
    let guard = with_lock()?;
    Ok(guard
        .as_ref()
        .is_some_and(|map| map.contains_key(wallet_id)))
}

/// Copy the cached password for this wallet (the cache stays).
pub fn get_for(wallet_id: &str) -> Result<Option<Zeroizing<String>>> {
    let guard = with_lock()?;
    Ok(guard.as_ref().and_then(|map| map.get(wallet_id)).cloned())
}

/// Cache after a successful unlock (per wallet; overwrites on wallet
/// password change — the last successful unlock wins).
pub fn store_for(wallet_id: &str, password: &Zeroizing<String>) -> Result<()> {
    let mut guard = with_lock()?;
    let map = guard.get_or_insert_with(HashMap::new);
    map.insert(wallet_id.to_string(), password.clone());
    Ok(())
}

/// Wipe everything when the last coin session locks (both BTC and LTC
/// closed = full logout).
pub fn erase_if_all_locked() -> Result<()> {
    let btc_open = btc_session::has_session()?;
    let ltc_open = ltc_session::has_session()?;
    if !btc_open && !ltc_open {
        *with_lock()? = None; // Zeroizing wipes every stored copy
    }
    Ok(())
}
