//! `storage` — SQLite storage for non-secret VEYRO application data.
//!
//! Security boundary: this crate MUST never hold private keys, seeds, mnemonic
//! phrases or any secret material. Those live exclusively in `crypto_vault`
//! envelopes. Everything stored here is public metadata:
//! wallet registry, generated addresses, contacts, node endpoints,
//! transaction labels, cached prices and app settings.
//!
//! Prices are stored as decimal strings — never floats — because binary
//! floating point cannot represent money exactly.
//!
//! Schema versioning: `PRAGMA user_version`, forward migrations in
//! [`Db::migrate`]. A database from a NEWER schema version is rejected rather
//! than downgraded (never risk corrupting user data).

#![forbid(unsafe_code)]

use rusqlite::{params, Connection, OptionalExtension};
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
CREATE TABLE wallets (
    id               TEXT PRIMARY KEY,
    name             TEXT NOT NULL,
    created_at_unix  INTEGER NOT NULL,
    vault_file       TEXT NOT NULL
);

CREATE TABLE addresses (
    wallet_id        TEXT NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    chain            TEXT NOT NULL,
    account_index    INTEGER NOT NULL DEFAULT 0,
    address_index    INTEGER NOT NULL DEFAULT 0,
    address          TEXT NOT NULL,
    label            TEXT,
    created_at_unix  INTEGER NOT NULL,
    PRIMARY KEY (wallet_id, chain, account_index, address_index)
);
CREATE INDEX idx_addresses_wallet ON addresses(wallet_id);

CREATE TABLE contacts (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    name             TEXT NOT NULL,
    chain            TEXT NOT NULL,
    address          TEXT NOT NULL,
    note             TEXT,
    UNIQUE (chain, address)
);

CREATE TABLE node_endpoints (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    chain            TEXT NOT NULL,
    name             TEXT NOT NULL,
    url              TEXT NOT NULL,
    is_primary       INTEGER NOT NULL DEFAULT 0,
    enabled          INTEGER NOT NULL DEFAULT 1,
    created_at_unix  INTEGER NOT NULL,
    UNIQUE (chain, url)
);

CREATE TABLE tx_labels (
    chain            TEXT NOT NULL,
    tx_id            TEXT NOT NULL,
    label            TEXT NOT NULL,
    PRIMARY KEY (chain, tx_id)
);

CREATE TABLE price_cache (
    ticker           TEXT NOT NULL,
    fiat             TEXT NOT NULL,
    price            TEXT NOT NULL, -- decimal string; never floats for money
    updated_at_unix  INTEGER NOT NULL,
    PRIMARY KEY (ticker, fiat)
);

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
}

