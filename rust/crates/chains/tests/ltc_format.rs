//! LTC milestone tests: bech32 encoder (cross-checked against rust-bitcoin
//! and a live mainnet vector) and the LTC account shape.
//!
//! Run without network: `cargo test -p chains --test ltc_format`.

use chains::bitcoin::keys::AccountPubkeys;
use chains::electrum::BtcNetwork;
use chains::litecoin::{bech32_segwit_address, LtcAccount};

/// BIP173 bech32 charset (reverse map built from it).
const CHARSET: &[u8] = b"qpzry9x8gf2tvdw0s3jn54khce6mua7l";

/// Independent implementation of the BIP173 polymod (do not reuse our
/// encoder internals — this is the cross-check).
fn polymod(values: &[u8]) -> u32 {
    const GEN: [u32; 5] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
    let mut chk: u32 = 1;
    for &v in values {
        let b = (chk >> 25) as u8;
        chk = ((chk & 0x1ff_ffff) << 5) ^ (v as u32);
        for (i, g) in GEN.iter().enumerate() {
            if (b >> i) & 1 == 1 {
                chk ^= g;
            }
        }
    }
    chk
}

fn hrp_expand(hrp: &str) -> Vec<u8> {
    let mut e: Vec<u8> = hrp.bytes().map(|b| b >> 5).collect();
    e.push(0);
    e.extend(hrp.bytes().map(|b| b & 31));
    e
}

/// Independent checksum pass of any bech32 (v0 constant) address.
fn checksum_ok(address: &str, hrp: &str) -> bool {
    let lower = address.to_ascii_lowercase();
    let rest = match lower.strip_prefix(&format!("{hrp}1")) {
        Some(rest) => rest,
        None => return false,
    };
    let mut data: Vec<u8> = Vec::with_capacity(rest.len());
    for c in rest.bytes() {
        match CHARSET.iter().position(|&x| x as char == c as char) {
            Some(q) => data.push(q as u8),
            None => return false,
        }
    }
    let mut vals = hrp_expand(hrp);
    vals.extend_from_slice(&data);
    // BIP173: the whole string must checksum to exactly 1 (bech32 constant).
    polymod(&vals) == 1
}

/// Independent quint → program decode with a proper accumulator (the buggy
/// `chunks(5)` shortcut silently mis-sized programs — do not).
fn decode_version_and_program(address: &str, hrp: &str) -> (u8, Vec<u8>) {
    let lower = address.to_ascii_lowercase();
    assert_eq!(&lower[..hrp.len() + 1], &format!("{hrp}1"));
    let data: Vec<u8> = lower[hrp.len() + 1..]
        .bytes()
        .map(|c| {
            CHARSET
                .iter()
                .position(|&x| x as char == c as char)
                .unwrap() as u8
        })
        .collect();
    assert!(data.len() > 6, "version + program + 6 checksum chars");
    // BIP173 checksum of the whole string.
    let mut vals = hrp_expand(hrp);
    vals.extend_from_slice(&data);
    assert_eq!(polymod(&vals), 1, "input vector must be self-consistent");
    // Witness version is the first quint; the checksum quints are excluded.
    let version = data[0];
    let quints = &data[1..data.len() - 6];
    let mut program: Vec<u8> = Vec::new();
    let mut acc: u32 = 0;
    let mut bits: u32 = 0;
    for &q in quints {
        acc = (acc << 5) | ((q & 31) as u32);
        bits += 5;
        while bits >= 8 {
            bits -= 8;
            program.push(((acc >> bits) & 0xff) as u8);
        }
    }
    assert_eq!(bits % 8, 0, "no padding bits must remain");
    (version, program)
}

/// The canonical BIP173 vector (fixed by the spec, not by us): decode its
/// program with the independent decoder → re-encode must be the identity.
/// The strongest possible checksum probe for the encoder.
#[test]
fn bech32_reproduces_the_canonical_bip173_vector() {
    let canonical = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4";
    let (version, program) = decode_version_and_program(canonical, "bc");
    assert_eq!(version, 0);
    assert_eq!(program.len(), 20);
    assert_eq!(
        bech32_segwit_address("bc", &program).expect("our encoder"),
        canonical
    );
}

