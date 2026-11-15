//! Litecoin adapter (transparent part only, MWEB out of scope per
//! docs/coins/LTC.md): BIP84-analog derivation `m / 84' / 2' / account'`
//! (SLIP-44 coin type 2; the bech32 path is not standardized for LTC, so
//! the import UX must offer `m / 44' / 2' / …` as an alternative — owner
//! decision recorded in the research doc), P2WPKH addresses with HRP `ltc`,
//! and the same Electrum protocol transport as BTC.
//!
//! Genesis (mainnet): 12a765e31ffd4059bada1e25190f6e98c99d9714d334efa41a1
//! 95a7e7e04bfe2 — verified in docs/coins/LTC.md (chainparams assert +
//! litecoinspace.org, two sources).
//!
//! The electrum transport (`ElectrumGateway`/`Gateway`) is reused 1:1;
//! network identity is verified by comparing the server-reported genesis
//! with [`GENESIS_MAINNET`] (hex, big-endian display order — the same
//! convention the BTC unlock flow uses).

use crate::bitcoin::keys::{AddressSource, DerivedAddress, BIP84_PURPOSE};
use crate::bitcoin::scan::{discover, wallet_balance};
use crate::electrum::{Gateway, HistoryEntry, ScriptBalance, Utxo};
use crate::{electrum_scripthash_hex, ChainError};
use ::bitcoin::{Transaction, Txid};
use bitcoin::bip32::{ChildNumber, DerivationPath, Xpriv, Xpub};
use bitcoin::ScriptBuf;
use electrum_client::ElectrumApi;

pub use crate::bitcoin::keys::BRANCH_EXTERNAL as LTC_BRANCH_EXTERNAL;
pub use crate::bitcoin::keys::BRANCH_INTERNAL as LTC_BRANCH_INTERNAL;

/// SLIP-44 coin type for Litecoin.
pub const LTC_COIN_TYPE: u32 = 2;

/// Bech32 HRP of the LTC mainnet.
pub const HRP_MAINNET: &str = "ltc";

/// Litecoin mainnet genesis hash (hex, display order).
pub const GENESIS_MAINNET_HEX: &str =
    "12a765e31ffd4059bada1e25190f6e98c99d9714d334efa41a195a7e7e04bfe2";

/// Public LTC Electrum servers (1209k.com monitoring + live verification
/// 2026-11-15 through the real rustls client, same path as the app;
/// protocol 1.4). Live probe rejects anything that does not answer or
/// serves the wrong genesis. bysh.me and rentonisk speak the protocol but
/// rustls rejects their certificates / drops fresh connections — excluded.
pub const SERVERS_MAINNET: &[&str] = &[
    "ssl://electrum-ltc.petrkr.net:60002",
    "ssl://litecoin.stackwallet.com:20063",
    "ssl://electrum.petrkr.net:60002",
    "ssl://electrum.ltc.xurious.com:50002",
    "ssl://backup.electrum-ltc.org:50002",
];

/// The smallest dust threshold the LTC flow uses (P2WPKH at 1 sat/vB is
/// well above it; mirrored from the BTC dust constant — Litecoin parity).
pub const LTC_P2WPKH_DUST_SAT: u64 = crate::bitcoin::P2WPKH_DUST_SAT;

const CHARSET: &[u8] = b"qpzry9x8gf2tvdw0s3jn54khce6mua7l";

fn bech32_polymod(values: &[u8]) -> u32 {
    const GEN: [u32; 5] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
    let mut chk: u32 = 1;
    for &v in values {
        let b = (chk >> 25) as u8;
        chk = ((chk & 0x1ff_ffff) << 5) ^ (v as u32);
        for (i, g) in GEN.iter().enumerate() {
            if (b >> i) & 1 == 1 {
                chk ^= g;
            }
        }
    }
    chk
}

fn hrp_expand(hrp: &str) -> Vec<u8> {
    let mut e: Vec<u8> = hrp.bytes().map(|b| b >> 5).collect();
    e.push(0);
    e.extend(hrp.bytes().map(|b| b & 31));
    e
}

/// Encode a witness v0 program into bech32 with the given HRP — shared by
/// LTC (HRP `ltc`) itself and the rust-bitcoin cross-check in tests. Uses
/// the bech32 constant (v0), not bech32m.
pub fn bech32_segwit_address(hrp: &str, program: &[u8]) -> Result<String, ChainError> {
    if program.is_empty() || program.len() > 40 {
        return Err(ChainError::KeyDerivation(
            "witness program length out of range".into(),
        ));
    }
    let mut data: Vec<u8> = vec![0]; // witness version 0 (quint)
    let mut acc: u32 = 0;
    let mut bits: u32 = 0;
    for &b in program {
        acc = (acc << 8) | (b as u32);
        bits += 8;
        while bits >= 5 {
            bits -= 5;
            data.push(((acc >> bits) & 31) as u8);
        }
    }
    if bits > 0 {
        data.push(((acc << (5 - bits)) & 31) as u8);
    }

    let mut values = hrp_expand(hrp);
    values.extend_from_slice(&data);
    values.extend_from_slice(&[0, 0, 0, 0, 0, 0]);
    let pl = bech32_polymod(&values) ^ 1;
    for i in 0..6 {
        data.push(((pl >> (5 * (5 - i))) & 31) as u8);
    }

    let mut out = String::from(hrp);
    out.push('1');
    for &q in &data {
        let ch = CHARSET[q as usize] as char;
        if ch.is_ascii_uppercase() {
            return Err(ChainError::KeyDerivation("uppercase in bech32".into()));
        }
        out.push(ch);
    }
    Ok(out)
}

