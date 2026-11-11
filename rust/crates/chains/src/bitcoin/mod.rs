//! Bitcoin adapter (BIP84 native SegWit) — the reference adapter of PHASE 4.
//!
//! Layout:
//! - [`keys`] — BIP32 tree from the BIP39 seed, BIP84 addresses, scripthashes;
//! - [`scan`] — address discovery (gap limit), UTXO/balance/history collection;
//! - [`tx`]  — fee estimation, transaction planning/build, local signing,
//!   idempotent broadcast, confirmation status.
//!
//! Constants documented in `docs/coins/BTC.md` (dust, gap discipline, sequence).

pub mod keys;
pub mod scan;
pub mod tx;

/// Dust threshold for P2WPKH outputs (satoshis): standard script dust limit
/// for a v0 witness program with OP_0 + 20-byte key hash.
/// dust = 3 * (per-output overhead) computed per BIP rules => 294 sat.
pub const P2WPKH_DUST_SAT: u64 = 294;

/// Address discovery gap limit (BIP44 convention): stop after this many
/// consecutive unused addresses past the last used index of a branch.
pub const DEFAULT_GAP_LIMIT: u32 = 20;

/// Input sequence: final AND **not** signaling BIP-125 replace-by-fee.
/// Replaceability (RBF/CPFP) is deliberately out of scope for this milestone;
/// making that decision visible here keeps it reviewable.
pub const SEQUENCE_NO_RBF: u32 = 0xFFFF_FFFE;