/// Bit-for-bit cross-check of the encoder against rust-bitcoin: the same
/// witness program rust-bitcoin produced for a BTC address fed through our
/// manual encoder must reconstruct the exact same string (encoder is
/// hrp-generic, so this validates the algorithm itself, HRP included).
#[test]
fn encoder_cross_checks_against_rust_bitcoin() {
    let seed = test_seed();
    let account = AccountPubkeys::from_seed(&seed, BtcNetwork::Mainnet, 0).expect("btc keys");
    let derived = account.derive_address(0, 0).expect("derive 0/0");
    let program = &derived.script_pubkey.as_bytes()[2..];

    let reencoded = bech32_segwit_address("bc", program).expect("our encoder");
    assert_eq!(reencoded, derived.address, "encoder == rust-bitcoin");
    assert!(checksum_ok(&reencoded, "bc"), "independent BIP173 checksum");
}

/// A known-good live LTC P2WPKH address from litecoinspace.org (pinned in
/// docs/coins/LTC.md, 11.11.2026): independent decode → re-encode must be
/// the identity.
#[test]
fn bech32_ltc_roundtrips_the_live_vector() {
    let addr = "ltc1qhw6ntumfxtmz7jek9vukdh53gj40u9arcclp85";
    assert!(checksum_ok(addr, "ltc"), "live vector checksum");
    let (version, program) = decode_version_and_program(addr, "ltc");
    assert_eq!(version, 0, "p2wpkh witness version");
    assert_eq!(program.len(), 20, "p2wpkh program length");

    let reencoded = bech32_segwit_address("ltc", &program).expect("our encoder");
    assert_eq!(reencoded, addr, "round trip must be the identity");
}

/// Derivation shape: ltc1 prefix, path text m/84'/2'/0', P2WPKH script
/// (OP_0 push-20), electrum scripthash, valid BIP173 checksum.
#[test]
fn ltc_account_derivation_shape() {
    let seed = test_seed();
    let account = LtcAccount::from_seed(&seed, 0).expect("ltc derivation");
    let derived = account.derive_address(0, 0).expect("derive 0/0");

    assert!(derived.address.starts_with("ltc1q"), "bech32 HRP ltc");
    assert!(derived.path.contains("m/84'/2'/0'"), "path text");
    assert_eq!(derived.script_pubkey.as_bytes()[0], 0x00, "p2wpkh version");
    assert_eq!(derived.script_pubkey.as_bytes()[1], 0x14, "push 20");
    assert_eq!(derived.script_pubkey.as_bytes().len(), 22, "p2wpkh script");
    assert_eq!(derived.scripthash_hex.len(), 64, "electrum scripthash");
    assert!(checksum_ok(&derived.address, "ltc"), "our own checksum");
}

/// Same address derivation twice → identical output (determinism of the
/// account object).
#[test]
fn ltc_derivation_is_deterministic() {
    let seed = test_seed();
    let a = LtcAccount::from_seed(&seed, 0)
        .expect("account")
        .derive_address(0, 3)
        .expect("0/3");
    let b = LtcAccount::from_seed(&seed, 0)
        .expect("account")
        .derive_address(0, 3)
        .expect("0/3");
    assert_eq!(a.address, b.address);
    assert_eq!(a.scripthash_hex, b.scripthash_hex);
}

/// Standard disposable BIP39 vector (12 words "abandon…" + "about").
fn test_seed() -> [u8; 64] {
    let mut words: Vec<&str> = vec!["abandon"; 11];
    words.push("about");
    let phrase = words.join(" ");
    let m = bip39::Mnemonic::parse_normalized(&phrase).expect("valid test phrase");
    m.to_seed_normalized("")
}
