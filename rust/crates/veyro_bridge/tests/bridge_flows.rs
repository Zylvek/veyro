//! End-to-end flows through the bridge API, called exactly the way Flutter
//! will call them (plain Rust calls — the FFI glue itself is exercised by the
//! real app build).

use veyro_bridge::api::{backup, storage, wallet};

fn tmp_base() -> String {
    std::env::var("VEYRO_TEST_TMP").unwrap_or_else(|_| r"D:\tmp\veyro-tests".to_string())
}

fn unique_dir(tag: &str) -> String {
    let dir =
        std::path::Path::new(&tmp_base()).join(format!("bridge-{}-{}", std::process::id(), tag));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir.to_string_lossy().into_owned()
}

#[test]
fn wallet_lifecycle_flow() {
    let dir = unique_dir("lifecycle");

    let created = wallet::create_wallet(dir.clone(), "Main".into(), "pw 123".into(), 24).unwrap();
    assert_eq!(created.mnemonic_phrase.split_whitespace().count(), 24);

    let listed = wallet::list_wallets(dir.clone()).unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].name, "Main");
    assert_eq!(listed[0].id, created.info.id);

    // Wrong password must be rejected.
    assert!(wallet::unlock_wallet(dir.clone(), created.info.id.clone(), "no".into()).is_err());

    let unlocked =
        wallet::unlock_wallet(dir.clone(), created.info.id.clone(), "pw 123".into()).unwrap();
    assert_eq!(unlocked.id, created.info.id);
    assert_eq!(unlocked.name, "Main");

    let revealed =
        wallet::reveal_mnemonic(dir.clone(), created.info.id.clone(), "pw 123".into()).unwrap();
    assert_eq!(revealed, created.mnemonic_phrase);

    // Unsupported mnemonic lengths must be rejected up front.
    assert!(wallet::create_wallet(dir.clone(), "Bad".into(), "pw".into(), 18).is_err());
    // Empty name must be rejected by the core.
    assert!(wallet::create_wallet(dir.clone(), "  ".into(), "pw".into(), 12).is_err());
}

#[test]
fn backup_roundtrip_keeps_secrets_in_rust() {
    let dir = unique_dir("backup-src");
    let restore_dir = unique_dir("backup-dst");

    let a = wallet::create_wallet(dir.clone(), "A".into(), "pa".into(), 12).unwrap();
    let b = wallet::create_wallet(dir.clone(), "B".into(), "pb".into(), 12).unwrap();

    let backup_path = std::path::Path::new(&tmp_base())
        .join(format!("bridge-backup-{}.json", std::process::id()));
    let out_path = backup_path.to_string_lossy().into_owned();

    // Export with a wrong password for wallet B must fail and write nothing.
    assert!(backup::export_backup(
        dir.clone(),
        vec![
            backup::BackupWalletRequest {
                wallet_id: a.info.id.clone(),
                password: "pa".into(),
            },
            backup::BackupWalletRequest {
                wallet_id: b.info.id.clone(),
                password: "WRONG".into(),
            },
        ],
        "backup pw".into(),
        out_path.clone(),
    )
    .is_err());
    assert!(!std::path::Path::new(&out_path).exists());

    // Empty selection must be rejected.
    assert!(
        backup::export_backup(dir.clone(), vec![], "backup pw".into(), out_path.clone(),).is_err()
    );

    backup::export_backup(
        dir.clone(),
        vec![
            backup::BackupWalletRequest {
                wallet_id: a.info.id.clone(),
                password: "pa".into(),
            },
            backup::BackupWalletRequest {
                wallet_id: b.info.id.clone(),
                password: "pb".into(),
            },
        ],
        "backup pw".into(),
        out_path.clone(),
    )
    .unwrap();

    // Wrong backup password must fail before anything is restored.
    assert!(backup::import_backup(
        restore_dir.clone(),
        out_path.clone(),
        "wrong".into(),
        "device pw".into(),
    )
    .is_err());
    assert!(wallet::list_wallets(restore_dir.clone())
        .unwrap()
        .is_empty());

    let imported = backup::import_backup(
        restore_dir.clone(),
        out_path.clone(),
        "backup pw".into(),
        "device pw".into(),
    )
    .unwrap();
    let names: Vec<_> = imported.iter().map(|w| w.name.clone()).collect();
    assert!(names.contains(&"A".to_string()));
    assert!(names.contains(&"B".to_string()));

    // Restored wallets unlock with the NEW device password and reveal the
    // original phrases.
    let a_id = imported.iter().find(|w| w.name == "A").unwrap().id.clone();
    let phrase = wallet::reveal_mnemonic(restore_dir.clone(), a_id, "device pw".into()).unwrap();
    assert_eq!(phrase, a.mnemonic_phrase);

    let listed = wallet::list_wallets(restore_dir).unwrap();
    assert_eq!(listed.len(), 2);
}

#[test]
fn storage_roundtrip_via_singleton() {
    let db_path =
        std::path::Path::new(&tmp_base()).join(format!("bridge-db-{}.sqlite", std::process::id()));
    let _ = std::fs::remove_file(&db_path);
    let db_path = db_path.to_string_lossy().into_owned();

    storage::db_open(db_path.clone()).unwrap();
    assert!(storage::db_schema_version().unwrap() >= 1);

    storage::db_upsert_wallet(storage::WalletRowDto {
        id: "abc123".into(),
        name: "Main".into(),
        created_at_unix: 123,
        vault_file: "abc123.wallet.json".into(),
    })
    .unwrap();

    let wallets = storage::db_list_wallets().unwrap();
    assert_eq!(wallets.len(), 1);
    assert_eq!(wallets[0].id, "abc123");
    assert_eq!(wallets[0].vault_file, "abc123.wallet.json");

    storage::db_set_setting("theme".into(), "dark".into()).unwrap();
    assert_eq!(
        storage::db_get_setting("theme".into()).unwrap().as_deref(),
        Some("dark")
    );

    // Close -> operations must fail; reopen -> data persists.
    storage::db_close().unwrap();
    assert!(storage::db_get_setting("theme".into()).is_err());
    storage::db_open(db_path).unwrap();
    assert_eq!(
        storage::db_get_setting("theme".into()).unwrap().as_deref(),
        Some("dark")
    );

    assert!(storage::db_delete_wallet("abc123".into()).unwrap());
    assert!(storage::db_list_wallets().unwrap().is_empty());
    storage::db_close().unwrap();
}
