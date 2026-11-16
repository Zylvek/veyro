//! `storage` — SQLite storage for non-secret VEYRO application data.
//!
//! Security boundary: this crate MUST never hold private keys, seeds, mnemonic
//! phrases or any secret material. Those live exclusively in `crypto_vault`
//! envelopes. Everything stored here is public metadata.
//!
//! Scope (owner decision): only the simple key-value `settings` table is in
//! actual use by the application (network codes, last-good servers, display
//! preferences). The broader registry/contacts/endpoints schema from milestone
//! 1 was removed together with the features it served (§2 MASTER_PROMPT:
//! no address book, no manual server selection); a database file created by
//! an older build simply carries the unused tables around harmlessly.
//!
//! Schema versioning: `PRAGMA user_version`, forward migrations in
//! [`Db::migrate`]. A database from a NEWER schema version is rejected rather
//! than downgraded (never risk corrupting user data).

#![forbid(unsafe_code)]

use rusqlite::{Connection, OptionalExtension};
use std::path::Path;
use thiserror::Error;

/// Current schema version (see [`Db::migrate`]).
pub const SCHEMA_VERSION: i64 = 1;

#[derive(Debug, Error)]
pub enum StorageError {
    #[error("database error: {0}")]
    Db(#[from] rusqlite::Error),
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("database is from a newer, unsupported schema version: {0}")]
    FutureSchema(i64),
}

const SCHEMA_V1: &str = "
CREATE TABLE settings (
    key              TEXT PRIMARY KEY,
    value            TEXT NOT NULL
);
";

/// Handle to the application database.
pub struct Db {
    conn: Connection,
}

impl Db {
    /// Open (and create if needed) a database file, then apply migrations.
    pub fn open(path: impl AsRef<Path>) -> Result<Self, StorageError> {
        let conn = Connection::open(path)?;
        // WAL improves crash safety; it is not applicable to in-memory DBs,
        // so failures are best-effort ignored.
        let _ = conn.pragma_update(None, "journal_mode", "WAL");
        Self::init(conn)
    }

    /// In-memory database (tests, previews).
    pub fn open_in_memory() -> Result<Self, StorageError> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(conn: Connection) -> Result<Self, StorageError> {
        conn.pragma_update(None, "foreign_keys", "ON")?;
        let db = Self { conn };
        db.migrate()?;
        Ok(db)
    }

    /// Apply pending schema migrations.
    fn migrate(&self) -> Result<(), StorageError> {
        let version: i64 = self
            .conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))?;
        if version > SCHEMA_VERSION {
            return Err(StorageError::FutureSchema(version));
        }
        if version < 1 {
            self.conn.execute_batch(SCHEMA_V1)?;
        }
        if version != SCHEMA_VERSION {
            self.conn
                .pragma_update(None, "user_version", SCHEMA_VERSION)?;
        }
        Ok(())
    }

    /// Current schema version (for tests/diagnostics).
    pub fn schema_version(&self) -> Result<i64, StorageError> {
        Ok(self
            .conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))?)
    }

    // -----------------------------------------------------------------------
    // Settings (simple non-secret key-value)
    // -----------------------------------------------------------------------

    pub fn set_setting(&self, key: &str, value: &str) -> Result<(), StorageError> {
        self.conn.execute(
            "INSERT INTO settings (key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            rusqlite::params![key, value],
        )?;
        Ok(())
    }

    pub fn get_setting(&self, key: &str) -> Result<Option<String>, StorageError> {
        self.conn
            .query_row(
                "SELECT value FROM settings WHERE key = ?1",
                rusqlite::params![key],
                |r| r.get(0),
            )
            .optional()
            .map_err(StorageError::from)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn in_memory_db_migrates_to_current_version() {
        let db = Db::open_in_memory().unwrap();
        assert_eq!(db.schema_version().unwrap(), SCHEMA_VERSION);
    }

    #[test]
    fn settings_roundtrip_and_overwrite() {
        let db = Db::open_in_memory().unwrap();
        assert_eq!(db.get_setting("missing").unwrap(), None);
        db.set_setting("theme", "dark").unwrap();
        db.set_setting("theme", "light").unwrap();
        assert_eq!(db.get_setting("theme").unwrap().as_deref(), Some("light"));
    }

    #[test]
    fn settings_survive_reopen() {
        let path = std::env::temp_dir().join(format!(
            "veyro-storage-{}-{}.sqlite",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let _ = std::fs::remove_file(&path);
        {
            let db = Db::open(&path).unwrap();
            db.set_setting("key", "value-v1").unwrap();
        }
        let db = Db::open(&path).unwrap();
        assert_eq!(db.get_setting("key").unwrap().as_deref(), Some("value-v1"));
        assert_eq!(db.schema_version().unwrap(), SCHEMA_VERSION);
        drop(db); // release the connection — Windows refuses removal otherwise
        std::fs::remove_file(&path).unwrap();
    }

    #[test]
    fn future_schema_is_rejected() {
        let path = std::env::temp_dir().join(format!(
            "veyro-storage-future-{}-{}.sqlite",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let _ = std::fs::remove_file(&path);
        {
            let conn = Connection::open(&path).unwrap();
            conn.pragma_update(None, "user_version", SCHEMA_VERSION + 1)
                .unwrap();
        }
        assert!(matches!(
            Db::open(&path),
            Err(StorageError::FutureSchema(_))
        ));
        std::fs::remove_file(&path).unwrap();
    }
}
