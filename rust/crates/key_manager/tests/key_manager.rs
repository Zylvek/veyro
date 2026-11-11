//! Integration tests for `key_manager`.

use key_manager::{from_entropy, from_phrase, generate, random_bytes, validate_phrase, Strength};
use zeroize::Zeroizing;

/// Official BIP39 test vector: entropy of 16 zero bytes.
const ZERO_ENTROPY_PHRASE: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

#[test]
fn known_bip39_vector_zero_entropy() {
    let m = from_entropy(&[0u8; 16]).unwrap();
    let phrase = m.phrase();
    assert_eq!(&*phrase, ZERO_ENTROPY_PHRASE);
    assert_eq!(m.word_count(), 12);
}

#[test]
fn generated_mnemonics_have_expected_word_counts() {
    assert_eq!(generate(Strength::Words12).unwrap().word_count(), 12);
    assert_eq!(generate(Strength::Words24).unwrap().word_count(), 24);
}

#[test]
fn generated_mnemonics_are_unique() {
    let a = generate(Strength::Words24).unwrap();
    let b = generate(Strength::Words24).unwrap();
    assert_ne!(&*a.phrase(), &*b.phrase());
}

#[test]
fn parse_roundtrip_preserves_phrase() {
    let m = generate(Strength::Words24).unwrap();
    let phrase = m.phrase();
    let parsed = from_phrase(&phrase).unwrap();
    assert_eq!(&*parsed.phrase(), &*phrase);
    assert_eq!(parsed.word_count(), 24);
}

#[test]
fn parse_tolerates_whitespace_and_case() {
    let messy = format!("  {}  \n", ZERO_ENTROPY_PHRASE.to_uppercase());
    // Only ASCII input => lowercasing is applied => must parse fine.
    let m = from_phrase(&messy).unwrap();
    assert_eq!(&*m.phrase(), ZERO_ENTROPY_PHRASE);
}

#[test]
fn invalid_phrases_are_rejected() {
    // Nonsense words.
    assert!(from_phrase("not a real mnemonic phrase at all").is_err());
    // Valid words, wrong count and no checksum.
    assert!(from_phrase("abandon abandon abandon").is_err());
    // Valid words, invalid checksum (12x 'abandon' has a bad last word).
    assert!(from_phrase("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon").is_err());
    // Empty.
    assert!(from_phrase("").is_err());
}

#[test]
fn seed_is_deterministic_and_passphrase_sensitive() {
    let m = from_phrase(ZERO_ENTROPY_PHRASE).unwrap();

    let s1 = m.to_seed("");
    let s2 = m.to_seed("");
    assert_eq!(s1.as_bytes(), s2.as_bytes());

    let s_trezor = m.to_seed("TREZOR");
    assert_ne!(s1.as_bytes(), s_trezor.as_bytes());
}

/// BIP39 official vector: the empty-passphrase seed of the zero-entropy
/// mnemonic starts with 5eb00bbd… (see trezor test vectors).
#[test]
fn seed_matches_official_vector_prefix() {
    let m = from_phrase(ZERO_ENTROPY_PHRASE).unwrap();
    let seed = m.to_seed("");
    let hexed = hex::encode(seed.as_bytes());
    assert!(hexed.starts_with("5eb00bbd"), "unexpected seed: {hexed}");
    assert_eq!(seed.as_bytes().len(), 64);
}

#[test]
fn validate_phrase_api() {
    assert!(validate_phrase(ZERO_ENTROPY_PHRASE).is_ok());
    assert!(validate_phrase("banana banana banana").is_err());
}

#[test]
fn random_bytes_are_random() {
    let a: [u8; 32] = random_bytes();
    let b: [u8; 32] = random_bytes();
    assert_ne!(a, b);
}

#[test]
fn debug_never_leaks_secrets() {
    let m = generate(Strength::Words24).unwrap();
    let debug = format!("{m:?}");
    for word in m.phrase().split(' ') {
        assert!(!debug.contains(word), "debug leaked mnemonic word");
    }
    let seed = m.to_seed("");
    let seed_debug = format!("{seed:?}");
    assert!(!seed_debug.contains(&hex::encode(seed.as_bytes())[..16]));
}

#[test]
fn phrase_is_zeroized_on_drop() {
    // Zeroizing<String> must not panic on drop; this is mostly a compile-time
    // property, but we keep a runtime smoke test for the API shape.
    {
        let m = generate(Strength::Words12).unwrap();
        let _phrase: Zeroizing<String> = m.phrase();
    }
}
