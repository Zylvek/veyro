//! Gated end-to-end cycle on a LIVE Bitcoin testnet (NOT part of CI):
//! faucet-funded self-transfer through the public bridge API —
//! unlock (genesis) → sync → fees → send → broadcast → status →
//! re-sync → history → optional confirmation wait → lock.
//!
//! The recipient is the wallet's own fresh receive address, so no third
//! party is involved and the only thing spent from the network's view is
//! the miner fee.
//!
//! Env:
//! - `VEYRO_E2E=1` — safety gate (abort unless exactly "1");
//! - `VEYRO_E2E_PHRASE` — BIP39 words of the faucet-funded wallet;
//! - `VEYRO_E2E_SERVER` — optional; defaults to the server probe-verified
//!   for the chosen network (see chains/tests/e2e_probe.rs);
//! - `VEYRO_E2E_NETWORK` — mainnet|testnet|testnet4 (default testnet4);
//! - `VEYRO_E2E_SEND_SAT` — self-transfer amount, default 5000, clamped
//!   to half the confirmed balance;
//! - `VEYRO_E2E_WAIT_SECS` — poll the new tx for confirmation up to N
//!   seconds (default 0: mempool status is enough for the cycle).
//!
//! Run (PowerShell):
//!   $env:VEYRO_E2E='1'; $env:VEYRO_E2E_PHRASE='...';
//!   cargo test -p veyro_bridge --test e2e_testnet -- --ignored --nocapture

use veyro_bridge::api::btc;
use veyro_bridge::api::wallet;

