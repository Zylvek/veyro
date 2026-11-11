//! Integration tests for `storage`.
//! File-based tests live on drive D only (`VEYRO_TEST_TMP`).

use rusqlite::Connection;
use storage::{Db, StorageError};

fn test_dir(tag: &str) -> std::path::PathBuf {
    let base =
        std::env::var("VEYRO_TEST_TMP").unwrap_or_else(|_| r"D:\tmp\veyro-tests".to_string());
    let dir = std::path::Path::new(&base).join(format!("storage-{}-{tag}", std::process::id()));
    let _ = std::fs::create_dir_all(&dir);
    dir
}

#[test]
fn wallet_registry_roundtrip_and_delete() {
    let db = Db::open_in_memory().unwrap();

    let w = storage::WalletRow {
        id: "abcd".into(),
        name: "Main".into(),
        created_at_unix: 1000,
        vault_file: "abcd.wallet.json".into(),
    };
    db.upsert_wallet(&w).unwrap();
    assert_eq!(db.list_wallets().unwrap(), vec![w.clone()]);

    // Upsert updates name without duplicating.
    let mut w2 = w.clone();
    w2.name = "Renamed".into();
    db.upsert_wallet(&w2).unwrap();
    let listed = db.list_wallets().unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].name, "Renamed");

    // Addresses cascade on wallet delete.
    db.upsert_address(&storage::AddressRow {
        wallet_id: "abcd".into(),
        chain: "btc".into(),
        account_index: 0,
        address_index: 0,
        address: "bc1qexample".into(),
        label: Some("pool payout".into()),
        created_at_unix: 1234,
    })
    .unwrap();
    assert!(!db.list_addresses("abcd", "btc").unwrap().is_empty());

    assert!(db.delete_wallet("abcd").unwrap());
    assert!(db.list_wallets().unwrap().is_empty());
    assert!(db.list_addresses("abcd", "btc").unwrap().is_empty());
    assert!(!db.delete_wallet("abcd").unwrap()); // already gone
}

#[test]
fn address_upsert_updates_same_slot() {
    let db = Db::open_in_memory().unwrap();
    db.upsert_wallet(&storage::WalletRow {
        id: "w1".into(),
        name: "W".into(),
        created_at_unix: 1,
        vault_file: "w1.wallet.json".into(),
    })
    .unwrap();

    for addr in ["addr-1", "addr-2"] {
        db.upsert_address(&storage::AddressRow {
            wallet_id: "w1".into(),
            chain: "kas".into(),
            account_index: 0,
            address_index: 0,
            address: addr.into(),
            label: None,
            created_at_unix: 5,
        })
        .unwrap();
    }
    let listed = db.list_addresses("w1", "kas").unwrap();
    assert_eq!(listed.len(), 1); // same slot, updated
    assert_eq!(listed[0].address, "addr-2");
}

#[test]
fn contacts_unique_and_filtering() {
    let db = Db::open_in_memory().unwrap();
    db.insert_contact("Pool", "kas", "kaspa:qabc", Some("2miners"))
        .unwrap();

    // Same chain+address is rejected by the UNIQUE constraint.
    assert!(db
        .insert_contact("Pool again", "kas", "kaspa:qabc", None)
        .is_err());

    let other = db.insert_contact("Friend", "btc", "bc1qxyz", None).unwrap();
    assert_ne!(other.id, 0);

    assert_eq!(db.list_contacts(None).unwrap().len(), 2);
    assert_eq!(db.list_contacts(Some("btc")).unwrap().len(), 1);
    assert!(db.delete_contact(other.id).unwrap());
    assert_eq!(db.list_contacts(None).unwrap().len(), 1);
}

