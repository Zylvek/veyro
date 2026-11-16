//! Wallet lifecycle operations (thin wrappers over `wallet_core`).
//!
//! Conventions:
//! - the wallets directory is passed per call — the UI owns locations;
//! - passwords (and, on create/reveal, the mnemonic phrase) are the only
//!   secrets crossing this boundary — see the crate docs for the contract;
//! - the bridge keeps no state: `WalletManager::open` per call.

use crate::production_kdf;
use anyhow::{anyhow, Result};
use wallet_core::{WalletInfo, WalletManager};

/// Non-secret wallet metadata as shown in the UI.
pub struct WalletInfoDto {
    pub id: String,
    pub name: String,
    pub created_at_unix: u64,
}

impl From<WalletInfo> for WalletInfoDto {
    fn from(info: WalletInfo) -> Self {
        Self {
            id: info.id,
            name: info.name,
            created_at_unix: info.created_at_unix,
        }
    }
}

/// Result of wallet creation: the phrase is shown to the user exactly once.
pub struct CreatedWalletDto {
    pub info: WalletInfoDto,
    /// Display once, then drop from UI memory. Never stored in plaintext.
    pub mnemonic_phrase: String,
}

/// Create a new wallet. `word_count` must be 12 or 24.
pub fn create_wallet(
    wallets_dir: String,
    name: String,
    password: String,
    word_count: u32,
) -> Result<CreatedWalletDto> {
    let strength = match word_count {
        12 => key_manager::Strength::Words12,
        24 => key_manager::Strength::Words24,
        n => {
            return Err(anyhow!(
                "unsupported mnemonic length: {n} words (expected 12 or 24)"
            ))
        }
    };
    let manager = WalletManager::open(&wallets_dir, production_kdf())?;
    let created = manager.create(&name, &password, strength)?;
    Ok(CreatedWalletDto {
        info: created.info.into(),
        mnemonic_phrase: created.mnemonic_phrase.to_string(),
    })
}

/// Restore a wallet from a BIP39 phrase (with optional passphrase).
/// The phrase is NOT re-displayed: the user already has it.
pub fn restore_wallet(
    wallets_dir: String,
    name: String,
    password: String,
    phrase: String,
    passphrase: String,
) -> Result<WalletInfoDto> {
    let manager = WalletManager::open(&wallets_dir, production_kdf())?;
    Ok(manager
        .restore(&name, &password, &phrase, &passphrase)?
        .info
        .into())
}

/// Verify the wallet password (returns wallet metadata on success).
///
/// The decrypted seed stays inside Rust and never crosses the FFI boundary:
/// signing will happen in the Rust chain adapters (Phase 4), not in Dart.
/// English BIP39 wordlist (2048 words, audited crate `bip39`) for the
/// seed-input suggestions on the import screen: prefix matches first,
/// closest-by-edit-distance fallback. Public data — the wordlist is a
/// published standard.
pub fn bip39_wordlist() -> Vec<String> {
    bip39::Language::English
        .word_list()
        .iter()
        .map(|s| s.to_string())
        .collect()
}

pub fn unlock_wallet(wallets_dir: String, id: String, password: String) -> Result<WalletInfoDto> {
    let manager = WalletManager::open(&wallets_dir, production_kdf())?;
    Ok(manager.unlock(&id, &password)?.info.into())
}

/// Explicit user action: reveal the mnemonic phrase (requires the password).
pub fn reveal_mnemonic(wallets_dir: String, id: String, password: String) -> Result<String> {
    let manager = WalletManager::open(&wallets_dir, production_kdf())?;
    Ok(manager.reveal_mnemonic(&id, &password)?.to_string())
}

/// List wallets (public metadata only).
pub fn list_wallets(wallets_dir: String) -> Result<Vec<WalletInfoDto>> {
    let manager = WalletManager::open(&wallets_dir, production_kdf())?;
    Ok(manager.list()?.into_iter().map(Into::into).collect())
}
