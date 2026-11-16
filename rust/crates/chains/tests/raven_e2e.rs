//! Gated live probe for the RVN adapter on TESTNET7 (NOT run in normal
//! test runs):
//!   cargo test -p chains --test raven_e2e -- --ignored --nocapture
//!
//! Docs/coins/RVN.md: testnet7 genesis
//! 000000ecfc5e6324a079542221d00e10362bdc894d56500c414060eea8a3ad5a,
//! official Electrum-RVN servers (servers_testnet.json: rvn4lyfe.com
//! TLS 50012).
//!
//! Phase 1 (`rvn_testnet_connect_and_derive`): connect + genesis check +
//! tip sanity + derive — оператор пополняет печатный адрес (фаусет или
//! ручной перевод testnet RVN).
//!
//! Phase 2 (`rvn_testnet_full_cycle`): скан → баланс/история →
//! self-transfer план → legacy SIGHASH_ALL подпись → идемпотентный
//! broadcast → mempool → ≥1 подтверждение. Полный честный цикл на
//! одноразовой фразе без касания mainnet-средств.

use bip39::Mnemonic;

use chains::bitcoin::scan::{collect_utxos, discover, history_with_amounts, wallet_balance};
use chains::bitcoin::tx::{estimate_fee_rates_with_fallback, idempotent_broadcast};
use chains::electrum::Gateway;
use chains::raven::{
    rvn_plan_transfer_on, rvn_signed_transfer, RvnAccount, RvnGateway, RvnNetwork,
};

const MAINNET_SERVER: &str = "ssl://rvn4lyfe.com:50002";
const MAINNET_SERVER_FALLBACK: &str = "ssl://162.19.153.65:50002";

const TESTNET_SERVER: &str = "ssl://rvn4lyfe.com:50012";
const TESTNET_SERVER_FALLBACK: &str = "ssl://testnet.rvn.rocks:50002";

/// Disposable standard BIP39 phrase (public test vector — never funded on
/// mainnet; testnet coins arrive here only from a faucet/manual deposit).
fn disposable_seed() -> [u8; 64] {
    let mut words: Vec<&str> = vec!["abandon"; 11];
    words.push("about");
    let mnemonic = Mnemonic::parse_normalized(&words.join(" ")).expect("valid test phrase");
    let seed64 = mnemonic.to_seed_normalized("");
    let seed: &[u8; 64] = seed64.as_slice().try_into().expect("64-byte seed");
    *seed
}

fn connect_first_available() -> RvnGateway {
    for url in [TESTNET_SERVER, TESTNET_SERVER_FALLBACK] {
        match RvnGateway::connect(url) {
            Ok(g) => return g,
            Err(e) => println!("{url}: connect failed ({e}) — next candidate"),
        }
    }
    panic!("no live Electrum-RVN testnet candidate");
}

fn account() -> RvnAccount {
    let seed = disposable_seed();
    RvnAccount::from_seed(&seed, RvnNetwork::Testnet7, 0).expect("account derivation m/44'/1'")
}

fn find_height(gateway: &RvnGateway, scripts: &[Vec<u8>], txid: &::bitcoin::Txid) -> i64 {
    scripts
        .iter()
        .filter_map(|s| gateway.script_history(s).ok())
        .flatten()
        .find(|e| &e.txid == txid)
        .map(|e| e.height)
        .unwrap_or(-1)
}

// ---------------------------------------------------------------------------
// Фаза 1: идентичность + коннект + деривация (пополнение после печати).
// ---------------------------------------------------------------------------

