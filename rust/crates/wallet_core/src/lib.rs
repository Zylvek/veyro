//! `wallet_core` — wallet lifecycle on top of `crypto_vault` and `key_manager`.
//!
//! Responsibilities of this milestone:
//! - create a new wallet (BIP39, phrase shown to the caller exactly once),
//! - restore a wallet from an existing phrase (with optional BIP39 passphrase),
//! - unlock an existing wallet with its password,
//! - list wallets.
//!
//! Storage model (v1, milestone 1):
//! - one JSON file `<id>.wallet.json` per wallet in the wallet directory;
//! - the file header (id, name, created_at, KDF params) is non-secret;
//! - the secret payload (seed hex + mnemonic phrase + passphrase) is encrypted
//!   with `crypto_vault` (Argon2id + XChaCha20-Poly1305) before it ever touches
//!   the disk, and is zeroized in memory after encryption;
//! - writes are atomic (temp file + rename) so a crash never leaves a torn file.
//!
//! A SQLite layer for non-secret metadata arrives in the next milestone; this
//! file format stays the security boundary for secrets regardless.

#![forbid(unsafe_code)]

use crypto_vault::{self, KdfParams, VaultEnvelope};
use key_manager::{self, Seed, Strength};
use rand_core::{OsRng, RngCore};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};
use thiserror::Error;
use zeroize::{Zeroize, Zeroizing};

/// Current on-disk wallet format version.
pub const FORMAT_VERSION: u16 = 1;
/// File extension of wallet files.
pub const WALLET_FILE_SUFFIX: &str = "wallet.json";

#[derive(Debug, Error)]
pub enum WalletCoreError {
    #[error("invalid wallet name")]
    InvalidName,
    #[error("wallet not found: {0}")]
    NotFound(String),
    #[error("wallet id collision: {0}")]
    IdCollision(String),
    #[error("unsupported wallet file version: {0}")]
    UnsupportedVersion(u16),
    #[error("I/O error: {0}")]
    Io(String),
    #[error("vault error: {0}")]
    Vault(#[from] crypto_vault::VaultError),
    #[error("key manager error: {0}")]
    KeyManager(#[from] key_manager::KeyManagerError),
    #[error("corrupted wallet data: {0}")]
    Corrupted(String),
}

/// Non-secret public info about a stored wallet.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct WalletInfo {
    pub id: String,
    pub name: String,
    pub created_at_unix: u64,
}

/// On-disk wallet file. `vault` holds all secrets; everything else is public.
#[derive(Serialize, Deserialize)]
pub struct WalletFile {
    pub format_version: u16,
    pub id: String,
    pub name: String,
    pub created_at_unix: u64,
    pub kdf: KdfParams,
    pub vault: VaultEnvelope,
}

/// Secrets kept inside the encrypted envelope. Zeroized on drop.
#[derive(Serialize, Deserialize)]
struct SecretPayload {
    /// BIP39 seed, hex-encoded (64 bytes).
    seed: String,
    /// Mnemonic phrase, so the user can view it again after unlocking.
    phrase: String,
    /// BIP39 passphrase used for seed derivation.
    passphrase: String,
}

impl Drop for SecretPayload {
    fn drop(&mut self) {
        self.seed.zeroize();
        self.phrase.zeroize();
        self.passphrase.zeroize();
    }
}

// Never expose secrets through Debug (defence in depth for logs).
impl std::fmt::Debug for SecretPayload {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("SecretPayload(<encrypted-at-rest material>)")
    }
}

/// Result of wallet creation: the phrase is returned exactly once.
pub struct CreatedWallet {
    pub info: WalletInfo,
    /// Show to the user once, then drop. Never logged, never persisted in plaintext.
    pub mnemonic_phrase: Zeroizing<String>,
}

/// Result of restoring an existing wallet (phrase is NOT re-displayed: the user
/// already has it).
pub struct RestoredWallet {
    pub info: WalletInfo,
}

/// An unlocked wallet: wallet info plus the decrypted BIP39 seed in memory.
/// The seed is zeroized on drop.
pub struct UnlockedWallet {
    pub info: WalletInfo,
    pub seed: Seed,
}

/// Manages wallets in a single directory.
pub struct WalletManager {
    dir: PathBuf,
    kdf: KdfParams,
}

