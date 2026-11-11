//! `crypto_vault` — authenticated encryption-at-rest for wallet secrets.
//!
//! Construction (envelope v1):
//! - KDF: **Argon2id** (RFC 9106), default params m = 64 MiB, t = 3, p = 1.
//! - AEAD: **XChaCha20-Poly1305** with a fresh random 24-byte nonce per envelope.
//! - Randomness: OS CSPRNG (`rand_core::OsRng`).
//!
//! Security properties:
//! - Ciphertext integrity is verified by the Poly1305 tag.
//! - A wrong password is indistinguishable from corrupted data (single generic
//!   error, no password-validation oracle).
//! - KDF parameters are stored in the envelope, but bounded on decrypt to
//!   prevent denial-of-service from malicious files.
//! - Keys and plaintext buffers are zeroized after use.
//!
//! This crate never implements cryptographic primitives itself; it only
//! composes audited implementations (RustCrypto `argon2` / `chacha20poly1305`).

#![forbid(unsafe_code)]

use chacha20poly1305::aead::{Aead, KeyInit};
use chacha20poly1305::{Key, XChaCha20Poly1305, XNonce};
use rand_core::{OsRng, RngCore};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use zeroize::Zeroizing;

/// Salt length in bytes.
pub const SALT_LEN: usize = 16;
/// XChaCha20-Poly1305 nonce length in bytes.
pub const NONCE_LEN: usize = 24;
/// Derived key length in bytes.
pub const KEY_LEN: usize = 32;
/// Current envelope format version.
pub const ENVELOPE_VERSION: u16 = 1;

// Upper bounds for KDF parameters read from untrusted envelopes.
// Prevents a malicious file from forcing minutes of memory allocation.
const KDF_M_KIB_MAX: u32 = 1 << 20; // 1 GiB
const KDF_T_MAX: u32 = 32;
const KDF_P_MAX: u32 = 16;

#[derive(Debug, Error)]
pub enum VaultError {
    #[error("invalid KDF parameters")]
    InvalidParams,
    #[error("key derivation failed")]
    Kdf,
    #[error("encryption failed")]
    Encrypt,
    /// Intentionally generic: never reveal *why* decryption failed.
    #[error("decryption failed: wrong password or corrupted data")]
    Decrypt,
    #[error("unsupported envelope version: {0}")]
    UnsupportedVersion(u16),
    #[error("malformed envelope")]
    MalformedEnvelope,
    #[error("serialization error: {0}")]
    Serialization(String),
}

/// Argon2id parameters (RFC 9106). Serialized inside the envelope so that
/// parameters can be strengthened later without invalidating old wallets.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct KdfParams {
    /// Memory cost in KiB (must be at least `8 * p`).
    pub m_kib: u32,
    /// Time cost (number of passes).
    pub t: u32,
    /// Parallelism.
    pub p: u32,
}

impl Default for KdfParams {
    fn default() -> Self {
        // 64 MiB / 3 passes / 1 lane: strong against GPU attacks, tolerable
        // on mid-range Android devices. Can be raised in future versions.
        Self {
            m_kib: 65536,
            t: 3,
            p: 1,
        }
    }
}

impl KdfParams {
    /// Validate with both lower (correctness) and upper (anti-DoS) bounds.
    pub fn validate(&self) -> Result<(), VaultError> {
        if self.p < 1 || self.p > KDF_P_MAX {
            return Err(VaultError::InvalidParams);
        }
        if self.t < 1 || self.t > KDF_T_MAX {
            return Err(VaultError::InvalidParams);
        }
        if self.m_kib < 8 * self.p || self.m_kib > KDF_M_KIB_MAX {
            return Err(VaultError::InvalidParams);
        }
        Ok(())
    }
}

/// Encrypted envelope. Contains no plaintext and no derived key material:
/// only random salt/nonce and authenticated ciphertext. Safe to persist.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VaultEnvelope {
    pub version: u16,
    pub kdf: KdfParams,
    #[serde(with = "serde_hex")]
    pub salt: Vec<u8>,
    #[serde(with = "serde_hex")]
    pub nonce: Vec<u8>,
    #[serde(with = "serde_hex")]
    pub ciphertext: Vec<u8>,
}

// Never print raw envelope bytes in logs; expose lengths only.
impl std::fmt::Debug for VaultEnvelope {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("VaultEnvelope")
            .field("version", &self.version)
            .field("kdf", &self.kdf)
            .field("salt_len", &self.salt.len())
            .field("nonce_len", &self.nonce.len())
            .field("ciphertext_len", &self.ciphertext.len())
            .finish()
    }
}

mod serde_hex {
    use serde::{de::Error, Deserialize, Deserializer, Serializer};