/// Фаза 0: честный mainnet-проб (профиль LTC receive-only milestone):
/// живой TLS-транспорт, genesis mainnet бит-в-бит, tip, деривация
/// m/44'/175', gap-скан по одноразовой фразе (пусто по построению —
/// проверяется транспорт/деривация/протокол, а не чужие средства).
#[test]
#[ignore = "live mainnet probe: run with -- --ignored --nocapture"]
fn rvn_mainnet_empty_probe() {
    let gateway = match RvnGateway::connect(MAINNET_SERVER) {
        Ok(g) => g,
        Err(e) => {
            println!("{MAINNET_SERVER}: {e} — пробуем fallback");
            RvnGateway::connect(MAINNET_SERVER_FALLBACK).expect("mainnet fallback connect")
        }
    };
    let (version, pmin, pmax, genesis) = gateway.server_features().expect("features");
    let genesis_hex = hex::encode(genesis);
    assert_eq!(
        genesis_hex,
        hex::encode(RvnNetwork::Mainnet.genesis_hash()),
        "server genesis mismatch — refusing (fund-safety)"
    );
    let tip = gateway.tip_height().expect("tip");
    assert!(tip > 1_000_000, "RVN mainnet tip far past 1M, got {tip}");
    println!("OK {version} protocol={pmin}..{pmax} tip={tip} genesis={genesis_hex}");
    gateway
        .verify_network(RvnNetwork::Mainnet)
        .expect("verify_network mainnet");

    let (rates, fallback) = estimate_fee_rates_with_fallback(&gateway).expect("fees");
    println!(
        "fees: fast={} normal={} slow={} sat/vb (fallback={fallback})",
        rates.fast_sat_vb, rates.normal_sat_vb, rates.slow_sat_vb,
    );

    let seed = disposable_seed();
    let account =
        RvnAccount::from_seed(&seed, RvnNetwork::Mainnet, 0).expect("derivation m/44'/175'");
    let first = account.derive_address(0, 0).expect("first address");
    assert!(first.address.starts_with('R'), "{}", first.address);
    println!("first address: {} ({})", first.address, first.path);

    let discovery = discover(&gateway, &account, 5).expect("discover");
    let slots = discovery.slots().count();
    println!("discovered {slots} slots (gap 5)");
    let balance = wallet_balance(&gateway, &discovery).expect("balance");
    println!(
        "balance: confirmed={} unconfirmed_delta={} (одноразовая фраза — пусто по построению)",
        balance.confirmed_sat, balance.unconfirmed_delta_sat
    );
    println!("RVN mainnet probe complete");
}

#[test]
#[ignore = "live testnet7 test: run with -- --ignored --nocapture"]
fn rvn_testnet_connect_and_derive() {
    let gateway = connect_first_available();

    // Fund-safety: сервер обязан отдать genesis testnet7 бит-в-бит.
    let (version, pmin, pmax, genesis) = gateway.server_features().expect("server_features");
    let genesis_hex = hex::encode(genesis);
    assert_eq!(
        genesis_hex,
        hex::encode(RvnNetwork::Testnet7.genesis_hash()),
        "server genesis mismatch — refusing (fund-safety)"
    );
    let tip = gateway.tip_height().expect("tip_height");
    assert!(tip > 1000, "testnet7 tip past genesis, got {tip}");
    println!("OK {version} protocol={pmin}..{pmax} tip={tip} genesis={genesis_hex}");

    let (rates, fallback) = estimate_fee_rates_with_fallback(&gateway).expect("fee rates");
    println!(
        "fees: fast={} normal={} slow={} sat/vb (fallback={fallback})",
        rates.fast_sat_vb, rates.normal_sat_vb, rates.slow_sat_vb,
    );

    let account = account();
    let first = account.derive_address(0, 0).expect("first address");
    assert!(first.address.starts_with('r'), "{}", first.address);
    println!("first address: {} ({})", first.address, first.path);
    let target = account.derive_address(0, 2).expect("address idx2");
    println!("self-send target: {} ({})", target.address, target.path);

    let discovery = discover(&gateway, &account, 5).expect("discover");
    let slots = discovery.slots().count();
    println!("discovered {slots} slots (gap 5)");
    let balance = wallet_balance(&gateway, &discovery).expect("wallet_balance");
    println!(
        "balance: confirmed={} unconfirmed_delta={}",
        balance.confirmed_sat, balance.unconfirmed_delta_sat
    );
    println!("phase 1 complete — fund the first address (≥1 блок подтверждения), затем фаза 2");
}