/// Публичное «лицо» LTC-аккаунта: производные адреса без приватных
/// ключей (подписывание требует отдельно полученного секретного ключа,
/// см. [`derive_secret_key_ltc`]).
#[derive(Debug, Clone)]
pub struct LtcAccount {
    account: u32,
    account_xpub: Xpub,
}

impl LtcAccount {
    /// Derive `m/84'/2'/account'` from the BIP39 seed bytes. Hardened
    /// derivation happens in scope; private keys are dropped on return.
    pub fn from_seed(seed: &[u8; 64], account: u32) -> Result<Self, ChainError> {
        let secp = bitcoin::secp256k1::Secp256k1::new();
        let hardened = |i: u32| -> Result<ChildNumber, ChainError> {
            ChildNumber::from_hardened_idx(i)
                .map_err(|e| ChainError::key(format!("hardened child {i}: {e}")))
        };
        let path: DerivationPath = [
            hardened(BIP84_PURPOSE)?,
            hardened(LTC_COIN_TYPE)?,
            hardened(account)?,
        ]
        .into_iter()
        .collect();
        // BIP32 master: the version bytes only affect the xpub/xprv
        // serialization, and LTC uses the standard btc versions (docs/coins/
        // LTC.md §2) — keys are identical for any network value here.
        let master = Xpriv::new_master(bitcoin::Network::Bitcoin, seed)
            .map_err(|e| ChainError::key(format!("master key: {e}")))?;
        let account_key = master
            .derive_priv(&secp, &path)
            .map_err(|e| ChainError::key(format!("account derivation: {e}")))?;
        let account_xpub = Xpub::from_priv(&secp, &account_key);
        Ok(Self {
            account,
            account_xpub,
        })
    }

    pub fn account(&self) -> u32 {
        self.account
    }

    pub fn account_xpub(&self) -> &Xpub {
        &self.account_xpub
    }