fn tmp_dir() -> String {
    let base =
        std::env::var("VEYRO_TEST_TMP").unwrap_or_else(|_| r"D:\tmp\veyro-tests".to_string());
    let dir = std::path::Path::new(&base).join(format!("e2e-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir.to_string_lossy().into_owned()
}

fn network_code() -> u32 {
    match std::env::var("VEYRO_E2E_NETWORK")
        .unwrap_or_default()
        .as_str()
    {
        "mainnet" => 0,
        "testnet" => 1,
        // Default testnet4: it is today the only bitcoin testnet with a
        // captcha-free faucet (bitcoinfaucet.uo1.net) and a verified
        // Fulcrum server (ssl://blackie.c3-soft.com:57010).
        _ => 2,
    }
}

fn default_server(network_code: u32) -> &'static str {
    match network_code {
        0 => "ssl://fulcrum.bullbitcoin.com:50002",
        1 => "ssl://electrum.blockstream.info:60002",
        _ => "ssl://blackie.c3-soft.com:57010",
    }
}

#[test]
#[ignore = "live-network test: needs VEYRO_E2E=1 plus VEYRO_E2E_PHRASE of a funded wallet"]
fn full_cycle_testnet() {
    if std::env::var("VEYRO_E2E").as_deref() != Ok("1") {
        panic!("safety gate: set VEYRO_E2E=1 to run the live testnet cycle");
    }
    let phrase = std::env::var("VEYRO_E2E_PHRASE").expect("set VEYRO_E2E_PHRASE");
    let network_code = network_code();
    let server = std::env::var("VEYRO_E2E_SERVER")
        .unwrap_or_else(|_| default_server(network_code).to_string());
    let send_sat: u64 = std::env::var("VEYRO_E2E_SEND_SAT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(5000);
    let wait_secs: u64 = std::env::var("VEYRO_E2E_WAIT_SECS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(0);

    let dir = tmp_dir();
    let password = "e2e password 123";

    // 1. Deterministic wallet from the fixed faucet phrase.
    let created = wallet::restore_wallet(
        dir.clone(),
        "E2E".into(),
        password.into(),
        phrase,
        "".into(),
    )
    .expect("restore from phrase");
    println!("[1] wallet id {}", created.id);

    // 2. Unlock — the genesis fund-safety check runs inside.
    let unlock = btc::btc_unlock(dir, created.id, password.into(), network_code, server)
        .expect("btc_unlock (server genesis must match the network)");
    println!(
        "[2] {} server={} version={} tip={}",
        unlock.network_display, unlock.server_url, unlock.server_version, unlock.tip_height
    );

    // 3. Sync: the faucet coin must be confirmed.
    let sync = btc::btc_sync(20).expect("btc_sync");
    println!(
        "[3] confirmed={} unconfirmed={} utxos={} tip={}",
        sync.confirmed_sat, sync.unconfirmed_delta_sat, sync.utxo_count, sync.tip_height
    );
    assert!(
        sync.confirmed_sat > 0,
        "no confirmed funds — fund {} via a testnet faucet and wait for the \
         block before running this test (confirmed={} unconfirmed={})",
        sync.next_receive.address,
        sync.confirmed_sat,
        sync.unconfirmed_delta_sat,
    );

    // 4. Server fee presets; keep the slowest above the relay minimum.
    //    When the server cannot estimate (Electrum -1, typical on testnet)
    //    the bridge returns conservative fallback presets and says so.
    let fees = btc::btc_fees().expect("btc_fees");
    let rate = std::cmp::max(fees.slow_sat_vb, 1);
    println!(
        "[4] fees sat/vB fast={} normal={} slow={} (using {rate}) fallback={}",
        fees.fast_sat_vb, fees.normal_sat_vb, fees.slow_sat_vb, fees.fallback
    );

    // 5. Self-transfer to our own fresh address.
    let recv = btc::btc_receive_address().expect("receive address");
    let amount = std::cmp::min(send_sat, sync.confirmed_sat / 2);
    println!("[5] sending {amount} sat -> {}", recv.address);
    let result = btc::btc_send(recv.address.clone(), amount, rate).expect("btc_send");
    println!(
        "[5] txid={} fee={} sat ({} vsize, {} sat/vB) change={} sat status={} already_known={}",
        result.txid,
        result.fee_sat,
        result.vsize,
        result.fee_sat_per_vb,
        result.change_sat.unwrap_or(0),
        result.status,
        result.already_known
    );
    assert!(
        !result.already_known,
        "the first send must be new to the network"
    );
    assert_eq!(result.recipient, recv.address);
    assert_eq!(result.amount_sat, amount);
    assert!(
        result.fee_sat > 0 && result.fee_sat < amount,
        "sane miner fee"
    );

    // 6. Status right after the broadcast: the tx must be visible under the
    //    scanned funding script.
    let status = btc::btc_tx_status(result.txid.clone()).expect("tx status");
    println!(
        "[6] status={} height={:?} confirmations={:?}",
        status.state, status.height, status.confirmations
    );
    assert_ne!(
        status.state, "unknown",
        "our own tx must be found by the scan"
    );

    // 7. Re-sync — Rust kept the pre-send UTXO set invalidated; the fresh
    //    discovery must succeed even while the spend is in the mempool.
    let sync2 = btc::btc_sync(20).expect("re-sync after send");
    println!(
        "[7] after spend: confirmed={} unconfirmed={} utxos={} used_addresses={}",
        sync2.confirmed_sat,
        sync2.unconfirmed_delta_sat,
        sync2.utxo_count,
        sync2.used_addresses.len()
    );

    // 8. History: the broadcast tx appears with computed amounts. After the
    //    re-sync both sides of the self-transfer are scanned, so the
    //    direction is "internal".
    let history = btc::btc_history().expect("history");
    let item = history
        .items
        .iter()
        .find(|i| i.txid == result.txid)
        .expect("broadcast tx in history");
    println!(
        "[8] history item: {} height={} received={} sent={} fee={:?}",
        item.direction, item.height, item.received_sat, item.sent_net_sat, item.fee_sat
    );

    // 9. Optional: block until the transfer is confirmed.
    if wait_secs > 0 {
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(wait_secs);
        println!("[9] polling for confirmation up to {wait_secs}s…");
        loop {
            let st = btc::btc_tx_status(result.txid.clone()).expect("poll status");
            if st.state == "confirmed" {
                println!(
                    "[9] confirmed at height {:?} (+{} conf)",
                    st.height,
                    st.confirmations.unwrap_or(0)
                );
                break;
            }
            if std::time::Instant::now() >= deadline {
                println!("[9] not confirmed within the budget (state {})", st.state);
                break;
            }
            std::thread::sleep(std::time::Duration::from_secs(30));
        }
    }

    // 10. Lock: the seed is wiped inside Rust, no session remains.
    btc::btc_lock().expect("btc_lock");
    println!("[10] session locked; live cycle complete");
}

#[test]
#[ignore = "live-network check of the faucet funding state (balance only)"]
fn check_funding_only() {
    if std::env::var("VEYRO_E2E").as_deref() != Ok("1") {
        panic!("safety gate: set VEYRO_E2E=1");
    }
    let phrase = std::env::var("VEYRO_E2E_PHRASE").expect("set VEYRO_E2E_PHRASE");
    let network_code = network_code();
    let server = std::env::var("VEYRO_E2E_SERVER")
        .unwrap_or_else(|_| default_server(network_code).to_string());

    let dir = tmp_dir();
    let created = wallet::restore_wallet(
        dir.clone(),
        "E2E".into(),
        "e2e password 123".into(),
        phrase,
        "".into(),
    )
    .expect("restore from phrase");
    let unlock = btc::btc_unlock(
        dir,
        created.id,
        "e2e password 123".into(),
        network_code,
        server,
    )
    .expect("btc_unlock");
    let sync = btc::btc_sync(20).expect("btc_sync");
    println!(
        "confirmed={} unconfirmed={} utxos={} next_receive={}",
        sync.confirmed_sat, sync.unconfirmed_delta_sat, sync.utxo_count, sync.next_receive.address
    );
    let _ = unlock;
    btc::btc_lock().unwrap();
}