#[test]
fn node_endpoints_primary_semantics() {
    let db = Db::open_in_memory().unwrap();
    db.upsert_node_endpoint("btc", "home node", "http://127.0.0.1:8332", true, true, 1)
        .unwrap();
    db.upsert_node_endpoint("btc", "public", "http://example.test:8332", false, true, 2)
        .unwrap();
    // Upserting the same URL updates instead of duplicating.
    db.upsert_node_endpoint(
        "btc",
        "public renamed",
        "http://example.test:8332",
        false,
        false,
        3,
    )
    .unwrap();

    let nodes = db.list_node_endpoints("btc").unwrap();
    assert_eq!(nodes.len(), 2);
    assert!(nodes[0].is_primary);
    assert_eq!(nodes[1].name, "public renamed");
    assert!(!nodes[1].enabled);

    db.set_primary_node("btc", nodes[1].id).unwrap();
    let promoted = nodes[1].id;
    let nodes = db.list_node_endpoints("btc").unwrap();
    assert_eq!(nodes.len(), 2);
    for n in &nodes {
        // Exactly the promoted endpoint is primary; the list puts it first.
        assert_eq!(n.is_primary, n.id == promoted);
    }
    assert_eq!(nodes[0].id, promoted);
}

#[test]
fn tx_labels_upsert() {
    let db = Db::open_in_memory().unwrap();
    assert_eq!(db.get_tx_label("btc", "tx1").unwrap(), None);
    db.set_tx_label("btc", "tx1", "pool payout").unwrap();
    db.set_tx_label("btc", "tx1", "renamed").unwrap();
    assert_eq!(
        db.get_tx_label("btc", "tx1").unwrap().as_deref(),
        Some("renamed")
    );
    assert_eq!(db.get_tx_label("kas", "tx1").unwrap(), None);
}

#[test]
fn price_cache_decimal_strings() {
    let db = Db::open_in_memory().unwrap();
    db.set_price(&storage::PriceEntryRow {
        ticker: "BTC".into(),
        fiat: "USD".into(),
        price: "104321.55".into(),
        updated_at_unix: 42,
    })
    .unwrap();
    db.set_price(&storage::PriceEntryRow {
        ticker: "BTC".into(),
        fiat: "USD".into(),
        price: "104500.00".into(),
        updated_at_unix: 43,
    })
    .unwrap();
    let got = db.get_price("BTC", "USD").unwrap().unwrap();
    assert_eq!(got.price, "104500.00");
    assert_eq!(got.updated_at_unix, 43);
}

#[test]
fn settings_roundtrip() {
    let db = Db::open_in_memory().unwrap();
    assert_eq!(db.get_setting("fiat").unwrap(), None);
    db.set_setting("fiat", "USD").unwrap();
    db.set_setting("fiat", "RUB").unwrap();
    assert_eq!(db.get_setting("fiat").unwrap().as_deref(), Some("RUB"));
}

#[test]
fn file_db_persists_across_reopen() {
    let dir = test_dir("reopen");
    let path = dir.join("app.sqlite");
    let _ = std::fs::remove_file(&path);

    {
        let db = Db::open(&path).unwrap();
        db.set_setting("currency", "EUR").unwrap();
        db.set_tx_label("btc", "tx9", "wage").unwrap();
    }
    {
        let db = Db::open(&path).unwrap();
        assert_eq!(db.get_setting("currency").unwrap().as_deref(), Some("EUR"));
        assert_eq!(
            db.get_tx_label("btc", "tx9").unwrap().as_deref(),
            Some("wage")
        );
        assert_eq!(db.schema_version().unwrap(), storage::SCHEMA_VERSION);
    }
}

#[test]
fn future_schema_rejected() {
    let dir = test_dir("future");
    let path = dir.join("future.sqlite");
    let _ = std::fs::remove_file(&path);

    {
        // Simulate a DB created by a newer VEYRO version.
        let conn = Connection::open(&path).unwrap();
        conn.execute_batch(
            "CREATE TABLE wallets (id TEXT);
             PRAGMA user_version = 99;",
        )
        .unwrap();
    }

    match Db::open(&path) {
        Err(StorageError::FutureSchema(99)) => {}
        Err(e) => panic!("expected FutureSchema(99), got error: {e:?}"),
        Ok(_) => panic!("expected FutureSchema(99), got Ok"),
    }
}
