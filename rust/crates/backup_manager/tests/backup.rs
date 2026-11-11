//! Integration tests for `backup_manager`.
//! Use light (but valid) Argon2id parameters to keep the suite fast.

use backup_manager::{export, import, BackupError, BackupFile, WalletSecretInput};
use crypto_vault::KdfParams;
use std::path::PathBuf;
use zeroize::Zeroizing;

fn light_kdf() -> KdfParams {
    KdfParams {
        m_kib: 8192,
        t: 1,
        p: 1,
    }
}

fn sample_secrets() -> Vec<WalletSecretInput> {
    vec![
        WalletSecretInput {
            name: "Main".into(),
            phrase: Zeroizing::new(
                "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about".into(),
            ),
            passphrase: Zeroizing::new(String::new()),
        },
        WalletSecretInput {
            name: "Savings".into(),
            phrase: Zeroizing::new(
                "legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth title".into(),
            ),
            passphrase: Zeroizing::new("25th-word".into()),
        },
    ]
}

fn test_dir(tag: &str) -> PathBuf {
    let base =
        std::env::var("VEYRO_TEST_TMP").unwrap_or_else(|_| r"D:\tmp\veyro-tests".to_string());
    let dir = std::path::Path::new(&base).join(format!("backup-{}-{tag}", std::process::id()));
    let _ = std::fs::create_dir_all(&dir);
    dir
}

#[test]
fn export_import_roundtrip() {
    let backup = export(sample_secrets(), "backup-pw", light_kdf()).unwrap();
    let restored = import(&backup, "backup-pw").unwrap();

    assert_eq!(restored.len(), 2);
    assert_eq!(restored[0].name, "Main");
    assert_eq!(&*restored[0].phrase, "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about");
    assert_eq!(&*restored[0].passphrase, "");
    assert_eq!(restored[1].name, "Savings");
    assert_eq!(&*restored[1].passphrase, "25th-word");
}

#[test]
fn wrong_backup_password_fails() {
    let backup = export(sample_secrets(), "correct", light_kdf()).unwrap();
    assert!(matches!(
        import(&backup, "wrong"),
        Err(BackupError::Vault(_))
    ));
}

#[test]
fn empty_export_rejected() {
    assert!(matches!(
        export(vec![], "pw", light_kdf()),
        Err(BackupError::Empty)
    ));
}

#[test]
fn tampered_backup_fails() {
    let mut backup = export(sample_secrets(), "pw", light_kdf()).unwrap();
    let mid = backup.vault.ciphertext.len() / 2;
    backup.vault.ciphertext[mid] ^= 0x01;
    assert!(matches!(import(&backup, "pw"), Err(BackupError::Vault(_))));
}

#[test]
fn unsupported_version_rejected() {
    let mut backup = export(sample_secrets(), "pw", light_kdf()).unwrap();
    backup.version = 99;
    assert!(matches!(
        import(&backup, "pw"),
        Err(BackupError::UnsupportedVersion(99))
    ));
}

#[test]
fn wrong_app_id_rejected() {
    let mut backup = export(sample_secrets(), "pw", light_kdf()).unwrap();
    backup.app = "SOMETHING-ELSE".into();
    assert!(matches!(
        import(&backup, "pw"),
        Err(BackupError::Malformed(_))
    ));
}

#[test]
fn json_and_file_roundtrip() {
    let backup = export(sample_secrets(), "pw", light_kdf()).unwrap();

    let json = backup.to_json().unwrap();
    let parsed = BackupFile::from_json(&json).unwrap();
    let restored = import(&parsed, "pw").unwrap();
    assert_eq!(restored.len(), 2);

    // The header is public JSON; the payload must not leak any phrase words.
    assert!(!json.contains("abandon"));
    assert!(json.contains("VEYRO-BACKUP"));

    let dir = test_dir("file");
    let path = dir.join("wallet.backup.json");
    let _ = std::fs::remove_file(&path);
    backup.to_file(&path).unwrap();
    let loaded = BackupFile::from_file(&path).unwrap();
    let restored2 = import(&loaded, "pw").unwrap();
    assert_eq!(restored2.len(), 2);
    assert_eq!(restored2[1].name, "Savings");
}

#[test]
fn debug_never_leaks_secrets() {
    let backup = export(sample_secrets(), "pw", light_kdf()).unwrap();
    let debug = format!("{backup:?}");
    assert!(!debug.contains("abandon"));
    assert!(!debug.contains("25th-word"));
    assert!(debug.contains("VEYRO"));
}
