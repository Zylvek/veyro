//! Integration tests for `wallet_core`.
//!
//! Test data lives on drive D only (`MULTIWALLET_TEST_TMP`, default
//! `D:\tmp\multiwallet-tests`), per project environment constraint.

use crypto_vault::KdfParams;
use key_manager::{from_phrase, Seed, Strength};
use wallet_core::{RestoredWallet, WalletCoreError, WalletManager};

use std::collections::HashSet;
use std::sync::{Mutex, OnceLock};

fn test_dir(tag: &str) -> std::path::PathBuf {
    // Wipe each tag's directory exactly once per process; later calls must
    // return the same path without destroying state.
    static INIT: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();
    let registry = INIT.get_or_init(|| Mutex::new(HashSet::new()));
    let first = registry.lock().unwrap().insert(tag.to_string());

    let base = std::env::var("MULTIWALLET_TEST_TMP")
        .unwrap_or_else(|_| r"D:\tmp\multiwallet-tests".to_string());
    let dir = std::path::Path::new(&base).join(format!("{}-{}", std::process::id(), tag));
    if first {
        let _ = std::fs::remove_dir_all(&dir);
    }
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

// Light Argon2id for fast tests (validated range, real KDF).
fn test_kdf() -> KdfParams {
    KdfParams {
        m_kib: 8192,
        t: 1,
        p: 1,
    }
}

fn open(tag: &str) -> WalletManager {
    WalletManager::open(test_dir(tag), test_kdf()).unwrap()
}

#[test]
fn create_unlock_roundtrip() {
    let mgr = open("create_roundtrip");

    let created = mgr
        .create("Main", "strong password", Strength::Words24)
        .unwrap();
    let phrase = created.mnemonic_phrase.clone();

    let unlocked = mgr.unlock(&created.info.id, "strong password").unwrap();
    assert_eq!(unlocked.info.name, "Main");

    // The unlocked seed must equal an independent derivation from the phrase.
    let reference: Seed = from_phrase(&phrase).unwrap().to_seed("");
    assert_eq!(unlocked.seed.as_bytes(), reference.as_bytes());
}

#[test]
fn wrong_password_fails() {
    let mgr = open("wrong_password");
    let created = mgr.create("W", "correct pw", Strength::Words12).unwrap();
    assert!(matches!(
        mgr.unlock(&created.info.id, "wrong pw"),
        Err(WalletCoreError::Vault(_))
    ));
}

#[test]
fn unlock_nonexistent_fails() {
    let mgr = open("nonexistent");
    assert!(matches!(
        mgr.unlock("0000000000000000", "pw"),
        Err(WalletCoreError::NotFound(_))
    ));
}

#[test]
fn wallet_file_contains_no_plaintext_secrets() {
    let mgr = open("no_plaintext");
    let created = mgr
        .create("SecretTest", "pw123", Strength::Words24)
        .unwrap();

    let path = test_dir("no_plaintext").join(format!("{}.wallet.json", created.info.id));
    let content = std::fs::read_to_string(&path).unwrap();

    // No mnemonic words in the file.
    for word in created.mnemonic_phrase.split(' ') {
        assert!(
            !content.contains(word),
            "file leaked mnemonic word '{word}'"
        );
    }
    // No raw seed (hex of first 16 bytes of the seed never appears).
    let unlocked = mgr.unlock(&created.info.id, "pw123").unwrap();
    let seed_prefix = hex::encode(&unlocked.seed.as_bytes()[..16]);
    assert!(!content.contains(&seed_prefix), "file leaked seed bytes");
    // No plaintext secret field names inside (payload is encrypted as a whole).
    assert!(!content.contains("\"phrase\""));
    assert!(!content.contains("\"seed\""));
    // And no leftovers from atomic writes.
    assert!(!content.contains(".tmp"));
}

#[test]
fn restore_produces_same_seed_as_original() {
    let mgr = open("restore_same_seed");
    let created = mgr.create("Orig", "pw", Strength::Words24).unwrap();
    let phrase = created.mnemonic_phrase.clone();

    let restored: RestoredWallet = mgr.restore("Copy", "pw", &phrase, "").unwrap();
    assert_ne!(restored.info.id, created.info.id);

    let orig = mgr.unlock(&created.info.id, "pw").unwrap();
    let copy = mgr.unlock(&restored.info.id, "pw").unwrap();
    assert_eq!(orig.seed.as_bytes(), copy.seed.as_bytes());
}

#[test]
fn restore_with_bip39_passphrase_changes_seed() {
    let mgr = open("passphrase_changes_seed");
    let created = mgr.create("A", "pw", Strength::Words12).unwrap();
    let phrase = created.mnemonic_phrase.clone();

    let with_empty: RestoredWallet = mgr.restore("B", "pw", &phrase, "").unwrap();
    let with_pass: RestoredWallet = mgr
        .restore("C", "pw", &phrase, "my-secret-passphrase")
        .unwrap();

    let base = mgr.unlock(&with_empty.info.id, "pw").unwrap();
    let extended = mgr.unlock(&with_pass.info.id, "pw").unwrap();
    assert_ne!(base.seed.as_bytes(), extended.seed.as_bytes());

    // And it matches an independent derivation with the passphrase.
    let reference = from_phrase(&phrase)
        .unwrap()
        .to_seed("my-secret-passphrase");
    assert_eq!(extended.seed.as_bytes(), reference.as_bytes());
}

#[test]
fn restore_rejects_bad_phrase() {
    let mgr = open("restore_bad_phrase");
    assert!(matches!(
        mgr.restore("X", "pw", "totally invalid words here", ""),
        Err(WalletCoreError::KeyManager(_))
    ));
}

#[test]
fn list_shows_created_wallets() {
    let mgr = open("list");
    assert!(mgr.list().unwrap().is_empty());

    let a = mgr.create("Alpha", "pw", Strength::Words12).unwrap();
    let b = mgr.create("Beta", "pw", Strength::Words12).unwrap();

    let mut ids: Vec<String> = mgr.list().unwrap().into_iter().map(|w| w.id).collect();
    ids.sort();
    let mut expected = vec![a.info.id.clone(), b.info.id.clone()];
    expected.sort();
    assert_eq!(ids, expected);
    assert_ne!(a.info.id, b.info.id);
}

#[test]
fn reveal_mnemonic_requires_password_and_matches() {
    let mgr = open("reveal");
    let created = mgr.create("R", "correct", Strength::Words24).unwrap();

    assert!(matches!(
        mgr.reveal_mnemonic(&created.info.id, "incorrect"),
        Err(WalletCoreError::Vault(_))
    ));

    let revealed = mgr.reveal_mnemonic(&created.info.id, "correct").unwrap();
    assert_eq!(&*revealed, &*created.mnemonic_phrase);
}

#[test]
fn invalid_names_rejected() {
    let mgr = open("invalid_names");
    assert!(matches!(
        mgr.create("", "pw", Strength::Words12),
        Err(WalletCoreError::InvalidName)
    ));
    assert!(matches!(
        mgr.create(&"x".repeat(65), "pw", Strength::Words12),
        Err(WalletCoreError::InvalidName)
    ));
    assert!(matches!(
        mgr.create("bad\tname", "pw", Strength::Words12),
        Err(WalletCoreError::InvalidName)
    ));
}

#[test]
fn created_files_are_atomic_and_clean() {
    let mgr = open("atomic_clean");
    let created = mgr.create("Atomic", "pw", Strength::Words12).unwrap();
    let dir = test_dir("atomic_clean");
    let leftovers: Vec<_> = std::fs::read_dir(&dir)
        .unwrap()
        .map(|e| e.unwrap().file_name().to_string_lossy().to_string())
        .filter(|n| n.ends_with(".tmp"))
        .collect();
    assert!(leftovers.is_empty());
    assert!(dir
        .join(format!("{}.wallet.json", created.info.id))
        .exists());
}