    pub fn serialize<S: Serializer>(v: &Vec<u8>, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&hex::encode(v))
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<u8>, D::Error> {
        let s = <String>::deserialize(d)?;
        hex::decode(s.trim()).map_err(|e| D::Error::custom(format!("invalid hex: {e}")))
    }
}

impl VaultEnvelope {
    /// Serialize to a compact JSON string (the on-disk vault format).
    pub fn to_json(&self) -> Result<String, VaultError> {
        serde_json::to_string(self).map_err(|e| VaultError::Serialization(e.to_string()))
    }

    /// Parse from JSON.
    pub fn from_json(s: &str) -> Result<Self, VaultError> {
        serde_json::from_str(s).map_err(|e| VaultError::Serialization(e.to_string()))
    }

    fn check_lengths(&self) -> Result<(), VaultError> {
        if self.salt.len() != SALT_LEN
            || self.nonce.len() != NONCE_LEN
            || self.ciphertext.len() < 16
        // Poly1305 tag
        {
            return Err(VaultError::MalformedEnvelope);
        }
        Ok(())
    }
}

fn derive_key(
    password: &str,
    salt: &[u8],
    kdf: &KdfParams,
) -> Result<Zeroizing<[u8; KEY_LEN]>, VaultError> {
    let params = argon2::Params::new(kdf.m_kib, kdf.t, kdf.p, Some(KEY_LEN))
        .map_err(|_| VaultError::InvalidParams)?;
    let argon = argon2::Argon2::new(argon2::Algorithm::Argon2id, argon2::Version::V0x13, params);
    let mut key = Zeroizing::new([0u8; KEY_LEN]);
    argon
        .hash_password_into(password.as_bytes(), salt, key.as_mut_slice())
        .map_err(|_| VaultError::Kdf)?;
    Ok(key)
}

/// Encrypt `plaintext` under `password`.
///
/// A fresh random salt and nonce are generated for every call, so encrypting
/// the same data twice yields different envelopes (no determinism leakage).
pub fn encrypt(
    password: &str,
    plaintext: &[u8],
    kdf: KdfParams,
) -> Result<VaultEnvelope, VaultError> {
    kdf.validate()?;

    let mut salt = vec![0u8; SALT_LEN];
    OsRng.fill_bytes(&mut salt);
    let mut nonce = vec![0u8; NONCE_LEN];
    OsRng.fill_bytes(&mut nonce);

    let key = derive_key(password, &salt, &kdf)?;
    let cipher = XChaCha20Poly1305::new(Key::from_slice(key.as_slice()));
    let ciphertext = cipher
        .encrypt(XNonce::from_slice(&nonce), plaintext)
        .map_err(|_| VaultError::Encrypt)?;

    Ok(VaultEnvelope {
        version: ENVELOPE_VERSION,
        kdf,
        salt,
        nonce,
        ciphertext,
    })
}

/// Decrypt an envelope with `password`.
///
/// Fails with a single generic error for wrong password, tampering, or
/// corruption — callers learn nothing about which part failed.
pub fn decrypt(password: &str, envelope: &VaultEnvelope) -> Result<Zeroizing<Vec<u8>>, VaultError> {
    if envelope.version != ENVELOPE_VERSION {
        return Err(VaultError::UnsupportedVersion(envelope.version));
    }
    envelope.kdf.validate()?;
    envelope.check_lengths()?;

    let key = derive_key(password, &envelope.salt, &envelope.kdf)?;
    let cipher = XChaCha20Poly1305::new(Key::from_slice(key.as_slice()));
    let plaintext = cipher
        .decrypt(
            XNonce::from_slice(&envelope.nonce),
            envelope.ciphertext.as_slice(),
        )
        .map_err(|_| VaultError::Decrypt)?;

    Ok(Zeroizing::new(plaintext))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_kdf_params_are_valid() {
        assert!(KdfParams::default().validate().is_ok());
    }

    #[test]
    fn kdf_bounds_reject_zero_and_huge() {
        assert!(KdfParams {
            m_kib: 8,
            t: 1,
            p: 1
        }
        .validate()
        .is_ok()); // 8 KiB == 8*p, minimum
        assert!(KdfParams {
            m_kib: 7,
            t: 1,
            p: 1
        }
        .validate()
        .is_err()); // below 8*p
        assert!(KdfParams {
            m_kib: 0,
            t: 0,
            p: 0
        }
        .validate()
        .is_err());
        assert!(KdfParams {
            m_kib: (1 << 20) + 1,
            t: 1,
            p: 1
        }
        .validate()
        .is_err()); // > 1 GiB
        assert!(KdfParams {
            m_kib: 65536,
            t: 33,
            p: 1
        }
        .validate()
        .is_err()); // t too high
        assert!(KdfParams {
            m_kib: 65536,
            t: 1,
            p: 17
        }
        .validate()
        .is_err()); // p too high
    }
}
