//! BIP84 key derivation: BIP39 seed → m/84'/coin'/account' → native SegWit
//! addresses (P2WPKH, BIP84/BIP173).
//!
//! Security model:
//! - the caller hands over the BIP39 seed (`[u8; 64]`); it is used *in scope*
//!   and never copied into any struct of this module;
//! - hardened derivation happens once per account, then only the **account
//!   xpub** (public) is retained — address generation is watch-only and cannot
//!   expose key material;
//! - spending requires a separately derived, zeroizing, single-use secret key
//!   ([`derive_secret_key`]) — produced on demand inside the signing call.
//!
//! Paths follow BIP84 exactly: `m / 84' / coin' / account' / change / index`
//! with coin 0 (mainnet) or 1 (any testnet).

use crate::electrum::BtcNetwork;
use crate::{electrum_scripthash_hex, ChainError};
use bitcoin::bip32::{ChildNumber, DerivationPath, Xpriv, Xpub};
use bitcoin::{Address, ScriptBuf};
use zeroize::Zeroizing;

/// BIP84 purpose value (`m/84'/…`).
pub const BIP84_PURPOSE: u32 = 84;

/// Branch number for receiving addresses (external chain).
pub const BRANCH_EXTERNAL: u32 = 0;
/// Branch number for change addresses (internal chain).
pub const BRANCH_INTERNAL: u32 = 1;

/// A fully derived BIP84 address and everything the wallet records about it.
/// Contains public data only.
#[derive(Debug, Clone)]
pub struct DerivedAddress {
    /// Bech32 address string (`bc1q…` / `tb1q…`).
    pub address: String,
    /// `0014{keyhash}` — the script the network pays to.
    pub script_pubkey: ScriptBuf,
    /// Electrum scripthash (reversed sha256, hex) used by the gateway.
    pub scripthash_hex: String,
    /// 0 = receiving (external), 1 = change (internal).
    pub branch: u32,
    /// Address index inside the branch.
    pub index: u32,
    /// Human-readable BIP32 path, e.g. `m/84'/0'/0'/0/3`.
    pub path: String,
}

/// Watch-only public handle of a BIP84 account: everything needed to discover
/// addresses, track balances and build transactions; NOT sufficient to sign.
#[derive(Debug, Clone)]
pub struct AccountPubkeys {
    network: BtcNetwork,
    account: u32,
    account_xpub: Xpub,
}

impl AccountPubkeys {
    /// Derive the account keys from a BIP39 seed (empty or with passphrase —
    /// the caller supplies the ready BIP39 seed bytes).
    ///
    /// The hardened chain `m/84'/coin'/account'` is derived inside this
    /// function and the private keys are dropped on return.
    pub fn from_seed(
        seed: &[u8; 64],
        network: BtcNetwork,
        account: u32,
    ) -> Result<Self, ChainError> {
        let secp = bitcoin::secp256k1::Secp256k1::new();
        let hardened = |i: u32| -> Result<ChildNumber, ChainError> {
            ChildNumber::from_hardened_idx(i)
                .map_err(|e| ChainError::key(format!("hardened child {i}: {e}")))
        };
        let path: DerivationPath = [
            hardened(BIP84_PURPOSE)?,
            hardened(network.coin_type())?,
            hardened(account)?,
        ]
        .into_iter()
        .collect();

        let master = Xpriv::new_master(network.bitcoin_network(), seed)
            .map_err(|e| ChainError::key(format!("master key: {e}")))?;
        let account_key = master
            .derive_priv(&secp, &path)
            .map_err(|e| ChainError::key(format!("account derivation: {e}")))?;
        let account_xpub = Xpub::from_priv(&secp, &account_key);
        // `master` and `account_key` (private) go out of scope here; the
        // account key of rust-secp256k1 zeroizes on drop.
        Ok(Self {
            network,
            account,
            account_xpub,
        })
    }

    pub fn network(&self) -> BtcNetwork {
        self.network
    }

