//! Encrypted backup export/import. This flow lives in Rust (not Dart)
//! precisely so that wallet secrets never cross the FFI boundary:
//! export decrypts vaults inside Rust, import restores straight into new
//! vault files. Only user-typed passwords cross the boundary — by design.

use crate::production_kdf;
use anyhow::{anyhow, Result};
use backup_manager::{self, BackupFile, WalletSecretInput};
use wallet_core::WalletManager;

use super::wallet::WalletInfoDto;

/// One wallet to include in a backup, with its unlock password.
pub struct BackupWalletRequest {
    pub wallet_id: String,
    pub password: String,
}

/// Export the selected wallets into an encrypted backup file.
///
/// Each wallet's password is required: its vault must be decrypted one last
/// time to read the phrase and the BIP39 passphrase. The backup file itself
/// is protected by `backup_password`, which is independent of the wallet
/// passwords.
pub fn export_backup(
    wallets_dir: String,
    requests: Vec<BackupWalletRequest>,
    backup_password: String,
    out_path: String,
) -> Result<()> {
    if requests.is_empty() {
        return Err(anyhow!("select at least one wallet for the backup"));
    }
    let manager = WalletManager::open(&wallets_dir, production_kdf())?;
    let listed = manager.list()?;

    let mut inputs = Vec::with_capacity(requests.len());
    for request in requests {
        // The wallet name is public metadata; the password is validated by
        // the decryption inside `reveal_secrets` (one Argon2id run, not two).
        let name = listed
            .iter()
            .find(|w| w.id == request.wallet_id)
            .map(|w| w.name.clone())
            .ok_or_else(|| anyhow!("wallet not found: {}", request.wallet_id))?;
        let secrets = manager.reveal_secrets(&request.wallet_id, &request.password)?;
        inputs.push(WalletSecretInput {
            name,
            phrase: secrets.phrase,
            passphrase: secrets.passphrase,
        });
    }

    let backup = backup_manager::export(inputs, &backup_password, production_kdf())?;
    backup.to_file(&out_path)?;
    Ok(())
}

/// Import wallets from an encrypted backup and re-vault them with
/// `new_wallet_password` — the password of THIS device, chosen fresh by the
/// user and independent of the backup password. Returns the imported wallet
/// metadata. No secrets cross the FFI boundary.
pub fn import_backup(
    wallets_dir: String,
    backup_path: String,
    backup_password: String,
    new_wallet_password: String,
) -> Result<Vec<WalletInfoDto>> {
    let backup = BackupFile::from_file(&backup_path)?;
    let restored = backup_manager::import(&backup, &backup_password)?;
    let manager = WalletManager::open(&wallets_dir, production_kdf())?;

    let mut imported = Vec::with_capacity(restored.len());
    for secret in restored {
        let wallet = manager.restore(
            &secret.name,
            &new_wallet_password,
            &secret.phrase,
            &secret.passphrase,
        )?;
        imported.push(wallet.info.into());
    }
    Ok(imported)
}