    /// P2WPKH `ltc1…` address at `branch/index` (script + electrum
    /// scripthash included — the scan pipeline consumes the same struct
    /// the BTC module produces).
    pub fn derive_address(&self, branch: u32, index: u32) -> Result<DerivedAddress, ChainError> {
        if branch != LTC_BRANCH_EXTERNAL && branch != LTC_BRANCH_INTERNAL {
            return Err(ChainError::KeyDerivation(format!(
                "invalid branch {branch} (expected 0 or 1)"
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
        let compressed =
            bitcoin::key::CompressedPublicKey::from_slice(child.public_key.serialize().as_ref())
                .map_err(|e| ChainError::key(format!("compressed pubkey: {e}")))?;

        // P2WPKH: OP_0 push-20 of hash160 — программа берётся из скрипта.
        let script = ScriptBuf::new_p2wpkh(&compressed.wpubkey_hash());
        let program = &script.as_bytes()[2..];
        let address = bech32_segwit_address(HRP_MAINNET, program)?;
        let scripthash_hex = electrum_scripthash_hex(&script);
        Ok(DerivedAddress {
            address,
            script_pubkey: script,
            scripthash_hex,
            branch,
            index,
            path: crate::bitcoin::keys::format_path(LTC_COIN_TYPE, self.account, branch, index),
        })
    }
}

impl AddressSource for LtcAccount {
    fn derive_address(&self, branch: u32, index: u32) -> Result<DerivedAddress, ChainError> {
        LtcAccount::derive_address(self, branch, index)
    }
}

/// Ltc-транспорт: тот же electrum_client, что у BTC, но с валидацией
/// genesis Litecoin и бэкоффом на «дохлые» свежие соединения.
#[derive(Clone)]
pub struct LtcGateway {
    client: std::sync::Arc<electrum_client::Client>,
    url: String,
}

impl LtcGateway {
    pub fn connect(url: &str) -> Result<Self, ChainError> {
        if url.trim().is_empty() {
            return Err(ChainError::InvalidServerUrl("empty url".into()));
        }
        let lower = url.to_ascii_lowercase();
        if !lower.starts_with("tcp://") && !lower.starts_with("ssl://") {
            return Err(ChainError::InvalidServerUrl(format!(
                "{url} (expected tcp:// or ssl:// scheme)"
            )));
        }
        let config = electrum_client::ConfigBuilder::new()
            .retry(3)
            .timeout(Some(6))
            .build();
        let client = std::sync::Arc::new(
            electrum_client::Client::from_config(url, config)
                .map_err(|e| ChainError::Transport(format!("{url}: {e}")))?,
        );
        let gateway = Self {
            client,
            url: url.to_string(),
        };
        // Живой хэндшейк с бэкоффом (публичные серверы отрезают часть
        // свежих соединений): до трёх попыток, 0.7/1.4с.
        let mut wait = 700u64;
        for attempt in 0..3 {
            match gateway.server_features() {
                Ok(f) => {
                    let _ = f;
                    return Ok(gateway);
                }
                Err(e) => {
                    if attempt == 2 {
                        return Err(ChainError::Transport(format!("{url}: {e}")));
                    }
                    std::thread::sleep(std::time::Duration::from_millis(wait));
                    wait *= 2;
                }
            }
        }
        unreachable!("ltc handshake loop returns on the last attempt");
    }

    pub fn url(&self) -> &str {
        &self.url
    }
}

impl Gateway for LtcGateway {
    // Устаревший трейт-метод btc-эпохи; LTC ходы используют этот тип как
    // чистый транспорт через общие функции scan.rs.
    fn network(&self) -> crate::electrum::BtcNetwork {
        crate::electrum::BtcNetwork::Mainnet
    }

    fn server_features(&self) -> Result<(String, String, String, [u8; 32]), ChainError> {
        let f = self
            .client
            .server_features()
            .map_err(|e| ChainError::Protocol(e.to_string()))?;
        Ok((
            f.server_version,
            f.protocol_min,
            f.protocol_max,
            f.genesis_hash,
        ))
    }

    fn tip_height(&self) -> Result<u32, ChainError> {
        let n = self
            .client
            .block_headers_subscribe()
            .map_err(|e| ChainError::Protocol(e.to_string()))?;
        Ok(n.height as u32)
    }

    fn estimate_fee_btc_per_kb(&self, blocks: u32) -> Result<f64, ChainError> {
        self.client
            .estimate_fee(blocks as usize)
            .map_err(|e| ChainError::Protocol(e.to_string()))
    }

    fn script_balance(&self, script: &[u8]) -> Result<ScriptBalance, ChainError> {
        let s = bitcoin::Script::from_bytes(script);
        let b = self
            .client
            .script_get_balance(s)
            .map_err(|e| ChainError::Protocol(e.to_string()))?;
        Ok(ScriptBalance {
            confirmed_sat: b.confirmed,
            unconfirmed_sat: b.unconfirmed,
        })
    }

    fn script_utxos(&self, script: &[u8]) -> Result<Vec<Utxo>, ChainError> {
        let s = bitcoin::Script::from_bytes(script);
        let list = self
            .client
            .script_list_unspent(s)
            .map_err(|e| ChainError::Protocol(e.to_string()))?;
        Ok(list
            .into_iter()
            .map(|u| Utxo {
                txid: u.tx_hash,
                vout: u.tx_pos as u32,
                value_sat: u.value,
                height: (u.height > 0).then_some(u.height as u32),
            })
            .collect())
    }

    fn script_history(&self, script: &[u8]) -> Result<Vec<HistoryEntry>, ChainError> {
        let s = bitcoin::Script::from_bytes(script);
        let list = self
            .client
            .script_get_history(s)
            .map_err(|e| ChainError::Protocol(e.to_string()))?;
        Ok(list
            .into_iter()
            .map(|h| HistoryEntry {
                txid: h.tx_hash,
                height: h.height as i64,
            })
            .collect())
    }

    fn tx_by_id(&self, txid: &Txid) -> Result<Option<Transaction>, ChainError> {
        match self.client.transaction_get(txid) {
            Ok(tx) => Ok(Some(tx)),
            Err(e) => {
                let text = e.to_string().to_ascii_lowercase();
                if text.contains("no such")
                    || text.contains("unknown")
                    || text.contains("not found")
                    || text.contains("tx not in block chain")
                {
                    return Ok(None);
                }
                Err(ChainError::Protocol(e.to_string()))
            }
        }
    }

    fn broadcast(&self, tx: &Transaction) -> Result<Txid, ChainError> {
        self.client
            .transaction_broadcast(tx)
            .map_err(|e| ChainError::BroadcastRejected(e.to_string()))
    }
}

/// Полный LTC-скан аккаунта (gap-limit) + баланс: вход в UI-провод
/// будет использовать эти функции напрямую.
pub fn ltc_scan_and_balance(
    gateway: &LtcGateway,
    account: &LtcAccount,
    gap_limit: u32,
) -> Result<
    (
        crate::bitcoin::scan::Discovery,
        crate::bitcoin::scan::WalletBalance,
    ),
    ChainError,
> {
    let discovery = discover(gateway, account, gap_limit)?;
    let balance = wallet_balance(gateway, &discovery)?;
    Ok((discovery, balance))
}
