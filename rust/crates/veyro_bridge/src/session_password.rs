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

/// Wipe ONLY one wallet's cached password (owner decision: after an
/// irreversible wallet deletion its password must not survive in memory).
/// The rest of the map is untouched.
pub fn erase_for(wallet_id: &str) -> Result<()> {
    let mut now_empty = false;
    {
        let mut guard = with_lock()?;
        if let Some(map) = guard.as_mut() {
            if map.remove(wallet_id).is_some() && map.is_empty() {
                now_empty = true;
            }
        }
    }
    if now_empty {
        // Empty map holds no secrets: drop to release the allocation.
        *with_lock()? = None;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn per_wallet_cache_and_erase_for() {
        // Tests run in one process: make sure these ids are unique enough not
        // to clash with other tests touching the cache (none do by name).
        store_for("test-wallet-erase", &Zeroizing::new("pw-a".to_string())).unwrap();
        assert!(cached_for("test-wallet-erase").unwrap());
        assert!(!cached_for("test-wallet-other").unwrap());

        let got = get_for("test-wallet-erase").unwrap().unwrap();
        assert_eq!(&*got, "pw-a");

        assert!(erase_for("test-wallet-other").is_ok());
        assert!(cached_for("test-wallet-erase").unwrap());
        erase_for("test-wallet-erase").unwrap();
        assert!(!cached_for("test-wallet-erase").unwrap());
    }
}
