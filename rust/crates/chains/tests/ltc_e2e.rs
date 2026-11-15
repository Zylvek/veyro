//! Gated live probe for the LTC adapter (NOT run in normal test runs):
//!   cargo test -p chains --test ltc_e2e -- --ignored --nocapture
//!
//! Verifies against a real Electrum-LTC server (docs/coins/LTC.md §5):
//! 1. connect (handshake with backoff) + server identity via genesis check,
//! 2. tip height sanity (mainnet LTC is far past 1M blocks),
//! 3. full scan pipeline over a disposable standard BIP39 phrase
//!    ("abandon…about"): derive → gap-limit discover → balance query.
//!    The empty result is EXPECTED: this tests protocol + derivation, not
//!    someone's funds.

use bip39::Mnemonic;

use chains::bitcoin::scan::{discover, wallet_balance};
use chains::electrum::Gateway;
use chains::litecoin::{LtcAccount, LtcGateway, GENESIS_MAINNET_HEX, SERVERS_MAINNET};

#[test]
#[ignore = "live network test: run with -- --ignored --nocapture"]
fn ltc_live_end_to_end() {
    let server =
        std::env::var("VEYRO_LTC_E2E_SERVER").unwrap_or_else(|_| SERVERS_MAINNET[0].to_string());
    println!("connecting to {server} …");
    let gateway = LtcGateway::connect(&server).expect("connect (handshake with backoff)");

    // Identity: the server must serve the LTC mainnet genesis, bit for bit.
    let (version, pmin, pmax, genesis) = gateway.server_features().expect("server_features");
    let genesis_hex = hex::encode(genesis);
    assert_eq!(
        genesis_hex, GENESIS_MAINNET_HEX,
        "server genesis mismatch — refusing (fund-safety)"
    );
    let tip = gateway.tip_height().expect("tip_height");
    assert!(
        tip > 1_000_000,
        "LTC mainnet tip is far past 1M blocks, got {tip}"
    );
    println!("OK {version} protocol={pmin}..{pmax} tip={tip} genesis={genesis_hex}");

    // Disposable standard phrase (public test vector — no funds on it).
    let mut words: Vec<&str> = vec!["abandon"; 11];
    words.push("about");
    let phrase = words.join(" ");
    let mnemonic = Mnemonic::parse_normalized(&phrase).expect("valid test phrase");
    let seed64 = mnemonic.to_seed_normalized("");
    let seed: &[u8; 64] = seed64.as_slice().try_into().unwrap();
    let account = LtcAccount::from_seed(seed, 0).expect("account derivation");
    let first = account.derive_address(0, 0).expect("first address");
    println!("first address: {} ({})", first.address, first.path);

    // Full scan pipeline: gap-limited discovery on both branches.
    let discovery = discover(&gateway, &account, 2).expect("discover");
    let n_slots = discovery.external.slots.len() + discovery.internal.slots.len();
    println!("discovered {n_slots} slots (gap 2, external+internal)");
    let balance = wallet_balance(&gateway, &discovery).expect("wallet_balance");
    println!(
        "balance: confirmed={} lits unconfirmed_delta={} lits",
        balance.confirmed_sat, balance.unconfirmed_delta_sat
    );
    println!("LTC live probe complete");
}
