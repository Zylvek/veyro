//! Gated live probe for the XEC (eCash) adapter on TESTNET3 (NOT run in
//! normal test runs):
//!   cargo test -p chains --test xec_e2e -- --ignored --nocapture
//!
//! Docs/coins/XEC.md §2: testnet3 genesis == BTC testnet3 genesis,
//! cashaddr prefix `ectest`, official Electrum ABC testnet server
//! (servers_testnet.json: telectrum.bitcoinabc.org, TLS 60002).
//!
//! Phase 1 (`xec_testnet_connect_and_derive`): connect + genesis check +
//! tip sanity + derive the first address; the operator claims the faucet
//! (https://texplorer.e.cash/testnet-faucet) and waits ≥1 confirmation.
//!
//! Phase 2 (`xec_testnet_full_cycle`): scan → balance/history →
//! self-transfer plan → UAHF forkid sign → idempotent broadcast → wait
//! ≥1 confirmation. Full honest cycle on a disposable phrase WITHOUT
//! touching mainnet funds.

use bip39::Mnemonic;

use ::bitcoin::Txid;

use chains::bitcoin::scan::{collect_utxos, discover, history_with_amounts, wallet_balance};
use chains::bitcoin::tx::{estimate_fee_rates_with_fallback, idempotent_broadcast};
use chains::electrum::Gateway;
use chains::xec::{xec_plan_transfer_on, xec_signed_transfer, XecAccount, XecGateway, XecNetwork};

const TESTNET_SERVER: &str = "ssl://telectrum.bitcoinabc.org:60002";

/// Disposable standard BIP39 phrase (public test vector — never funded on
/// mainnet; coins arrive here only from the official testnet faucet).
fn disposable_seed() -> [u8; 64] {
    let mut words: Vec<&str> = vec!["abandon"; 11];
    words.push("about");
    let mnemonic = Mnemonic::parse_normalized(&words.join(" ")).expect("valid test phrase");
    let seed64 = mnemonic.to_seed_normalized("");
    let seed: &[u8; 64] = seed64.as_slice().try_into().expect("64-byte seed");
    *seed
}

fn connect_testnet() -> XecGateway {
    println!("connecting to {TESTNET_SERVER} …");
    XecGateway::connect(TESTNET_SERVER).expect("connect (handshake with backoff)")
}

fn account() -> XecAccount {
    let seed = disposable_seed();
    XecAccount::from_seed(&seed, XecNetwork::Testnet3, 0).expect("account derivation m/44'/1'")
}

/// Poll the discovered scripts for the txid and report its height
/// (`-1` = not seen by the Electrum backend; `0` = mempool).
fn find_height(gateway: &XecGateway, scripts: &[Vec<u8>], txid: &Txid) -> i64 {
    scripts
        .iter()
        .filter_map(|s| gateway.script_history(s).ok())
        .flatten()
        .find(|e| &e.txid == txid)
        .map(|e| e.height)
        .unwrap_or(-1)
}

// ---------------------------------------------------------------------------
// Phase 1: identity + connectivity + derive (operator funds after printing).
// ---------------------------------------------------------------------------

#[test]
#[ignore = "live testnet3 test: run with -- --ignored --nocapture"]
fn xec_testnet_connect_and_derive() {
    let gateway = connect_testnet();

    // Identity: the server must serve the eCash TESTNET3 genesis bit-for-bit.
    let (version, pmin, pmax, genesis) = gateway.server_features().expect("server_features");
    let genesis_hex = hex::encode(genesis);
    let expected = XecNetwork::Testnet3.genesis_hash();
    assert_eq!(
        genesis_hex,
        hex::encode(expected),
        "server genesis mismatch — refusing (fund-safety)"
    );
    let tip = gateway.tip_height().expect("tip_height");
    assert!(tip > 1000, "testnet3 tip must be past genesis, got {tip}");
    println!("OK {version} protocol={pmin}..{pmax} tip={tip} genesis={genesis_hex}");

    // Fee endpoint sanity (empty testnet mempool → honest fallback).
    let (rates, fallback) = estimate_fee_rates_with_fallback(&gateway).expect("fee rates");
    println!(
        "fees: fast={} normal={} slow={} sat/vbyte (fallback={fallback})",
        rates.fast_sat_vb, rates.normal_sat_vb, rates.slow_sat_vb,
    );

    // Derivation: testnet coin type 1 (BIP44), prefix `ectest`.
    let account = account();
    let first = account.derive_address(0, 0).expect("first address");
    assert!(first.address.starts_with("ectest:q"), "{}", first.address);
    println!("first address: {} ({})", first.address, first.path);

    let target = account.derive_address(0, 1).expect("address idx1");
    println!("self-send target: {} ({})", target.address, target.path);
    let target2 = account.derive_address(0, 2).expect("address idx2");
    println!("self-send target 2: {} ({})", target2.address, target2.path);

    // Empty-by-design scan pipeline on a fresh account.
    let discovery = discover(&gateway, &account, 5).expect("discover");
    let slots = discovery.slots().count();
    println!("discovered {slots} slots (gap 5)");
    let balance = wallet_balance(&gateway, &discovery).expect("wallet_balance");
    println!(
        "balance: confirmed={} sat unconfirmed_delta={} sat",
        balance.confirmed_sat, balance.unconfirmed_delta_sat
    );
    println!("phase 1 complete — claim the faucet for the first address, wait ≥1 confirmation, then run phase 2");
}

// ---------------------------------------------------------------------------
// Phase 2: full honest cycle: scan → history → plan → sign → broadcast →
// ≥1 confirmation.
// ---------------------------------------------------------------------------