impl WalletManager {
    /// Open (and create if needed) a wallet directory.
    pub fn open(dir: impl Into<PathBuf>, kdf: KdfParams) -> Result<Self, WalletCoreError> {
        let dir = dir.into();
        fs::create_dir_all(&dir).map_err(|e| WalletCoreError::Io(e.to_string()))?;
        Ok(Self { dir, kdf })
    }

    /// Create a new wallet. Returns the mnemonic phrase exactly once.
    pub fn create(
        &self,
        name: &str,
        password: &str,
        strength: Strength,
    ) -> Result<CreatedWallet, WalletCoreError> {
        validate_name(name)?;

        let mnemonic = key_manager::generate(strength)?;
        let phrase = mnemonic.phrase();
        let info = self.persist(name, password, &mnemonic, "")?;

        Ok(CreatedWallet {
            info,
            mnemonic_phrase: phrase,
        })
    }

    /// Restore an existing wallet from a phrase (with optional BIP39 passphrase).
    pub fn restore(
        &self,
        name: &str,
        password: &str,
        phrase: &str,
        passphrase: &str,
    ) -> Result<RestoredWallet, WalletCoreError> {
        validate_name(name)?;
        let mnemonic = key_manager::from_phrase(phrase)?;
        let info = self.persist(name, password, &mnemonic, passphrase)?;
        Ok(RestoredWallet { info })
    }

    /// Common path for create/restore: encrypt secrets, write the wallet file.
    fn persist(
        &self,
        name: &str,
        password: &str,
        mnemonic: &key_manager::Mnemonic,
        passphrase: &str,
    ) -> Result<WalletInfo, WalletCoreError> {
        let seed = mnemonic.to_seed(passphrase);

        let payload = SecretPayload {
            seed: hex::encode(seed.as_bytes()),
            phrase: mnemonic.phrase().to_string(),
            passphrase: passphrase.to_string(),
        };
        let payload_json = Zeroizing::new(
            serde_json::to_vec(&payload).map_err(|e| WalletCoreError::Corrupted(e.to_string()))?,
        );
        let envelope = crypto_vault::encrypt(password, &payload_json, self.kdf)?;
        // `payload` and `payload_json` zeroize on drop.

        let id = random_id();
        let path = self.wallet_path(&id);
        if path.exists() {
            return Err(WalletCoreError::IdCollision(id));
        }

        let file = WalletFile {
            format_version: FORMAT_VERSION,
            id: id.clone(),
            name: name.to_string(),
            created_at_unix: unix_now(),
            kdf: self.kdf,
            vault: envelope,
        };
        let file_json =
            serde_json::to_vec(&file).map_err(|e| WalletCoreError::Corrupted(e.to_string()))?;
        atomic_write(&path, &file_json)?;

        Ok(WalletInfo {
            id,
            name: file.name,
            created_at_unix: file.created_at_unix,
        })
    }

    /// Unlock a wallet by id and password. Returns the decrypted seed.
    pub fn unlock(&self, id: &str, password: &str) -> Result<UnlockedWallet, WalletCoreError> {
        let file = self.read_file(id)?;
        let payload_json = crypto_vault::decrypt(password, &file.vault)?;
        let payload: SecretPayload = serde_json::from_slice(&payload_json)
            .map_err(|e| WalletCoreError::Corrupted(e.to_string()))?;

        let seed_bytes = hex::decode(&payload.seed)
            .map_err(|_| WalletCoreError::Corrupted("bad seed hex".into()))?;
        let seed_arr: [u8; key_manager::SEED_LEN] = seed_bytes
            .try_into()
            .map_err(|_| WalletCoreError::Corrupted("bad seed length".into()))?;
        // `payload` (with phrase/passphrase) drops here and zeroizes.

        Ok(UnlockedWallet {
            info: WalletInfo {
                id: file.id,
                name: file.name,
                created_at_unix: file.created_at_unix,
            },
            seed: Seed::from_bytes(seed_arr),
        })
    }

    /// Reveal the mnemonic phrase after unlocking (requires the password).
    pub fn reveal_mnemonic(
        &self,
        id: &str,
        password: &str,
    ) -> Result<Zeroizing<String>, WalletCoreError> {
        let file = self.read_file(id)?;
        let payload_json = crypto_vault::decrypt(password, &file.vault)?;
        let mut payload: SecretPayload = serde_json::from_slice(&payload_json)
            .map_err(|e| WalletCoreError::Corrupted(e.to_string()))?;
        Ok(Zeroizing::new(std::mem::take(&mut payload.phrase)))
        // `payload` drops with an empty phrase and zeroizes the remaining fields.
    }

