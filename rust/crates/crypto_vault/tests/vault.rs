//! Integration tests for `crypto_vault`.
//!
//! Argon2id at full cost (64 MiB, t=3) takes ~0.3–1 s per call on desktop; to
//! keep the suite fast while still exercising real Argon2id + XChaCha20-Poly1305,
//! most tests use lighter (but still safe-validated) parameters.

use crypto_vault::{decrypt, encrypt, KdfParams, VaultEnvelope, VaultError};

fn test_kdf() -> KdfParams {
    KdfParams {
        m_kib: 8192,
        t: 1,
        p: 1,
    }
}

fn default_kdf() -> KdfParams {
    KdfParams::default()
}

#[test]
fn roundtrip_with_serialization() {
    let secret = b"top secret wallet material";
    let envelope = encrypt("correct horse battery staple", secret, test_kdf()).unwrap();

    let json = envelope.to_json().unwrap();
    let parsed = VaultEnvelope::from_json(&json).unwrap();
    assert_eq!(parsed, envelope);

    let recovered = decrypt("correct horse battery staple", &parsed).unwrap();
    assert_eq!(&*recovered, secret);
}

#[test]
fn full_default_params_roundtrip() {
    // One test at the actual production cost to prove the default parameters work.
    let secret = b"production params";
    let envelope = encrypt("pw", secret, default_kdf()).unwrap();
    assert_eq!(envelope.kdf, default_kdf());
    let recovered = decrypt("pw", &envelope).unwrap();
    assert_eq!(&*recovered, secret);
}

#[test]
fn wrong_password_fails() {
    let envelope = encrypt("right password", b"data", test_kdf()).unwrap();
    match decrypt("wrong password", &envelope) {
        Err(VaultError::Decrypt) => {}
        other => panic!("expected generic Decrypt error, got: {other:?}"),
    }
}

#[test]
fn tampered_ciphertext_fails() {
    let mut envelope = encrypt("pw", b"some data", test_kdf()).unwrap();
    let mid = envelope.ciphertext.len() / 2;
    envelope.ciphertext[mid] ^= 0x01;
    assert!(matches!(decrypt("pw", &envelope), Err(VaultError::Decrypt)));
}

#[test]
fn tampered_nonce_fails() {
    let mut envelope = encrypt("pw", b"some data", test_kdf()).unwrap();
    envelope.nonce[0] ^= 0xff;
    assert!(matches!(decrypt("pw", &envelope), Err(VaultError::Decrypt)));
}

#[test]
fn tampered_salt_fails() {
    let mut envelope = encrypt("pw", b"some data", test_kdf()).unwrap();
    envelope.salt[15] ^= 0x01;
    // A different salt derives a different key -> AEAD must reject.
    assert!(matches!(decrypt("pw", &envelope), Err(VaultError::Decrypt)));
}

#[test]
fn truncated_ciphertext_rejected_as_malformed() {
    let mut envelope = encrypt("pw", b"x", test_kdf()).unwrap();
    envelope.ciphertext.truncate(15); // less than the Poly1305 tag
    assert!(matches!(
        decrypt("pw", &envelope),
        Err(VaultError::MalformedEnvelope)
    ));
}

#[test]
fn malformed_salt_length_rejected() {
    let mut envelope = encrypt("pw", b"x", test_kdf()).unwrap();
    envelope.salt.push(0);
    assert!(matches!(
        decrypt("pw", &envelope),
        Err(VaultError::MalformedEnvelope)
    ));
}

#[test]
fn unsupported_version_rejected() {
    let mut envelope = encrypt("pw", b"x", test_kdf()).unwrap();
    envelope.version = 99;
    assert!(matches!(
        decrypt("pw", &envelope),
        Err(VaultError::UnsupportedVersion(99))
    ));
}

#[test]
fn malicious_kdf_params_rejected_on_decrypt() {
    // Envelope claims absurd Argon2id cost; decrypt must refuse before deriving.
    let mut envelope = encrypt("pw", b"x", test_kdf()).unwrap();
    envelope.kdf = KdfParams {
        m_kib: 1 << 20,
        t: u32::MAX,
        p: 16,
    };
    assert!(matches!(
        decrypt("pw", &envelope),
        Err(VaultError::InvalidParams)
    ));
}

#[test]
fn malicious_kdf_params_rejected_on_encrypt() {
    assert!(matches!(
        encrypt(
            "pw",
            b"x",
            KdfParams {
                m_kib: u32::MAX,
                t: 4,
                p: 1
            }
        ),
        Err(VaultError::InvalidParams)
    ));
}

#[test]
fn encryption_is_randomized() {
    let a = encrypt("pw", b"same plaintext", test_kdf()).unwrap();
    let b = encrypt("pw", b"same plaintext", test_kdf()).unwrap();
    assert_ne!(a.salt, b.salt);
    assert_ne!(a.nonce, b.nonce);
    assert_ne!(a.ciphertext, b.ciphertext);
}

#[test]
fn empty_plaintext_roundtrip() {
    let envelope = encrypt("pw", b"", test_kdf()).unwrap();
    let recovered = decrypt("pw", &envelope).unwrap();
    assert!(recovered.is_empty());
}

#[test]
fn large_plaintext_roundtrip() {
    // A few MiB, to verify streaming behaviour of the AEAD on realistic payloads.
    let secret = vec![0x5au8; 4 * 1024 * 1024];
    let envelope = encrypt("pw", &secret, test_kdf()).unwrap();
    let recovered = decrypt("pw", &envelope).unwrap();
    assert_eq!(&*recovered, &secret);
}

#[test]
fn envelope_json_has_expected_shape() {
    let envelope = encrypt("pw", b"data", test_kdf()).unwrap();
    let json = envelope.to_json().unwrap();
    // Structured fields must be present and version pinned.
    assert!(json.contains("\"version\":1"));
    assert!(json.contains("\"kdf\""));
    // No base64/JSON leak of plaintext (payload is hex-encoded ciphertext only).
    assert!(!json.contains("data"));
}
