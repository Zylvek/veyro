//! Gated probe for live Electrum servers (NOT run in CI):
//!   set VEYRO_E2E_SERVER=ssl://host:port  then run
//!   cargo test -p chains --test e2e_probe -- --ignored --nocapture
//!
//! Purpose: filter the candidate server list (docs/coins/BTC.md and public
//! sources) down to servers that (a) speak the Electrum protocol, (b) serve
//! the network their URL claims (genesis check), (c) are synced (tip height).

use bip39::Mnemonic;

use chains::bitcoin::keys::{AccountPubkeys, BRANCH_EXTERNAL};
use chains::electrum::{BtcNetwork, ElectrumGateway, Gateway};

/// Gated helper for the faucet step.
/// Empty VEYRO_E2E_PHRASE => generate + print a fresh phrase (write it down,
/// rerun with it). Non-empty => derive the first receive address:
///   cargo test -p chains --test e2e_probe derive_receive_address -- --ignored --nocapture
#[test]
#[ignore = "needs VEYRO_E2E_PHRASE (12/24 BIP39 words; empty = generate one)"]
fn derive_receive_address() {
    let network = BtcNetwork::Testnet; // адреса testnet (coin type 1)
    let phrase = std::env::var("VEYRO_E2E_PHRASE").unwrap_or_default();
    let phrase_string;
    let mnemonic = if phrase.trim().is_empty() {
        let generated =
            Mnemonic::generate(bip39::WordCount::Words12).expect("random mnemonic generation");
        phrase_string = generated.to_string();
        println!(
            "GENERATED PHRASE (write it down, it is printed once):\n{phrase_string}"
        );
        Mnemonic::parse_normalized(&phrase_string).expect("generated phrase is valid")
    } else {
        Mnemonic::parse_normalized(&phrase).expect("valid BIP39 phrase")
    };
    let seed = mnemonic.to_seed_normalized("");
    let account = AccountPubkeys::from_seed(&seed, network, 0).expect("account derivation");
    let address = account.derive_address(BRANCH_EXTERNAL, 0).expect("address");
    println!("TESTNET RECEIVE ADDRESS (m/84'/1'/0'/0/0): {}", address.address);
    println!("path: {}", address.path);
}

#[test]
#[ignore = "needs a live Electrum server: VEYRO_E2E_SERVER=... cargo test -- --ignored"]
fn probe_live_server() {
    let url = std::env::var("VEYRO_E2E_SERVER").expect("set VEYRO_E2E_SERVER");
    let network = match std::env::var("VEYRO_E2E_NETWORK")
        .unwrap_or_else(|_| "testnet".into())
        .as_str()
    {
        "mainnet" => BtcNetwork::Mainnet,
        "testnet4" => BtcNetwork::Testnet4,
        _ => BtcNetwork::Testnet,
    };
    println!("probing {url} for {}", network.display_name());

    let gateway = ElectrumGateway::connect(&url, network).expect("connect");
    let (version, pmin, pmax, genesis) = gateway.server_features().expect("server_features");
    let tip = gateway.tip_height().expect("tip_height");
    println!(
        "OK version={version} protocol={pmin}..{pmax} genesis={} tip={tip}",
        hex::encode(genesis)
    );
    println!("expected genesis={}", hex::encode(network.genesis_hash()));

    // Data sanity: a garbage script must return a zero balance, not an error.
    let garbage = [0u8; 32];
    if let Ok(balance) = gateway.script_balance(&garbage) {
        println!(
            "garbage-script balance: confirmed={} unconfirmed={}",
            balance.confirmed_sat, balance.unconfirmed_sat
        );
        assert_eq!(
            (balance.confirmed_sat, balance.unconfirmed_sat),
            (0, 0),
            "garbage script must have zero balance"
        );
    } else {
        println!("(garbage script errored — acceptable for a strict server)");
    }
}