    /// List wallets (public metadata only).
    pub fn list(&self) -> Result<Vec<WalletInfo>, WalletCoreError> {
        let mut wallets = Vec::new();
        for entry in fs::read_dir(&self.dir).map_err(|e| WalletCoreError::Io(e.to_string()))? {
            let entry = entry.map_err(|e| WalletCoreError::Io(e.to_string()))?;
            let path = entry.path();
            if !is_wallet_file(&path) {
                continue;
            }
            match read_wallet_file(&path) {
                Ok(file) => wallets.push(WalletInfo {
                    id: file.id,
                    name: file.name,
                    created_at_unix: file.created_at_unix,
                }),
                // Skip unreadable files rather than breaking the listing;
                // the UI will surface per-file errors on unlock.
                Err(_) => continue,
            }
        }
        wallets.sort_by(|a, b| {
            a.created_at_unix
                .cmp(&b.created_at_unix)
                .then(a.id.cmp(&b.id))
        });
        Ok(wallets)
    }

    fn wallet_path(&self, id: &str) -> PathBuf {
        // The id is generated by us (16 hex chars); still, refuse separators.
        assert!(
            !id.contains(['/', '\\']),
            "wallet id must be a plain hex token"
        );
        self.dir.join(format!("{id}.{WALLET_FILE_SUFFIX}"))
    }

    fn read_file(&self, id: &str) -> Result<WalletFile, WalletCoreError> {
        let path = self.wallet_path(id);
        if !path.exists() {
            return Err(WalletCoreError::NotFound(id.to_string()));
        }
        read_wallet_file(&path)
    }
}

fn read_wallet_file(path: &Path) -> Result<WalletFile, WalletCoreError> {
    let raw = fs::read_to_string(path).map_err(|e| WalletCoreError::Io(e.to_string()))?;
    let file: WalletFile =
        serde_json::from_str(&raw).map_err(|e| WalletCoreError::Corrupted(e.to_string()))?;
    if file.format_version != FORMAT_VERSION {
        return Err(WalletCoreError::UnsupportedVersion(file.format_version));
    }
    Ok(file)
}

fn is_wallet_file(path: &Path) -> bool {
    path.extension().is_some_and(|e| e == "json")
        && path.to_string_lossy().ends_with(&WALLET_FILE_SUFFIX)
}

fn validate_name(name: &str) -> Result<(), WalletCoreError> {
    let trimmed = name.trim();
    if trimmed.is_empty() || trimmed.len() > 64 {
        return Err(WalletCoreError::InvalidName);
    }
    if name.chars().any(|c| c.is_control()) {
        return Err(WalletCoreError::InvalidName);
    }
    Ok(())
}

fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn random_id() -> String {
    let mut bytes = [0u8; 8];
    OsRng.fill_bytes(&mut bytes);
    hex::encode(bytes)
}

/// Atomic write: write to a temp file, then rename over the destination.
fn atomic_write(path: &Path, data: &[u8]) -> Result<(), WalletCoreError> {
    let tmp = path.with_extension("tmp");
    fs::write(&tmp, data).map_err(|e| WalletCoreError::Io(e.to_string()))?;
    // Windows' rename fails if the destination exists; we already refused to
    // overwrite existing wallets before calling here.
    match fs::rename(&tmp, path) {
        Ok(()) => Ok(()),
        Err(e) => {
            let _ = fs::remove_file(&tmp);
            Err(WalletCoreError::Io(e.to_string()))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn name_validation() {
        assert!(validate_name("Main wallet").is_ok());
        assert!(validate_name("  ").is_err());
        assert!(validate_name("").is_err());
        assert!(validate_name(&"x".repeat(65)).is_err());
        assert!(validate_name("bad\nname").is_err());
        assert!(validate_name(&"x".repeat(64)).is_ok());
    }

    #[test]
    fn wallet_file_detection() {
        assert!(is_wallet_file(Path::new("w/abc.wallet.json")));
        assert!(!is_wallet_file(Path::new("w/abc.json")));
        assert!(!is_wallet_file(Path::new("w/abc.wallet.json.tmp")));
    }
}
