//! `key_manager` — wallet entropy, BIP39 mnemonics and seed derivation.
//!
//! - Entropy comes from the OS CSPRNG (`rand_core::OsRng`), never from userland PRNGs.
//! - Mnemonics are BIP39 (English wordlist) via the audited `bip39` crate
//!   (rust-bitcoin). The phrase is zeroized on drop.
//! - Seeds are the standard BIP39 512-bit PBKDF2-HMAC-SHA512 (2048 iterations)
//!   of `mnemonic` with `"mnemonic" + passphrase` as salt, and are zeroized on drop.
//!
//! Chain-specific key derivation (BIP32/BIP44 and native schemes for Monero,
//! Kaspa, Zcash, Iron Fish, ...) is intentionally NOT here; it lives in the
//! chain adapters and must be verified per network (see docs/coins/). This
//! module provides only the portable foundation.

#![forbid(unsafe_code)]

use bip39::{Language, Mnemonic as Bip39Mnemonic, WordCount};
use rand_core::{OsRng, RngCore};
use thiserror::Error;
use zeroize::Zeroizing;

/// BIP39 seed length in bytes.
pub const SEED_LEN: usize = 64;

#[derive(Debug, Error)]
pub enum KeyManagerError {
    #[error("mnemonic generation failed: {0}")]
    Generation(String),
    #[error("invalid mnemonic phrase: {0}")]
    InvalidMnemonic(String),
    #[error("invalid entropy length: {0}")]
    InvalidEntropy(usize),
}

/// Mnemonic strength. MultiWallet UI offers 24 words; 12 remains supported for
/// importing existing wallets.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Strength {
    Words12,
    Words24,
}

impl Strength {
    pub fn entropy_bits(self) -> usize {
        match self {
            Self::Words12 => 128,
            Self::Words24 => 256,
        }
    }

    pub fn word_count(self) -> usize {
        match self {
            Self::Words12 => 12,
            Self::Words24 => 24,
        }
    }
}

/// A validated BIP39 mnemonic. The underlying phrase is zeroized on drop
/// (feature `zeroize` of the `bip39` crate).
#[derive(Clone)]
pub struct Mnemonic {
    inner: Bip39Mnemonic,
}

// Never expose the phrase through Debug.
impl std::fmt::Debug for Mnemonic {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Mnemonic")
            .field("word_count", &self.inner.word_count())
            .finish()
    }
}

impl Mnemonic {
    /// The mnemonic phrase (zeroized on drop of the returned value).
    pub fn phrase(&self) -> Zeroizing<String> {
        Zeroizing::new(self.inner.to_string())
    }

    pub fn word_count(&self) -> usize {
        self.inner.word_count()
    }

    /// Derive the BIP39 seed with an optional passphrase ("25th word").
    /// Deterministic: same phrase + same passphrase => same seed.
    pub fn to_seed(&self, passphrase: &str) -> Seed {
        Seed(Zeroizing::new(self.inner.to_seed_normalized(passphrase)))
    }
}

/// A 64-byte BIP39 seed. Zeroized on drop.
pub struct Seed(Zeroizing<[u8; SEED_LEN]>);

impl Seed {
    pub fn from_bytes(bytes: [u8; SEED_LEN]) -> Self {
        Self(Zeroizing::new(bytes))
    }

    pub fn as_bytes(&self) -> &[u8; SEED_LEN] {
        &self.0
    }
}

// Never expose seed bytes through Debug.
impl std::fmt::Debug for Seed {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Seed(<64 secret bytes>)")
    }
}

/// Generate a fresh mnemonic using OS entropy. `English` wordlist, as
/// universally supported by mining-payout-friendly wallets and hardware devices.
pub fn generate(strength: Strength) -> Result<Mnemonic, KeyManagerError> {
    let wc = match strength {
        Strength::Words12 => WordCount::Words12,
        Strength::Words24 => WordCount::Words24,
    };
    let inner = Bip39Mnemonic::generate_in_with(&mut OsRng, Language::English, wc)
        .map_err(|e| KeyManagerError::Generation(e.to_string()))?;
    Ok(Mnemonic { inner })
}

/// Build a mnemonic from externally supplied entropy (e.g. hardware RNG).
/// Length must be 16..=32 bytes and a multiple of 4 (BIP39).
pub fn from_entropy(entropy: &[u8]) -> Result<Mnemonic, KeyManagerError> {
    if entropy.len() < 16 || entropy.len() > 32 || entropy.len() % 4 != 0 {
        return Err(KeyManagerError::InvalidEntropy(entropy.len()));
    }
    let inner = Bip39Mnemonic::from_entropy(entropy)
        .map_err(|e| KeyManagerError::Generation(e.to_string()))?;
    Ok(Mnemonic { inner })
}

/// Parse and validate a user-entered mnemonic phrase.
///
/// Whitespace is normalized (any runs of spaces/tabs/newlines collapse to
/// single ASCII spaces) and ASCII input is lowercased, which is safe for the
/// English wordlist. Checksum and wordlist membership are enforced by `bip39`.
pub fn from_phrase(phrase: &str) -> Result<Mnemonic, KeyManagerError> {
    let normalized: String = phrase.split_whitespace().collect::<Vec<_>>().join(" ");
    let normalized = if normalized.is_ascii() {
        normalized.to_lowercase()
    } else {
        normalized
    };
    let inner = Bip39Mnemonic::parse_normalized(&normalized)
        .map_err(|e| KeyManagerError::InvalidMnemonic(e.to_string()))?;
    Ok(Mnemonic { inner })
}

/// Validate a phrase without keeping it around longer than necessary.
pub fn validate_phrase(phrase: &str) -> Result<(), KeyManagerError> {
    from_phrase(phrase).map(|_| ())
}

/// Uniform random bytes from the OS CSPRNG (for ids, salts, native schemes).
pub fn random_bytes<const N: usize>() -> [u8; N] {
    let mut buf = [0u8; N];
    OsRng.fill_bytes(&mut buf);
    buf
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strength_mapping() {
        assert_eq!(Strength::Words12.entropy_bits(), 128);
        assert_eq!(Strength::Words12.word_count(), 12);
        assert_eq!(Strength::Words24.entropy_bits(), 256);
        assert_eq!(Strength::Words24.word_count(), 24);
    }

    #[test]
    fn entropy_length_is_validated() {
        assert!(from_entropy(&[0u8; 15]).is_err());
        assert!(from_entropy(&[0u8; 12]).is_err());
        assert!(from_entropy(&[0u8; 33]).is_err());
        assert!(from_entropy(&[0u8; 16]).is_ok());
    }
}
