//! `veyro_bridge` — the FFI boundary between the Flutter UI and the Rust core.
//!
//! Security contract of this crate:
//!
//! - The **only** secrets that ever cross the FFI boundary are:
//!   1. user-typed passwords (unavoidable — the UI reads them),
//!   2. the one-time mnemonic phrase shown to the user right after wallet
//!      creation, and the phrase revealed by the explicit user action
//!      "reveal mnemonic".
//! - The BIP39 **seed** and backup **payloads** never cross the boundary:
//!   backup export/import runs entirely inside Rust
//!   (`wallet_core::reveal_secrets` → `backup_manager`).
//! - Wallet operations open the wallet directory per call; the bridge keeps
//!   no secret state.
//!
//! Unlike the core crates (`#![forbid(unsafe_code)]`), this crate does NOT
//! forbid `unsafe`: the flutter_rust_bridge generated glue
//! (`src/frb_generated.rs`) may legitimately require it. Hand-written code in
//! this crate avoids `unsafe`; the exception is audited to the generated
//! file only.

pub mod api;
mod btc_session;
mod frb_generated;

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
