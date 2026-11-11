//! `backup_manager` — encrypted backups of VEYRO wallet secrets.
//!
//! Purpose: move a wallet between the user's own devices **without any server**.
//!
//! Construction:
//! - The backup payload (mnemonic phrases + BIP39 passphrases + wallet names)
//!   is serialized to JSON and encrypted with `crypto_vault`
//!   (Argon2id + XChaCha20-Poly1305) under a **backup password** chosen by the
//!   user at export time.
//! - The on-disk/portable format is a small JSON header (`app`, `version`,
//!   `created_at_unix`) plus the encrypted envelope. The header contains no
//!   secrets — not even the number of wallets (it lives in the ciphertext).
//! - Integrity is guaranteed by the AEAD tag: any tampering makes import fail.
//! - Payloads are zeroized in memory after encryption and after decryption
//!   consumption.
//!
//! Import intentionally returns secrets to the caller instead of writing
//! wallets directly: the UI layer re-encrypts them into fresh per-device
//! vaults via `wallet_core::restore` with a password chosen on this device.

#![forbid(unsafe_code)]

use crypto_vault::{self, KdfParams};
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};
use thiserror::Error;
use zeroize::{Zeroize, Zeroizing};

/// Backup format version.
pub const BACKUP_VERSION: u16 = 1;
/// Format marker.
pub const BACKUP_APP_ID: &str = "VEYRO-BACKUP";

#[derive(Debug, Error)]
pub enum BackupError {
    #[error("nothing to export: backup must contain at least one wallet")]
    Empty,
    #[error("vault error: {0}")]
    Vault(#[from] crypto_vault::VaultError),
    #[error("malformed backup file: {0}")]
    Malformed(String),
    #[error("unsupported backup version: {0}")]
    UnsupportedVersion(u16),
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
}

/// Input for export: secrets of one wallet.
pub struct WalletSecretInput {
    pub name: String,
    pub phrase: Zeroizing<String>,
    pub passphrase: Zeroizing<String>,
}

/// Output of import: decrypted secrets, consumed by `wallet_core::restore`.
pub struct RestoredWalletSecret {
    pub name: String,
    pub phrase: Zeroizing<String>,
    pub passphrase: Zeroizing<String>,
}

/// Secret payload stored inside the encrypted envelope. Zeroized on drop.
#[derive(Serialize, Deserialize)]
struct BackupPayload {
    wallets: Vec<BackupWalletSecret>,
    exported_at_unix: u64,
}

#[derive(Serialize, Deserialize)]
struct BackupWalletSecret {
    name: String,
    phrase: String,
    passphrase: String,
}

impl Drop for BackupWalletSecret {
    fn drop(&mut self) {
        self.name.zeroize();
        self.phrase.zeroize();
        self.passphrase.zeroize();
    }
}

// Never expose secrets through Debug.
impl std::fmt::Debug for BackupWalletSecret {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("BackupWalletSecret(<secret>)")
    }
}

/// Portable backup file. The header is public; all secrets are inside `vault`.
#[derive(Serialize, Deserialize)]
pub struct BackupFile {
    pub app: String,
    pub version: u16,
    pub created_at_unix: u64,
    pub vault: crypto_vault::VaultEnvelope,
}

impl std::fmt::Debug for BackupFile {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BackupFile")
            .field("app", &self.app)
            .field("version", &self.version)
            .field("created_at_unix", &self.created_at_unix)
            .field("vault", &self.vault)
            .finish()
    }
}

/// Export wallet secrets into an encrypted backup.
///
/// The `backup_password` is independent of wallet unlock passwords: it protects
/// this file specifically (the user may also reuse it — their choice).
pub fn export(
    wallets: Vec<WalletSecretInput>,
    backup_password: &str,
    kdf: KdfParams,
) -> Result<BackupFile, BackupError> {
    if wallets.is_empty() {
        return Err(BackupError::Empty);
    }

    let payload = BackupPayload {
        wallets: wallets
            .into_iter()
            .map(|w| BackupWalletSecret {
                name: w.name,
                phrase: w.phrase.to_string(),
                passphrase: w.passphrase.to_string(),
            })
            .collect(),
        exported_at_unix: unix_now(),
    };
    let json = Zeroizing::new(
        serde_json::to_vec(&payload).map_err(|e| BackupError::Malformed(e.to_string()))?,
    );
    let envelope = crypto_vault::encrypt(backup_password, &json, kdf)?;
    // `payload` and `json` zeroize on drop.

    Ok(BackupFile {
        app: BACKUP_APP_ID.to_string(),
        version: BACKUP_VERSION,
        created_at_unix: unix_now(),
        vault: envelope,
    })
}

/// Verify and decrypt a backup. Fails generically on wrong password or tampering.
pub fn import(
    backup: &BackupFile,
    backup_password: &str,
) -> Result<Vec<RestoredWalletSecret>, BackupError> {
    if backup.app != BACKUP_APP_ID {
        return Err(BackupError::Malformed("unexpected app id".into()));
    }
    if backup.version != BACKUP_VERSION {
        return Err(BackupError::UnsupportedVersion(backup.version));
    }

    let json = crypto_vault::decrypt(backup_password, &backup.vault)?;
    let payload: BackupPayload =
        serde_json::from_slice(&json).map_err(|e| BackupError::Malformed(e.to_string()))?;
    // `json` zeroizes on drop; `payload` zeroizes its secrets on drop.

    Ok(payload
        .wallets
        .into_iter()
        .map(|mut w| RestoredWalletSecret {
            name: std::mem::take(&mut w.name),
            phrase: Zeroizing::new(std::mem::take(&mut w.phrase)),
            passphrase: Zeroizing::new(std::mem::take(&mut w.passphrase)),
        })
        .collect())
    // Empty husks drop and zeroize harmlessly; the real secrets now live
    // in Zeroizing wrappers.
}

impl BackupFile {
    /// Serialize to a JSON string (portable representation).
    pub fn to_json(&self) -> Result<String, BackupError> {
        serde_json::to_string(self).map_err(|e| BackupError::Malformed(e.to_string()))
    }

    pub fn from_json(s: &str) -> Result<Self, BackupError> {
        serde_json::from_str(s).map_err(|e| BackupError::Malformed(e.to_string()))
    }

    /// Write the backup to a file.
    pub fn to_file(&self, path: impl AsRef<Path>) -> Result<(), BackupError> {
        std::fs::write(path, self.to_json()?)?;
        Ok(())
    }

    /// Read a backup from a file.
    pub fn from_file(path: impl AsRef<Path>) -> Result<Self, BackupError> {
        let raw = std::fs::read_to_string(path)?;
        Self::from_json(&raw)
    }
}

fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_id_is_stable() {
        assert_eq!(BACKUP_APP_ID, "VEYRO-BACKUP");
    }
}