#[test]
#[ignore = "live testnet3 test: run with -- --ignored --nocapture (faucet-funded)"]
fn xec_testnet_full_cycle() {
    let seed = disposable_seed();
    let gateway = connect_testnet();
    gateway
        .verify_network(XecNetwork::Testnet3)
        .expect("genesis check");
    let account = account();
    let first = account.derive_address(0, 0).expect("first address");
    println!("first address: {}", first.address);

    // 1) Scan: gap-limited discovery + UTXO collection + balance.
    let discovery = discover(&gateway, &account, 5).expect("discover");
    let utxos = collect_utxos(&gateway, &discovery).expect("collect_utxos");
    let balance = wallet_balance(&gateway, &discovery).expect("wallet_balance");
    println!(
        "utxos={} balance: confirmed={} sat unconfirmed_delta={} sat",
        utxos.len(),
        balance.confirmed_sat,
        balance.unconfirmed_delta_sat
    );
    assert!(
        balance.confirmed_sat > 0,
        "no confirmed balance — claim the faucet for {} and wait ≥1 confirmation",
        first.address
    );
    assert!(!utxos.is_empty(), "balance confirmed but no UTXO collected");

    // 2) History with amounts and directions (the faucet incoming payment).
    let resolution = history_with_amounts(&gateway, &discovery).expect("history_with_amounts");
    for item in &resolution.items {
        println!(
            "history: {} height={} dir={:?} received={} sent_net={}",
            item.txid, item.height, item.direction, item.received_sat, item.sent_net_sat
        );
    }
    assert!(
        resolution.items.iter().any(|i| matches!(
            i.direction,
            Some(chains::bitcoin::scan::HistoryDirection::Incoming)
        )),
        "expected the faucet incoming payment in history"
    );

    // 3) Self-send: recipient = own external index 2 (first address keeps
    //    its UTXO shape; target idx 2 = clean recipient), change = internal
    //    next index. Amount: full balance minus a generous fee headroom —
    //    the plan absorbs sub-dust leftovers into the fee.
    let recipient = account.derive_address(0, 2).expect("recipient address");
    println!(
        "self-send recipient: {} ({})",
        recipient.address, recipient.path
    );

    let (rates, fallback) = estimate_fee_rates_with_fallback(&gateway).expect("fee rates");
    let rate = rates.normal_sat_vb.max(1);
    println!("send rate: {rate} sat/vbyte (fallback={fallback})");

    let headroom = rate.saturating_mul(400); // ≥ real 1-in-2 P2PKH size
    let amount = balance.confirmed_sat.saturating_sub(headroom);
    assert!(
        amount > 546,
        "confirmed balance too small for a dust-safe spend: {amount} sat"
    );

    let change_index = discovery.internal.next_index();
    let change = account
        .derive_address(1, change_index)
        .expect("change address");

    let plan = xec_plan_transfer_on(
        XecNetwork::Testnet3,
        &recipient.address,
        amount,
        rate,
        &utxos,
        &change,
    )
    .expect("plan");
    println!(
        "plan: recipient_amount={} fee={} vsize={} inputs={} change={:?}",
        plan.recipient_amount_sat,
        plan.fee_sat,
        plan.vsize,
        plan.inputs.len(),
        plan.change.as_ref().map(|c| c.2)
    );
    assert_eq!(plan.recipient, recipient.address, "recipient must match");
    assert!(plan.recipient_amount_sat > 0, "amount must be positive");
    assert!(plan.fee_sat > 0, "fee must be positive");
    assert!(
        plan.recipient_amount_sat + plan.fee_sat <= balance.confirmed_sat,
        "plan spends more than the confirmed balance"
    );

    // 4) Sign with the UAHF forkid digest path.
    let tip_height = gateway.tip_height().expect("tip");
    let signed =
        xec_signed_transfer(&plan, &seed, XecNetwork::Testnet3, 0, tip_height).expect("sign");
    let txid_str = signed.txid.to_string();
    println!(
        "signed: txid={txid_str} raw_len={} bytes",
        signed.raw_hex.len() / 2
    );

    // 5) Idempotent broadcast (Sent or AlreadyKnown both mean acceptance).
    match idempotent_broadcast(&gateway, &signed).expect("broadcast") {
        chains::BroadcastOutcome::Sent(txid) => {
            assert_eq!(txid.to_string(), txid_str);
            println!("broadcast: Sent ({txid})");
        }
        chains::BroadcastOutcome::AlreadyKnown(txid) => {
            assert_eq!(txid.to_string(), txid_str);
            println!("broadcast: AlreadyKnown ({txid})");
        }
    }

    // 6) Status: wait for ≥1 confirmation across all discovered scripts.
    let scripts: Vec<Vec<u8>> = discovery.slots().map(|s| s.script_pubkey.clone()).collect();
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(1200);
    let mut confirmed = false;
    while std::time::Instant::now() < deadline {
        let height = find_height(&gateway, &scripts, &signed.txid);
        println!("status: history_height={height}");
        if height >= 1 {
            confirmed = true;
            break;
        }
        std::thread::sleep(std::time::Duration::from_secs(30));
    }
    assert!(
        confirmed,
        "tx was not confirmed within the deadline — check explorer: https://texplorer.e.cash/tx/{txid_str}"
    );
    println!(
        "phase 2 complete — full live cycle on eCash testnet3: connect → scan → history → plan → sign (UAHF forkid) → broadcast → confirmed"
    );
    println!("explorer: https://texplorer.e.cash/tx/{txid_str}");
}
