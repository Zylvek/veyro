//! Official BIP143 native P2WPKH test vector
//! (https://github.com/bitcoin/bips/blob/master/bip-0143.mediawiki — the
//! "Native P2WPKH" example) — verbatim hex pins.
//!
//! What is pinned:
//! 1. the BIP143 digest of input 1 (the second, witness input) equals the
//!    documented `c37af311…cb670`;
//! 2. our local signing of input 1 reproduces the officially signed raw
//!    transaction byte-for-byte (RFC6979 deterministic nonces on both sides);
//! 3. the pubkey derived from the documented private key matches the vector.
//!
//! Input 0 of the vector is a legacy P2PK input — out of scope for this
//! adapter (we only sign P2WPKH inputs). The test therefore starts from the
//! officially SIGNED transaction (input 0 legacy sig intact) and re-signs
//! input 1 through our code path.

use bitcoin::consensus::Decodable;
use chains::bitcoin::tx::{bip143_sighash_p2wpkh, sign_p2wpkh_input};
use hex::FromHex;

/// BIP143 example: full signed transaction (input 0 = legacy P2PK + input 1 =
/// P2WPKH, both SIGHASH_ALL). Copied verbatim from the BIP document: note the
/// BIP144 layout — witnesses come after txouts, locktime last; input 0's
/// witness is a zero-item count ("00") and the trailing bytes are the
/// locktime (`11 000000` = 17).
const SIGNED_TX_HEX: &str = "01000000000102fff7f7881a8099afa6940d42d1e7f6362bec38171ea3edf433541db4e4ad969f00000000494830450221008b9d1dc26ba6a9cb62127b02742fa9d754cd3bebf337f7a55d114c8e5cdd30be022040529b194ba3f9281a99f2b1c0a19c0489bc22ede944ccf4ecbab4cc618ef3ed01eeffffffef51e1b804cc89d182d279655c3aa89e815b1b309fe287d9b2b55d57b90ec68a0100000000ffffffff02202cb206000000001976a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac9093510d000000001976a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac000247304402203609e17b84f6a7d30c80bfa610b5b4542f32a8a0d5447a12fb1366d7f01cc44a0220573a954c4518331561406f90300e8f3358f51928d43c212a8caed02de67eebee0121025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee635711000000";

/// The unsigned counterpart, used for the digest step.
const UNSIGNED_TX_HEX: &str = "0100000002fff7f7881a8099afa6940d42d1e7f6362bec38171ea3edf433541db4e4ad969f0000000000eeffffffef51e1b804cc89d182d279655c3aa89e815b1b309fe287d9b2b55d57b90ec68a0100000000ffffffff02202cb206000000001976a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac9093510d000000001976a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac11000000";

/// Vector data for input 1 (P2WPKH): value 6 BTC, key hash witness program
/// 00141d0f172a0ecb48aee1be1f2687d2963ae33f71a1.
const INPUT_1_VALUE_SAT: u64 = 600_000_000;
const INPUT_1_PRIVKEY_HEX: &str =
    "619c335025c7f4012e556c2a58b2506e30b8511b53ade95ea316fd8c3286feb9";
const INPUT_1_PUBKEY_HEX: &str =
    "025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee6357";
const INPUT_1_SIGHASH_HEX: &str =
    "c37af31116d1b27caf68aae9e3ac82f1477929014d5b917657d0eb49478cb670";

/// Witness of input 1 in the official signature:
/// item0 = `30 44 … 01` (71 bytes, 0x47), item1 = `21 025476c2…` (33 bytes).
const INPUT_1_WITNESS_OFFICIAL: [&str; 2] = [
    "304402203609e17b84f6a7d30c80bfa610b5b4542f32a8a0d5447a12fb1366d7f01cc44a0220573a954c4518331561406f90300e8f3358f51928d43c212a8caed02de67eebee01",
    "025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee6357",
];

fn decode_tx(hex_str: &str) -> bitcoin::Transaction {
    let bytes = Vec::from_hex(hex_str).expect("vector tx hex is valid");
    Decodable::consensus_decode(&mut bytes.as_slice()).expect("vector tx parses")
}

#[test]
fn bip143_digest_of_input_1_matches_vector() {
    let mut tx = decode_tx(UNSIGNED_TX_HEX);
    let pubkey = Vec::from_hex(INPUT_1_PUBKEY_HEX).unwrap();
    let digest = bip143_sighash_p2wpkh(&mut tx, 1, INPUT_1_VALUE_SAT, &pubkey)
        .expect("digest of a valid P2WPKH input");
    assert_eq!(hex::encode(digest), INPUT_1_SIGHASH_HEX);
}

#[test]
fn local_signing_reproduces_the_bip143_vector() {
    let mut tx = decode_tx(SIGNED_TX_HEX);
    let sk = Vec::from_hex(INPUT_1_PRIVKEY_HEX).unwrap();

    // Sanity: the documented private key derives the documented pubkey.
    let secret = bitcoin::secp256k1::SecretKey::from_slice(&sk).unwrap();
    let secp = bitcoin::secp256k1::Secp256k1::signing_only();
    let pk = bitcoin::secp256k1::PublicKey::from_secret_key(&secp, &secret);
    assert_eq!(hex::encode(pk.serialize()), INPUT_1_PUBKEY_HEX);

    // The witness must be re-signable after a round trip.
    let witness_before = tx.input[1]
        .witness
        .iter()
        .map(hex::encode)
        .collect::<Vec<_>>();
    assert_eq!(
        witness_before, INPUT_1_WITNESS_OFFICIAL,
        "official witness parses"
    );

    sign_p2wpkh_input(
        &mut tx,
        1,
        INPUT_1_VALUE_SAT,
        sk.as_slice().try_into().unwrap(),
    )
    .expect("signing succeeds");

    let re_signed = hex::encode({
        let mut buf = Vec::new();
        bitcoin::consensus::Encodable::consensus_encode(&tx, &mut buf).unwrap();
        buf
    });
    assert_eq!(
        re_signed, SIGNED_TX_HEX,
        "local BIP143 signing must reproduce the official vector byte-for-byte"
    );
}

#[test]
fn signed_tx_witness_and_id_structure() {
    // Independent structural checks: witness items and the input set.
    let tx = decode_tx(SIGNED_TX_HEX);
    assert_eq!(tx.input.len(), 2);
    assert_eq!(
        tx.input[0].witness.to_vec().len(),
        0,
        "legacy input has no witness"
    );
    assert_eq!(
        tx.input[1].witness.to_vec().len(),
        2,
        "P2WPKH witness = sig+pk"
    );
    let wit = tx.input[1].witness.to_vec();
    assert_eq!(hex::encode(&wit[0]), INPUT_1_WITNESS_OFFICIAL[0]);
    assert_eq!(hex::encode(&wit[1]), INPUT_1_WITNESS_OFFICIAL[1]);
    assert_eq!(
        hex::encode(&wit[0]),
        INPUT_1_WITNESS_OFFICIAL[0],
        "sighash byte 0x01 included"
    );
}
