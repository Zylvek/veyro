//! End-to-end flows through the bridge API, called exactly the way Flutter
//! will call them (plain Rust calls — the FFI glue itself is exercised by the
//! real app build).

use veyro_bridge::api::{storage, wallet};

fn tmp_base() -> String {
    std::env::var("VEYRO_TEST_TMP").unwrap_or_else(|_| std::env::temp_dir().join("veyro-tests").display().to_string())
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
fn settings_flow_via_singleton() {
    let db_path =
        std::path::Path::new(&tmp_base()).join(format!("bridge-db-{}.sqlite", std::process::id()));
    let _ = std::fs::remove_file(&db_path);
    let db_path = db_path.to_string_lossy().into_owned();

    storage::db_open(db_path.clone()).unwrap();
    assert!(storage::db_schema_version().unwrap() >= 1);

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

    storage::db_close().unwrap();
}
