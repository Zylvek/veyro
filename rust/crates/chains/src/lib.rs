//! `chains` — blockchain adapters of VEYRO.
//!
//! Ground rules (mirrors ARCHITECTURE.md):
//! - one adapter per network/family; every adapter is verified against its coin
//!   passport (`docs/coins/*.md`) before any network call is trusted;
//! - all money amounts are `u64`/`i64` **satoshis** — floats never appear in
//!   money paths;
//! - secrets stay in the Rust core: callers hand over derived key material or
//!   seeds and get back signed transactions; nothing secret is ever logged;
//! - light access only: public Electrum (the "own/public Electrum server" model
//!   of the BTC passport), no custom backends.
//!
//! First adapter: Bitcoin (BIP84 native SegWit, mainnet/testnet/testnet4).

#![forbid(unsafe_code)]

pub mod bitcoin;
pub mod electrum;

pub use crate::bitcoin::tx::SignedTransfer;
pub use crate::bitcoin::{DEFAULT_GAP_LIMIT, P2WPKH_DUST_SAT, SEQUENCE_NO_RBF};
pub use crate::electrum::{
    BroadcastOutcome, BtcNetwork, Gateway, GatewayNetworkInfo, HistoryEntry, ScriptBalance, Utxo,
};

use thiserror::Error;

/// Adapter-level error surfaced to the bridge/UI. The goal is a typed,
/// actionable error set — the UI can distinguish "server down" from "not enough
/// funds" from "your input was invalid". `Display` (and therefore every log
/// line) is produced by the per-variant message, which never contains secrets.
#[derive(Debug, Error)]
pub enum ChainError {
    #[error("network transport error: {0}")]
    Transport(String),
    #[error("electrum protocol error: {0}")]
    Protocol(String),
    #[error("invalid server url: {0}")]
    InvalidServerUrl(String),
    #[error("invalid recipient address: {0}")]
    InvalidAddress(String),
    #[error("recipient address is not a {0} address")]
    AddressNetworkMismatch(&'static str),
    #[error("invalid amount: {0}")]
    InvalidAmount(String),
    #[error("fee rate must be at least 1 sat/vB")]
    FeeTooLow,
    #[error("fee estimate unavailable from the server (got {0})")]
    FeeEstimateUnavailable(f64),
    #[error("amount {amount_sat} sat is below the dust limit ({dust_sat} sat)")]
    Dust { amount_sat: u64, dust_sat: u64 },
    #[error(
        "insufficient funds: need {required_sat} sat, available {available_sat} sat spendable"
    )]
    InsufficientFunds {
        required_sat: u64,
        available_sat: u64,
    },
    #[error("no spendable outputs (balance may be unconfirmed or below dust)")]
    NoSpendableOutputs,
    #[error("key derivation failure: {0}")]
    KeyDerivation(String),
    #[error("crypto failure: {0}")]
    Crypto(String),
    #[error("broadcast rejected by the network: {0}")]
    BroadcastRejected(String),
    #[error("transaction not found: {0}")]
    TxNotFound(String),
    #[error("internal failure: {0}")]
    Internal(String),
}

impl ChainError {
    /// Wrap a derivation/copy failure message. Redacts overlong context so a
    /// panic message can never smuggle a blob of key material into logs.
    pub fn key(mut msg: String) -> Self {
        if msg.len() > 200 {
            msg.truncate(200);
        }
        ChainError::KeyDerivation(msg)
    }
}

/// Electrum scripthash: `sha256(scriptPubKey)` bytes reversed, lower-case hex.
/// Defined by the Electrum protocol (used as the address identifier for
/// scripthash.* RPC calls).
pub fn electrum_scripthash_hex(script_pubkey: &::bitcoin::Script) -> String {
    use ::sha2::{Digest, Sha256};
    let digest = Sha256::digest(script_pubkey.as_bytes());
    let mut reversed = [0u8; 32];
    for (i, b) in digest.iter().rev().enumerate() {
        reversed[i] = *b;
    }
    hex::encode(reversed)
}
