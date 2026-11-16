//! `veyro_bridge` — the FFI boundary between the Flutter UI and the Rust core.
//!
//! Security contract of this crate:
//!
//! - The **only** secrets that ever cross the FFI boundary are:
//!   1. user-typed passwords (unavoidable — the UI reads them),
//!   2. the one-time mnemonic phrase shown to the user right after wallet
//!      creation, and the phrase revealed by the explicit user action
//!      "reveal mnemonic".
//! - The BIP39 **seed** never crosses the boundary: unlocking keeps it inside
//!   Rust in a zeroizing coin session; signing runs against that copy.
//! - Wallet operations open the wallet directory per call; the bridge keeps
//!   no secret state besides sessions and the per-wallet password cache.
//!
//! Unlike the core crates (`#![forbid(unsafe_code)]`), this crate does NOT
//! forbid `unsafe`: the flutter_rust_bridge generated glue
//! (`src/frb_generated.rs`) may legitimately require it. Hand-written code in
//! this crate avoids `unsafe`; the exception is audited to the generated
//! file only.

pub mod api;
mod btc_session;
mod frb_generated;
mod ltc_session;
mod session_password;

use chains::ChainError;
use crypto_vault::KdfParams;

/// Production KDF parameters for wallets created or restored through the UI
/// (64 MiB / t=3 / p=1, as documented for `crypto_vault`).
pub fn production_kdf() -> KdfParams {
    KdfParams {
        m_kib: 65536,
        t: 3,
        p: 1,
    }
}

/// Единственный классификатор «один reconnect/retry оправдан» для синхронных
/// операций BTC/LTC (transport + protocol от ядра; одна реализация вместо
/// четырёх копий строковых проверок). Ошибки содержания (адрес, сумма, ключи)
/// никогда не триггерят retry.
pub(crate) fn is_transient_sync_error(e: &ChainError) -> bool {
    matches!(e, ChainError::Transport(_) | ChainError::Protocol(_))
}