    pub fn account(&self) -> u32 {
        self.account
    }

    /// Public account key (safe to persist/display; enables watch-only).
    pub fn account_xpub(&self) -> &Xpub {
        &self.account_xpub
    }

    /// Derive the address at `branch/index` from the PUBLIC account key.
    pub fn derive_address(&self, branch: u32, index: u32) -> Result<DerivedAddress, ChainError> {
        if branch != BRANCH_EXTERNAL && branch != BRANCH_INTERNAL {
            return Err(ChainError::KeyDerivation(format!(
                "invalid BIP84 branch {branch} (expected 0 or 1)"
            )));
        }
        let normal = |i: u32| -> Result<ChildNumber, ChainError> {
            ChildNumber::from_normal_idx(i)
                .map_err(|e| ChainError::key(format!("normal child {i}: {e}")))
        };
        let path: DerivationPath = [normal(branch)?, normal(index)?].into_iter().collect();

        let secp = bitcoin::secp256k1::Secp256k1::verification_only();
        let child = self
            .account_xpub
            .derive_pub(&secp, &path)
            .map_err(|e| ChainError::key(format!("xpub child: {e}")))?;
        let compressed = bitcoin::key::CompressedPublicKey::from_slice(
            child.public_key.serialize().as_ref(),
        )
        .map_err(|e| ChainError::key(format!("compressed pubkey: {e}")))?;
        let address = Address::p2wpkh(&compressed, self.network.bitcoin_network());

        let script_pubkey = address.script_pubkey();
        Ok(DerivedAddress {
            address: address.to_string(),
            scripthash_hex: electrum_scripthash_hex(&script_pubkey),
            script_pubkey,
            branch,
            index,
            path: format_path(self.network.coin_type(), self.account, branch, index),
        })
    }
}

/// Derive the (zeroizing) secret key of `branch/index` under
/// `m/84'/coin'/account'` — used only inside local signing. The bytes are
/// wiped when the returned wrapper is dropped.
pub fn derive_secret_key(
    seed: &[u8; 64],
    network: BtcNetwork,
    account: u32,
    branch: u32,
    index: u32,
) -> Result<Zeroizing<[u8; 32]>, ChainError> {
    if branch != BRANCH_EXTERNAL && branch != BRANCH_INTERNAL {
        return Err(ChainError::KeyDerivation(format!(
            "invalid BIP84 branch {branch} (expected 0 or 1)"
        )));
    }
    let secp = bitcoin::secp256k1::Secp256k1::new();
    let hardened = |i: u32| -> Result<ChildNumber, ChainError> {
        ChildNumber::from_hardened_idx(i)
            .map_err(|e| ChainError::key(format!("hardened child {i}: {e}")))
    };
    let normal = |i: u32| -> Result<ChildNumber, ChainError> {
        ChildNumber::from_normal_idx(i)
            .map_err(|e| ChainError::key(format!("normal child {i}: {e}")))
    };
    let path: DerivationPath = [
        hardened(BIP84_PURPOSE)?,
        hardened(network.coin_type())?,
        hardened(account)?,
        normal(branch)?,
        normal(index)?,
    ]
    .into_iter()
    .collect();

    let master = Xpriv::new_master(network.bitcoin_network(), seed)
        .map_err(|e| ChainError::key(format!("master key: {e}")))?;
    let leaf = master
        .derive_priv(&secp, &path)
        .map_err(|e| ChainError::key(format!("leaf derivation: {e}")))?;
    let mut bytes = <[u8; 32]>::default();
    bytes.copy_from_slice(&leaf.private_key.secret_bytes());
    Ok(Zeroizing::new(bytes))
}

/// BIP84 path in canonical text form, e.g. `m/84'/1'/0'/1/7`.
pub fn format_path(coin_type: u32, account: u32, branch: u32, index: u32) -> String {
    format!("m/84'/{coin_type}'/{account}'/{branch}/{index}")
}