// ---------------------------------------------------------------------------
// Фаза 2: полный честный цикл.
// ---------------------------------------------------------------------------

#[test]
#[ignore = "live testnet7 test: run with -- --ignored --nocapture (faucet-funded)"]
fn rvn_testnet_full_cycle() {
    let seed = disposable_seed();
    let gateway = connect_first_available();
    gateway
        .verify_network(RvnNetwork::Testnet7)
        .expect("genesis check");
    let account = account();
    let first = account.derive_address(0, 0).expect("first address");
    println!("first address: {}", first.address);

    // 1) Скан + UTXO + баланс.
    let discovery = discover(&gateway, &account, 5).expect("discover");
    let utxos = collect_utxos(&gateway, &discovery).expect("collect_utxos");
    let balance = wallet_balance(&gateway, &discovery).expect("wallet_balance");
    println!(
        "utxos={} balance: confirmed={} unconfirmed_delta={}",
        utxos.len(),
        balance.confirmed_sat,
        balance.unconfirmed_delta_sat
    );
    assert!(
        balance.confirmed_sat > 0,
        "нет подтверждённого баланса — пополни {} и подожди ≥1 блок",
        first.address
    );
    assert!(!utxos.is_empty());

    // 2) История с суммами/направлениями (входящий депозит).
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
        "в истории нет входящего депозита"
    );

    // 3) Self-send: получатель = свой внешний индекс 2.
    let recipient = account.derive_address(0, 2).expect("recipient address");
    println!(
        "self-send recipient: {} ({})",
        recipient.address, recipient.path
    );

    let (rates, fallback) = estimate_fee_rates_with_fallback(&gateway).expect("fee rates");
    let rate = rates.normal_sat_vb.max(1);
    println!("send rate: {rate} sat/vb (fallback={fallback})");

    let headroom = rate.saturating_mul(400);
    let amount = balance.confirmed_sat.saturating_sub(headroom);
    assert!(amount > 546, "баланс мал для dust-safe отправки: {amount}");

    let change_index = discovery.internal.next_index();
    let change = account
        .derive_address(1, change_index)
        .expect("change address");

    let plan = rvn_plan_transfer_on(
        RvnNetwork::Testnet7,
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
    assert_eq!(plan.recipient, recipient.address);
    assert!(plan.recipient_amount_sat > 0);
    assert!(plan.fee_sat > 0);
    assert!(plan.recipient_amount_sat + plan.fee_sat <= balance.confirmed_sat);

    // 4) Локальная подпись legacy SIGHASH_ALL (без forkid).
    let tip_height = gateway.tip_height().expect("tip");
    let signed =
        rvn_signed_transfer(&plan, &seed, RvnNetwork::Testnet7, 0, tip_height).expect("sign");
    let txid_str = signed.txid.to_string();
    println!(
        "signed: txid={txid_str} raw_len={} bytes",
        signed.raw_hex.len() / 2
    );

    // 5) Идемпотентный broadcast.
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

    // 6) Статус: mempool, затем ≥1 подтверждение (testnet7 — 1 мин/блок).
    let scripts: Vec<Vec<u8>> = discovery.slots().map(|s| s.script_pubkey.clone()).collect();
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(1500);
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
        "транзакция не подтвердилась за дедлайн — explorer: https://ravencoin.network/tx/{txid_str}"
    );
    println!("phase 2 complete — полный живой цикл на Ravencoin testnet7: коннект → скан → история → план → подпись (legacy) → broadcast → подтверждение");
    println!("explorer: https://ravencoin.network/tx/{txid_str}");
}
