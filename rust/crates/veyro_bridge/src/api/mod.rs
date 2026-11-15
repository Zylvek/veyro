//! Public API surface exposed to Dart via flutter_rust_bridge.
//!
//! Everything `pub` in this module tree becomes a Dart function. Keep this
//! surface thin: real logic lives in the core crates, which own the tests.

pub mod backup;
pub mod btc;
pub mod ltc;
pub mod session;
pub mod storage;
pub mod wallet;
