//! Non-secret SQLite metadata exposed through a process-global singleton.
//!
//! Why a global: flutter_rust_bridge opaque types must be `Sync`, and a
//! rusqlite connection is not. Owning the connection in one
//! `Mutex<Option<Db>>` keeps the database usable from Dart without ever
//! exposing the handle across the boundary.

use anyhow::{anyhow, Result};
use std::sync::{Mutex, MutexGuard};
use storage::{Db, WalletRow};

/// Wallet registry row (non-secret; mirrors `storage::WalletRow`).
pub struct WalletRowDto {
    pub id: String,
    pub name: String,
    pub created_at_unix: i64,
    /// Path of the vault file this record points to.
    pub vault_file: String,
}

static DB: Mutex<Option<Db>> = Mutex::new(None);

fn with_lock() -> Result<MutexGuard<'static, Option<Db>>> {
    DB.lock()
        .map_err(|_| anyhow!("storage mutex poisoned by a previous panic"))
}

fn with_db<T>(f: impl FnOnce(&Db) -> Result<T>) -> Result<T> {
    let guard = with_lock()?;
    let db = guard
        .as_ref()
        .ok_or_else(|| anyhow!("database is not open"))?;
    f(db)
}

/// Open (or switch to) the metadata database at `path`.
/// A previously opened connection is closed first.
pub fn db_open(path: String) -> Result<()> {
    let mut guard = with_lock()?;
    let db = Db::open(&path)?;
    *guard = Some(db);
    Ok(())
}

/// Close the database (no-op if not open).
pub fn db_close() -> Result<()> {
    let mut guard = with_lock()?;
    *guard = None;
    Ok(())
}

/// Current schema version of the open database.
pub fn db_schema_version() -> Result<i64> {
    with_db(|db| Ok(db.schema_version()?))
}

/// Register (or update) a wallet record.
pub fn db_upsert_wallet(row: WalletRowDto) -> Result<()> {
    with_db(|db| {
        db.upsert_wallet(&WalletRow {
            id: row.id,
            name: row.name,
            created_at_unix: row.created_at_unix,
            vault_file: row.vault_file,
        })?;
        Ok(())
    })
}
/// List all wallet records.
pub fn db_list_wallets() -> Result<Vec<WalletRowDto>> {
    with_db(|db| {
        let rows = db
            .list_wallets()?
            .into_iter()
            .map(|row| WalletRowDto {
                id: row.id,
                name: row.name,
                created_at_unix: row.created_at_unix,
                vault_file: row.vault_file,
            })
            .collect();
        Ok(rows)
    })
}

/// Delete a wallet record. Returns `true` if it existed.
pub fn db_delete_wallet(id: String) -> Result<bool> {
    with_db(|db| Ok(db.delete_wallet(&id)?))
}

/// Store a setting (simple key-value, non-secret).
pub fn db_set_setting(key: String, value: String) -> Result<()> {
    with_db(|db| Ok(db.set_setting(&key, &value)?))
}

/// Read a setting.
pub fn db_get_setting(key: String) -> Result<Option<String>> {
    with_db(|db| Ok(db.get_setting(&key)?))
}