// ---------------------------------------------------------------------------
// Row types
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WalletRow {
    pub id: String,
    pub name: String,
    pub created_at_unix: i64,
    pub vault_file: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AddressRow {
    pub wallet_id: String,
    pub chain: String,
    pub account_index: i64,
    pub address_index: i64,
    pub address: String,
    pub label: Option<String>,
    pub created_at_unix: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ContactRow {
    pub id: i64,
    pub name: String,
    pub chain: String,
    pub address: String,
    pub note: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NodeEndpointRow {
    pub id: i64,
    pub chain: String,
    pub name: String,
    pub url: String,
    pub is_primary: bool,
    pub enabled: bool,
    pub created_at_unix: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PriceEntryRow {
    pub ticker: String,
    pub fiat: String,
    /// Decimal string (e.g. `"104321.55"`); never a float.
    pub price: String,
    pub updated_at_unix: i64,
}

// ---------------------------------------------------------------------------
// Wallets
// ---------------------------------------------------------------------------

impl Db {
    /// Insert or update the wallet registry entry.
    pub fn upsert_wallet(&self, w: &WalletRow) -> Result<(), StorageError> {
        self.conn.execute(
            "INSERT INTO wallets (id, name, created_at_unix, vault_file)
             VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(id) DO UPDATE SET name = excluded.name, vault_file = excluded.vault_file",
            params![w.id, w.name, w.created_at_unix, w.vault_file],
        )?;
        Ok(())
    }

    pub fn list_wallets(&self) -> Result<Vec<WalletRow>, StorageError> {
        let mut stmt = self.conn.prepare(
            "SELECT id, name, created_at_unix, vault_file FROM wallets ORDER BY created_at_unix",
        )?;
        let rows = stmt
            .query_map([], |r| {
                Ok(WalletRow {
                    id: r.get(0)?,
                    name: r.get(1)?,
                    created_at_unix: r.get(2)?,
                    vault_file: r.get(3)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    /// Delete a wallet entry. Generated addresses are removed by `ON DELETE CASCADE`.
    pub fn delete_wallet(&self, id: &str) -> Result<bool, StorageError> {
        let affected = self
            .conn
            .execute("DELETE FROM wallets WHERE id = ?1", params![id])?;
        Ok(affected > 0)
    }

    // -----------------------------------------------------------------------
    // Addresses
    // -----------------------------------------------------------------------

    /// Insert or update a generated address for a wallet+chain slot.
    pub fn upsert_address(&self, a: &AddressRow) -> Result<(), StorageError> {
        self.conn.execute(
            "INSERT INTO addresses (wallet_id, chain, account_index, address_index, address, label, created_at_unix)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
             ON CONFLICT(wallet_id, chain, account_index, address_index)
             DO UPDATE SET address = excluded.address, label = excluded.label",
            params![
                a.wallet_id,
                a.chain,
                a.account_index,
                a.address_index,
                a.address,
                a.label,
                a.created_at_unix
            ],
        )?;
        Ok(())
    }

    pub fn list_addresses(
        &self,
        wallet_id: &str,
        chain: &str,
    ) -> Result<Vec<AddressRow>, StorageError> {
        let mut stmt = self.conn.prepare(
            "SELECT wallet_id, chain, account_index, address_index, address, label, created_at_unix
             FROM addresses WHERE wallet_id = ?1 AND chain = ?2
             ORDER BY account_index, address_index",
        )?;
        let rows = stmt
            .query_map(params![wallet_id, chain], |r| {
                Ok(AddressRow {
                    wallet_id: r.get(0)?,
                    chain: r.get(1)?,
                    account_index: r.get(2)?,
                    address_index: r.get(3)?,
                    address: r.get(4)?,
                    label: r.get(5)?,
                    created_at_unix: r.get(6)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    // -----------------------------------------------------------------------
    // Contacts
    // -----------------------------------------------------------------------

    pub fn insert_contact(
        &self,
        name: &str,
        chain: &str,
        address: &str,
        note: Option<&str>,
    ) -> Result<ContactRow, StorageError> {
        self.conn.execute(
            "INSERT INTO contacts (name, chain, address, note) VALUES (?1, ?2, ?3, ?4)",
            params![name, chain, address, note],
        )?;
        Ok(self
            .contact_by_address(chain, address)?
            .expect("just inserted"))
    }

    fn contact_by_address(
        &self,
        chain: &str,
        address: &str,
    ) -> Result<Option<ContactRow>, StorageError> {
        self.conn
            .query_row(
                "SELECT id, name, chain, address, note FROM contacts WHERE chain = ?1 AND address = ?2",
                params![chain, address],
                |r| {
                    Ok(ContactRow {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        chain: r.get(2)?,
                        address: r.get(3)?,
                        note: r.get(4)?,
                    })
                },
            )
            .optional()
            .map_err(StorageError::from)
    }

    pub fn list_contacts(&self, chain: Option<&str>) -> Result<Vec<ContactRow>, StorageError> {
        let mut stmt = self
            .conn
            .prepare("SELECT id, name, chain, address, note FROM contacts WHERE (?1 IS NULL OR chain = ?1) ORDER BY name")?;
        let rows = stmt
            .query_map(params![chain], |r| {
                Ok(ContactRow {
                    id: r.get(0)?,
                    name: r.get(1)?,
                    chain: r.get(2)?,
                    address: r.get(3)?,
                    note: r.get(4)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    pub fn delete_contact(&self, id: i64) -> Result<bool, StorageError> {
        Ok(self
            .conn
            .execute("DELETE FROM contacts WHERE id = ?1", params![id])?
            > 0)
    }

    // -----------------------------------------------------------------------
    // Node endpoints
    // -----------------------------------------------------------------------

    pub fn upsert_node_endpoint(
        &self,
        chain: &str,
        name: &str,
        url: &str,
        is_primary: bool,
        enabled: bool,
        created_at_unix: i64,
    ) -> Result<(), StorageError> {
        self.conn.execute(
            "INSERT INTO node_endpoints (chain, name, url, is_primary, enabled, created_at_unix)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)
             ON CONFLICT(chain, url) DO UPDATE SET
                name = excluded.name,
                is_primary = excluded.is_primary,
                enabled = excluded.enabled",
            params![chain, name, url, is_primary, enabled, created_at_unix],
        )?;
        Ok(())
    }

    pub fn list_node_endpoints(&self, chain: &str) -> Result<Vec<NodeEndpointRow>, StorageError> {
        let mut stmt = self.conn.prepare(
            "SELECT id, chain, name, url, is_primary, enabled, created_at_unix
             FROM node_endpoints WHERE chain = ?1
             ORDER BY is_primary DESC, id",
        )?;
        let rows = stmt
            .query_map(params![chain], |r| {
                Ok(NodeEndpointRow {
                    id: r.get(0)?,
                    chain: r.get(1)?,
                    name: r.get(2)?,
                    url: r.get(3)?,
                    is_primary: r.get::<_, i64>(4)? != 0,
                    enabled: r.get::<_, i64>(5)? != 0,
                    created_at_unix: r.get(6)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    /// Mark exactly one endpoint as primary for a chain (demoting others).
    pub fn set_primary_node(&self, chain: &str, id: i64) -> Result<(), StorageError> {
        self.conn.execute(
            "UPDATE node_endpoints SET is_primary = (id = ?2) WHERE chain = ?1",
            params![chain, id],
        )?;
        Ok(())
    }

    pub fn delete_node_endpoint(&self, id: i64) -> Result<bool, StorageError> {
        Ok(self
            .conn
            .execute("DELETE FROM node_endpoints WHERE id = ?1", params![id])?
            > 0)
    }

    // -----------------------------------------------------------------------
    // Transaction labels
    // -----------------------------------------------------------------------

    pub fn set_tx_label(&self, chain: &str, tx_id: &str, label: &str) -> Result<(), StorageError> {
        self.conn.execute(
            "INSERT INTO tx_labels (chain, tx_id, label) VALUES (?1, ?2, ?3)
             ON CONFLICT(chain, tx_id) DO UPDATE SET label = excluded.label",
            params![chain, tx_id, label],
        )?;
        Ok(())
    }

    pub fn get_tx_label(&self, chain: &str, tx_id: &str) -> Result<Option<String>, StorageError> {
        self.conn
            .query_row(
                "SELECT label FROM tx_labels WHERE chain = ?1 AND tx_id = ?2",
                params![chain, tx_id],
                |r| r.get(0),
            )
            .optional()
            .map_err(StorageError::from)
    }

    // -----------------------------------------------------------------------
    // Price cache
    // -----------------------------------------------------------------------

    pub fn set_price(&self, entry: &PriceEntryRow) -> Result<(), StorageError> {
        self.conn.execute(
            "INSERT INTO price_cache (ticker, fiat, price, updated_at_unix) VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(ticker, fiat) DO UPDATE SET
                price = excluded.price, updated_at_unix = excluded.updated_at_unix",
            params![entry.ticker, entry.fiat, entry.price, entry.updated_at_unix],
        )?;
        Ok(())
    }

    pub fn get_price(
        &self,
        ticker: &str,
        fiat: &str,
    ) -> Result<Option<PriceEntryRow>, StorageError> {
        self.conn
            .query_row(
                "SELECT ticker, fiat, price, updated_at_unix FROM price_cache WHERE ticker = ?1 AND fiat = ?2",
                params![ticker, fiat],
                |r| {
                    Ok(PriceEntryRow {
                        ticker: r.get(0)?,
                        fiat: r.get(1)?,
                        price: r.get(2)?,
                        updated_at_unix: r.get(3)?,
                    })
                },
            )
            .optional()
            .map_err(StorageError::from)
    }

    // -----------------------------------------------------------------------
    // Settings
    // -----------------------------------------------------------------------

    pub fn set_setting(&self, key: &str, value: &str) -> Result<(), StorageError> {
        self.conn.execute(
            "INSERT INTO settings (key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            params![key, value],
        )?;
        Ok(())
    }

    pub fn get_setting(&self, key: &str) -> Result<Option<String>, StorageError> {
        self.conn
            .query_row(
                "SELECT value FROM settings WHERE key = ?1",
                params![key],
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
}
