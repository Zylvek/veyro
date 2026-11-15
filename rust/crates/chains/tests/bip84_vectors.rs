//! Official BIP84 test vectors (https://github.com/bitcoin/bips/blob/master/
//! bip-0084.mediawiki, License CC0-1.0) — verbatim golden pins for the
//! key derivation layer. The BIP39 seed is computed from the documented
//! mnemonic via the audited `bip39` crate, so this file also pins seed
//! derivation end-to-end.

use bip39::Mnemonic;
use bitcoin::bip32::{ChildNumber, DerivationPath};
use bitcoin::secp256k1::{PublicKey as SecpPublicKey, Secp256k1, SecretKey};
use chains::bitcoin::keys::{derive_secret_key, AccountPubkeys, BRANCH_EXTERNAL, BRANCH_INTERNAL};
use chains::electrum::BtcNetwork;

/// BIP84 test vector mnemonic (12 words, "all abandon").
const MNEMONIC: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

fn vector_seed() -> [u8; 64] {
    let mnemonic = Mnemonic::parse_normalized(MNEMONIC).expect("BIP84 vector mnemonic is valid");
    mnemonic.to_seed_normalized("")
}

/// m/84'/0'/0'/0/0 — first receiving address.
const ADDR_0_0: &str = "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu";
/// m/84'/0'/0'/0/1 — second receiving address.
const ADDR_0_1: &str = "bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g";
/// m/84'/0'/0'/1/0 — first change address.
const ADDR_CHANGE_0: &str = "bc1q8c6fshw2dlwun7ekn9qwf37cu2rn755upcp6el";

const PUBKEY_0_0: &str = "0330d54fd0dd420a6e5f8d3624f5f3482cae350f79d5f0753bf5beef9c2d91af3c";
const PUBKEY_0_1: &str = "03e775fd51f0dfb8cd865d9ff1cca2a158cf651fe997fdc9fee9c1d3b5e995ea77";
const PUBKEY_CHANGE_0: &str = "03025324888e429ab8e3dbaf1f7802648b9cd01e9b418485c5fa4c1b9b5700e1a6";

fn mainnet_account() -> AccountPubkeys {
    AccountPubkeys::from_seed(&vector_seed(), BtcNetwork::Mainnet, 0).expect("derive account")
}

#[test]
fn bip84_addresses_match_official_vectors() {
    let account = mainnet_account();
    assert_eq!(
        account
            .derive_address(BRANCH_EXTERNAL, 0)
            .expect("derive")
            .address,
        ADDR_0_0
    );
    assert_eq!(
        account
            .derive_address(BRANCH_EXTERNAL, 1)
            .expect("derive")
            .address,
        ADDR_0_1
    );
    assert_eq!(
        account
            .derive_address(BRANCH_INTERNAL, 0)
            .expect("derive")
            .address,
        ADDR_CHANGE_0
    );
}

#[test]
fn bip84_pubkeys_match_official_vectors() {
    let account = mainnet_account();
    let secp = Secp256k1::verification_only();
    let path_of = |branch: u32, index: u32| -> Result<DerivationPath, bitcoin::bip32::Error> {
        Ok([
            ChildNumber::from_normal_idx(branch)?,
            ChildNumber::from_normal_idx(index)?,
        ]
        .into_iter()
        .collect())
    };
    let pubkey_hex = |branch: u32, index: u32| -> String {
        let xpub = account.account_xpub();
        let child = xpub
            .derive_pub(&secp, &path_of(branch, index).unwrap())
            .unwrap();
        hex::encode(child.public_key.serialize())
    };
    assert_eq!(pubkey_hex(BRANCH_EXTERNAL, 0), PUBKEY_0_0);
    assert_eq!(pubkey_hex(BRANCH_EXTERNAL, 1), PUBKEY_0_1);
    assert_eq!(pubkey_hex(BRANCH_INTERNAL, 0), PUBKEY_CHANGE_0);
}

#[test]
fn derive_secret_key_reproduces_vector_pubkey() {
    // The seed-to-pubkey path must reproduce the BIP84 pubkey for m/84'/0'/0'/0/0.
    let sk = derive_secret_key(&vector_seed(), BtcNetwork::Mainnet, 0, BRANCH_EXTERNAL, 0)
        .expect("derive secret");
    let secret = SecretKey::from_slice(sk.as_ref()).expect("32-byte key");
    let secp = Secp256k1::signing_only();
    let pk = SecpPublicKey::from_secret_key(&secp, &secret);
    assert_eq!(hex::encode(pk.serialize()), PUBKEY_0_0);
    assert_eq!(hex::encode(pk.serialize()), PUBKEY_0_0); // determinism
}

#[test]
fn derived_script_pubkey_matches_address_payload() {
    // golden = the official bech32 address (it encodes the full key hash);
    // the script is checked structurally + via the bech32 round trip.
    let account = mainnet_account();
    let da = account.derive_address(BRANCH_EXTERNAL, 0).expect("derive");
    let spk = da.script_pubkey.as_bytes();
    assert_eq!(spk.len(), 22, "P2WPKH spk = OP_0 PUSH20 <20B>");
    assert_eq!(&spk[..2], &[0x00, 0x14]);
    assert_eq!(da.path, "m/84'/0'/0'/0/0");
    // bech32 round trip: parsing the vector address must yield the same spk
    let parsed: bitcoin::Address<bitcoin::address::NetworkUnchecked> =
        ADDR_0_0.parse().expect("vector address parses");
    let checked = parsed
        .require_network(bitcoin::Network::Bitcoin)
        .expect("mainnet address");
    assert_eq!(checked.script_pubkey(), da.script_pubkey);
}

#[test]
fn testnet_uses_coin_type_one_and_tb_prefix() {
    // m/84'/1'/0'/0/0 — testnet derivation differs from mainnet (coin 1).
    let account = AccountPubkeys::from_seed(&vector_seed(), BtcNetwork::Testnet, 0)
        .expect("derive testnet account");
    let da = account.derive_address(BRANCH_EXTERNAL, 0).expect("derive");
    assert!(da.address.starts_with("tb1q"), "got {}", da.address);
    assert_eq!(da.path, "m/84'/1'/0'/0/0");
    // It must NOT equal the mainnet vector address for the same index.
    assert_ne!(da.address, ADDR_0_0);

    // Testnet4 shares coin type 1 and the tb1 prefix (BIP84: coin 1 = any
    // testnet; BIP173: HRP "tb" for testnets).
    let acct4 = AccountPubkeys::from_seed(&vector_seed(), BtcNetwork::Testnet4, 0)
        .expect("derive testnet4 account");
    let da4 = acct4.derive_address(BRANCH_EXTERNAL, 0).expect("derive");
    assert_eq!(da.address, da4.address, "coin type drives derivation");
}

#[test]
fn invalid_branch_rejected() {
    let account = mainnet_account();
    let r = account.derive_address(2, 0);
    assert!(r.is_err(), "branch 2 must be rejected");
    let s = derive_secret_key(&vector_seed(), BtcNetwork::Mainnet, 0, 7, 0);
    assert!(s.is_err(), "branch 7 secret derivation must be rejected");
}
