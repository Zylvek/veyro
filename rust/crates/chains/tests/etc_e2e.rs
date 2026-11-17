//! Gated live probe for the ETC adapter on MORDOR testnet (NOT run in
//! normal test runs):
//!   cargo test -p chains --test etc_e2e -- --ignored --nocapture
//!
//! Паспорт docs/coins/ETC.md: Mordor, chainId 63, genesis
//! 0xa68ebde7932eccb177d38d55dcc6461a019dd795a681e59b5a3e4f3a7259a3f1,
//! RPC https://rpc.mordor.etccooperative.org (проверен 11.11.2026).
//! Фаусет: https://faucet.etcmc-monitor.org (PoW-mining; адрес ниже).
//!
//! Phase 1 (`etc_mordor_connect_and_derive`): connect + chainId/genesis
//! проверка + tip + деривация m/44'/61'/0'/0/0 — печатающий адрес для
//! фаусета. Баланс честно «0 пока не пополнят» (без выдумок).
//!
//! Phase 2 (`etc_mordor_full_cycle`): запускать ПОСЛЕ пополнения адреса:
//! баланс → nonce → self-transfer ~90% (остальное — газ) → подпись
//! EIP-155 → eth_sendRawTransaction → in_mempool → receipt → подтверждение.
//! Одноразовая фраза из ПУБЛИЧНОГО BIP39-вектора: mainnet никогда не
//! пополнится (адрес известен), Mordor-монеты — добровольный фаусет.

use bip39::Mnemonic;

use chains::etc::{
    EtcAccount, EtcGateway, EtcNetwork, LegacyTxIntent, MORDOR_GENESIS_HEX, TRANSFER_GAS,
};

/// Публичный тест-вектор BIP39 (никогда не основной кошелёк).
fn disposable_seed() -> [u8; 64] {
    let mut words: Vec<&str> = vec!["abandon"; 11];
    words.push("about");
    let mnemonic = Mnemonic::parse_normalized(&words.join(" ")).expect("valid test phrase");
    mnemonic
        .to_seed_normalized("")
        .to_vec()
        .try_into()
        .expect("64-byte seed")
}

fn mordor_gateway() -> EtcGateway {
    EtcGateway::connect("https://rpc.mordor.etccooperative.org", EtcNetwork::Mordor)
        .expect("mordor gateway (chainId 63 + genesis)")
}

#[test]
#[ignore = "live: cargo test -p chains --test etc_e2e phase1 -- --ignored --nocapture"]
fn etc_mordor_connect_and_derive() {
    let gateway = mordor_gateway();
    let tip = gateway.block_number().expect("height");
    let acc = EtcAccount::from_seed(&disposable_seed(), EtcNetwork::Mordor, 0).expect("account");
    let addr = acc.derive_address(0).expect("address");
    let balance = gateway.balance_wei(&addr.addr20, false).expect("balance");
    let nonce = gateway.nonce(&addr.addr20).expect("nonce");
    println!("mordor tip = {tip}");
    println!("ФАУСЕТ-АДРЕС (EIP-55): {}", addr.address);
    println!("path = {}", addr.path);
    println!("balance_wei = {balance}  (0 — честно, пока не пополнят)");
    println!("nonce = {nonce}");
    let _ = MORDOR_GENESIS_HEX;
}

#[test]
#[ignore = "live AFTER funding: cargo test -p chains --test etc_e2e full_cycle -- --ignored --nocapture"]
fn etc_mordor_full_cycle() {
    let gateway = mordor_gateway();
    let seed = disposable_seed();
    let acc = EtcAccount::from_seed(&seed, EtcNetwork::Mordor, 0).expect("account");
    let addr = acc.derive_address(0).expect("address");
    let (secret, from) =
        chains::etc::etc_secret_key(&seed, EtcNetwork::Mordor, 0, 0).expect("secret");
    println!("адрес: {} (from подписи: {from})", addr.address);

    // 1. Баланс/nonce — честный стартовый срез
    let balance = gateway.balance_wei(&addr.addr20, false).expect("balance");
    let pending = gateway.balance_wei(&addr.addr20, true).expect("pending");
    let nonce = gateway.nonce(&addr.addr20).expect("nonce");
    println!("step1: latest={balance} pending={pending} nonce={nonce}");
    assert!(balance > 0, "адрес не пополнен — сначала фаусет (phase 1)");
    assert!(pending >= balance, "pending ≥ latest (или без изменений)");

    // 2. Оценка газа от сервера: перевод 90% баланса себе
    let gas_price = gateway.gas_price_wei().expect("gasPrice");
    let send_amount = balance * 9 / 10;
    let intent = LegacyTxIntent {
        nonce,
        gas_price_wei: gas_price,
        gas_limit: TRANSFER_GAS,
        to: addr.addr20, // self-transfer: полный цикл за один фаусет-взнос
        value_wei: send_amount,
        data: Vec::new(),
    };
    let estimate = gateway
        .estimate_gas(&addr.addr20, &intent)
        .expect("estimateGas для пополненного адреса обязан работать");
    println!("step2: gasPrice={gas_price} estimateGas={estimate} send={send_amount} wei");
    assert!(estimate >= TRANSFER_GAS);

    // 3. Подпись EIP-155 (chainId 63) и broadcast
    let signed_intent = LegacyTxIntent {
        nonce,
        gas_price_wei: gas_price,
        gas_limit: estimate,
        to: addr.addr20,
        value_wei: send_amount,
        data: Vec::new(),
    };
    let (raw_hex, txhash, from_signed) =
        chains::etc::etc_sign_transfer(&secret, EtcNetwork::Mordor, signed_intent).expect("sign");
    assert_eq!(
        from_signed,
        addr.address.replace("0x", "").to_lowercase().to_string(),
        "from подписи должен совпадать с адресом аккаунта (0x-hex)"
    );
    println!("step3: txhash={txhash}");
    gateway.send_raw(&raw_hex).expect("broadcast");
    println!("step4: broadcast ok");

    // 4. Честный статус: mempool → receipt (поллинг ~90 сек, блок ~8-13 c)
    let mut confirmed_block: Option<u64> = None;
    for _ in 0..20 {
        std::thread::sleep(std::time::Duration::from_secs(5));
        match gateway.receipt(&txhash).expect("receipt query") {
            Some(r) => {
                assert!(
                    r.status_success,
                    "receipt есть, но не success — честный отказ"
                );
                confirmed_block = r.block_number;
                break;
            }
            None => {
                let in_pool = gateway.in_mempool(&txhash).expect("mempool query");
                println!("…receipt нет; in_mempool={in_pool}");
            }
        }
    }
    let block = confirmed_block.expect("транза обязана подтвердиться в ~90 c");
    println!("full cycle: ПОДТВЕРЖДЕНО в блоке {block} ✅");

    // 5. Баланс после: latest вернулся к ~balance (self-transfer, минус газ)
    let after = gateway
        .balance_wei(&addr.addr20, false)
        .expect("balance after");
    let fee_paid = balance + send_amount - after; // честная арифметика не сходится при self-send: баланс уменьшается на газ
    println!("step5: after={after} fee_paid≈{fee_paid} wei");
    assert!(after < balance, "газ обязан уменьшить баланс");
}
