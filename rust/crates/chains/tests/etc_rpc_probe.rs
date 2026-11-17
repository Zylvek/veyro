//! Живой RPC-пробник ETC/Mordor (NOT run in normal test runs):
//!   cargo test -p chains --test etc_rpc_probe -- --ignored --nocapture
//!
//! Эндпоинты и параметры — из паспорта docs/coins/ETC.md (RPC-проверен
//! 11.11.2026): mainnet chainId 61, генезис d4e56740…; Mordor chainId 63,
//! генезис a68ebde7…. Проверки: https-only connect с чепухой-отклонением,
//! chainId + genesis, высота, баланс нулевого адреса, gasPrice, nonce,
//! estimateGas, BlockScout v2 REST, честные таймауты. Отправку транз
//! пробник НЕ делает (только после пополнения тестнет-адреса).

use chains::etc::{
    blockscout_history, EtcAccount, EtcGateway, EtcNetwork, LegacyTxIntent,
    ETC_MAINNET_GENESIS_HEX, MORDOR_GENESIS_HEX, TRANSFER_GAS,
};

fn gate(n: EtcNetwork, url: &str) {
    let gw =
        EtcGateway::connect(url, n).unwrap_or_else(|e| panic!("{url}: живого канала нет: {e}"));
    let height = gw.block_number().expect("height");
    let zero = [0u8; 20];
    let balance = gw.balance_wei(&zero, false).expect("balance");
    let gas = gw.gas_price_wei().expect("gasPrice");
    let seed: [u8; 64] = std::array::from_fn(|i| ((i * 7) % 251) as u8);
    let acc = EtcAccount::from_seed(&seed, n, 0).expect("account"); //Disposable seed (нефундированный)
    let addr = acc.derive_address(0).expect("addr");
    let nonce = gw.nonce(&addr.addr20).expect("nonce");
    println!(
        "{url}: height={height} zero-balance_wei={balance} gasPrice_wei={gas} nonce({addr:?})={nonce}",
    );

    // estimateGas нативного перевода 1 wei с несуществующего источника:
    // сервер либо оценит по шаблону, либо честно откажет — оба исхода валидны,
    // печатаем фактический.
    let intent = LegacyTxIntent {
        nonce: 0,
        gas_price_wei: gas,
        gas_limit: TRANSFER_GAS,
        to: [0u8; 20],
        value_wei: 1,
        data: Vec::new(),
    };
    match gw.estimate_gas(&addr.addr20, &intent) {
        Ok(g) => println!("{url}: estimateGas={g} (перевод)"),
        Err(e) => println!("{url}: estimateGas честно отказал: {e}"),
    }
}

#[test]
#[ignore = "live rpc probe: cargo test -p chains --test etc_rpc_probe mainnet -- --ignored --nocapture"]
fn etc_mainnet_rpc_probe() {
    // Сначала честные отклонения небезопасных входов:
    assert!(EtcGateway::connect("http://etc.etcdesktop.com", EtcNetwork::Mainnet).is_err());
    assert!(EtcGateway::connect("", EtcNetwork::Mainnet).is_err());
    // Живой mainnet (кандидаты из паспорта, порядок честный):
    for url in EtcNetwork::Mainnet.preset_servers() {
        match EtcGateway::connect(url, EtcNetwork::Mainnet) {
            Ok(_) => {
                gate(EtcNetwork::Mainnet, url);
                break;
            }
            Err(e) => println!("{url}: недоступен: {e}"),
        }
    }
    // BlockScout REST v2: истории нулевого адреса (может быть пустой — честно).
    match blockscout_history("https://etc.blockscout.com/api/v2", &[0u8; 20]) {
        Ok((items, total)) => println!(
            "blockscout v2: история нулевого адреса: {} из {} (проверен) ✅",
            items.len(),
            total
        ),
        Err(e) => println!("blockscout v2: недоступен: {e}"),
    }
    let _ = ETC_MAINNET_GENESIS_HEX;
}

#[test]
#[ignore = "live rpc probe: cargo test -p chains --test etc_rpc_probe mordor -- --ignored --nocapture"]
fn etc_mordor_rpc_probe() {
    let gw = EtcGateway::connect("https://rpc.mordor.etccooperative.org", EtcNetwork::Mordor)
        .expect("mordor gateway (chainId 63 + genesis a68ebde7…)");
    let height = gw.block_number().expect("height");
    let gas = gw.gas_price_wei().expect("gasPrice");
    println!("mordor: height={height} gasPrice_wei={gas} ✅ генезис сверён");
    let _ = MORDOR_GENESIS_HEX;
}
