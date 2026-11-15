//! Диагностический проб: реальные btc_unlock/btc_sync против живого
//! сервера с реальным vault'ом (без Dart). Печатает точную ошибку.

use veyro_bridge::api::{btc, wallet};

#[test]
#[ignore]
fn probe_real_unlock_sync() {
    let dir = format!(
        "{}\\AppData\\Roaming\\veyro\\wallets",
        std::env::var("USERPROFILE").unwrap()
    );
    let list = wallet::list_wallets(dir.clone()).unwrap();
    for w in &list {
        println!(
            "WALLET id={} name={} created={}",
            w.id, w.name, w.created_at_unix
        );
    }

    for (id, network, server) in [
        (
            "49a232f78a37477a",
            0u32,
            "ssl://fulcrum.bullbitcoin.com:50002",
        ),
        (
            "517cc921fd3c6f7e",
            0u32,
            "ssl://fulcrum.bullbitcoin.com:50002",
        ),
        ("49a232f78a37477a", 2u32, "ssl://blackie.c3-soft.com:57010"),
        ("517cc921fd3c6f7e", 2u32, "ssl://blackie.c3-soft.com:57010"),
    ] {
        println!("--- unlock id={id} network={network} server={server} ---");
        match btc::btc_unlock(
            dir.clone(),
            id.into(),
            "1234".into(),
            network,
            server.into(),
        ) {
            Ok(d) => println!("UNLOCK OK xpub={}", d.account_xpub),
            Err(e) => {
                println!("UNLOCK ERR: {e:#}");
                continue;
            }
        }
        match btc::btc_sync(20) {
            Ok(s) => println!(
                "SYNC OK confirmed={} delta={} tip={} utxos={} used={}",
                s.confirmed_sat,
                s.unconfirmed_delta_sat,
                s.tip_height,
                s.utxo_count,
                s.used_addresses.len()
            ),
            Err(e) => println!("SYNC ERR: {e:#}"),
        }
        let _ = btc::btc_lock();
    }
}
