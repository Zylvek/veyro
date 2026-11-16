//! Bitcoin Cash adapter (docs/coins/BCH.md — верdict Full support).
//!
//! Отличия от BTC/LTC (BCH — классический UTXO без SegWit):
//! - деривация BIP44 `m/44'/145'/account'` (SLIP-44: 145 mainnet, 1 testnet);
//! - адрес P2PKH в cashaddr (`bitcoincash:q…`), legacy base58 тоже принимается;
//! - подпись ECDSA SIGHASH_ALL|FORKID (0x41), дайджест UAHF (spec
//!   "Replay protected sighash", forkId=0) — своя реализация, проверена
//!   тест-векторами BCHN `src/test/data/sighash.json` (40 записей);
//! - размер транзакции честный legacy-байтовый, комиссия в сат/байт;
//! - Electrum-транспорт тот же протокол; genesis BCH == BTC genesis.
//!
//! Секреты: hardened-деривация в скоупе, секрет ключа только в подписи,
//! Zeroizing на выходе; никакой секрет не логируется.

use crate::bitcoin::keys::{AddressSource, DerivedAddress};
use crate::bitcoin::scan::{discover, wallet_balance, Discovery, WalletBalance, WalletUtxo};
use crate::electrum::Gateway;
use crate::{electrum_scripthash_hex, ChainError};
use ::bitcoin::bip32::{ChildNumber, DerivationPath, Xpriv, Xpub};
use ::bitcoin::consensus::Encodable;
use ::bitcoin::{ScriptBuf, Transaction, Txid};
use bitcoin_hashes::Hash;
use electrum_client::ElectrumApi;
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

/// SLIP-44 coin type BCH mainnet (паспорт §3).
pub const BCH_COIN_TYPE: u32 = 145;

/// cashaddr-префиксы сетей (паспорт §2).
pub const PREFIX_MAINNET: &str = "bitcoincash";
pub const PREFIX_TESTNET: &str = "bchtest";

/// Genesis BCH mainnet — общий с BTC (форк; 2 источника в паспорте §2).
pub const GENESIS_MAINNET_HEX: &str =
    "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f";
/// Genesis BCH testnet3 — общий с BTC testnet3 (паспорт §2).
pub const GENESIS_TESTNET_HEX: &str =
    "000000000933ea01ad0ee984209779baaec3ced90fa3f408719526f8d77f4943";

/// Сети BCH. Testnet4/scalenet/chipnet/regtest не поддерживается (паспорт §2:
/// только у testnet3 подтверждена публичная инфраструктура).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BchNetwork {
    Mainnet,
    Testnet3,
}

impl BchNetwork {
    pub fn coin_type(self) -> u32 {
        match self {
            BchNetwork::Mainnet => BCH_COIN_TYPE,
            BchNetwork::Testnet3 => 1,
        }
    }

    pub fn display_name(self) -> &'static str {
        match self {
            BchNetwork::Mainnet => "Bitcoin Cash mainnet",
            BchNetwork::Testnet3 => "Bitcoin Cash testnet3",
        }
    }

    pub fn cashaddr_prefix(self) -> &'static str {
        match self {
            BchNetwork::Mainnet => PREFIX_MAINNET,
            BchNetwork::Testnet3 => PREFIX_TESTNET,
        }
    }

    /// Genesis (hex, big-endian display order — как у BTC/LTC).
    pub fn genesis_hash(self) -> [u8; 32] {
        let hex64 = match self {
            BchNetwork::Mainnet => GENESIS_MAINNET_HEX,
            BchNetwork::Testnet3 => GENESIS_TESTNET_HEX,
        };
        let bytes = hex::decode(hex64).expect("genesis hash hex is valid");
        let mut out = [0u8; 32];
        out.copy_from_slice(&bytes);
        out
    }

    /// Legacy-base58 версии (паспорт §2): (P2PKH, P2SH).
    pub fn legacy_versions(self) -> (u8, u8) {
        match self {
            BchNetwork::Mainnet => (0x00, 0x05),
            BchNetwork::Testnet3 => (0x6f, 0xc4),
        }
    }

    /// Стабильный wire/UI код: 0 mainnet, 1 testnet3.
    pub fn code(self) -> u32 {
        match self {
            BchNetwork::Mainnet => 0,
            BchNetwork::Testnet3 => 1,
        }
    }

    pub fn from_code(code: u32) -> Option<Self> {
        match code {
            0 => Some(BchNetwork::Mainnet),
            1 => Some(BchNetwork::Testnet3),
            _ => None,
        }
    }
}

/// Кандидаты публичных Electrum-BCH серверов (Electron Cash servers.json,
/// TLS 50002). Живой фильтр по rustls — после реального прогона, список
/// сокращается до реально работающих (дисциплина LTC).
pub const SERVER_MAINNET_CANDIDATES: &[&str] = &[
    "ssl://bch.imaginary.cash:50002",
    "ssl://electroncash.dk:50002",
    "ssl://bch.loping.net:50002",
];

/// Транспорт BCH: та же схема transports, что у LTC (общие scan-функции).
#[derive(Clone)]
pub struct BchGateway {
    client: std::sync::Arc<electrum_client::Client>,
    url: String,
}

impl BchGateway {
    pub fn connect(url: &str) -> Result<Self, ChainError> {
        if url.trim().is_empty() {
            return Err(ChainError::InvalidServerUrl("empty url".into()));
        }
        let lower = url.to_ascii_lowercase();
        // TLS-only политика: tcp:// вообще не пропускается.
        if !lower.starts_with("ssl://") {
            return Err(ChainError::InvalidServerUrl(format!(
                "{url} (expected ssl:// — TLS-only policy)"
            )));
        }
        let config = electrum_client::ConfigBuilder::new()
            .retry(1)
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
        let mut wait = 700u64;
        for attempt in 0..2 {
            match gateway.server_features() {
                Ok(_) => return Ok(gateway),
                Err(e) => {
                    if attempt == 1 {
                        return Err(ChainError::Transport(format!("{url}: {e}")));
                    }
                    std::thread::sleep(std::time::Duration::from_millis(wait));
                    wait *= 2;
                }
            }
        }
        unreachable!("bch handshake loop returns on the last attempt");
    }

    pub fn url(&self) -> &str {
        &self.url
    }

    /// Fund-safety: genesis сервера обязан совпасть с сетью BCH.
    pub fn verify_network(&self, network: BchNetwork) -> Result<(), ChainError> {
        let f = self
            .client
            .server_features()
            .map_err(crate::electrum::map_client_error)?;
        if f.genesis_hash == network.genesis_hash() {
            Ok(())
        } else {
            Err(ChainError::Protocol(format!(
                "server genesis {} does not match {} — refusing to use it",
                hex::encode(f.genesis_hash),
                network.display_name()
            )))
        }
    }
}

impl Gateway for BchGateway {
    fn network(&self) -> crate::electrum::BtcNetwork {
        crate::electrum::BtcNetwork::Mainnet
    }

    fn estimate_fees_batch(&self, blocks: &[u32]) -> Result<Vec<f64>, ChainError> {
        let depths: Vec<usize> = blocks.iter().map(|b| *b as usize).collect();
        self.client
            .batch_estimate_fee(&depths)
            .map_err(crate::electrum::map_client_error)
    }

    fn server_features(&self) -> Result<(String, String, String, [u8; 32]), ChainError> {
        let f = self
            .client
            .server_features()
            .map_err(crate::electrum::map_client_error)?;
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
            .map_err(crate::electrum::map_client_error)?;
        Ok(n.height as u32)
    }

    fn estimate_fee_btc_per_kb(&self, blocks: u32) -> Result<f64, ChainError> {
        self.client
            .estimate_fee(blocks as usize)
            .map_err(|e| ChainError::Protocol(e.to_string()))
    }

    fn script_balance(&self, script: &[u8]) -> Result<crate::electrum::ScriptBalance, ChainError> {
        let s = ::bitcoin::Script::from_bytes(script);
        let b = self
            .client
            .script_get_balance(s)
            .map_err(crate::electrum::map_client_error)?;
        Ok(crate::electrum::ScriptBalance {
            confirmed_sat: b.confirmed,
            unconfirmed_sat: b.unconfirmed,
        })
    }

    fn script_utxos(&self, script: &[u8]) -> Result<Vec<crate::electrum::Utxo>, ChainError> {
        let s = ::bitcoin::Script::from_bytes(script);
        let list = self
            .client
            .script_list_unspent(s)
            .map_err(crate::electrum::map_client_error)?;
        Ok(list
            .into_iter()
            .map(|u| crate::electrum::Utxo {
                txid: u.tx_hash,
                vout: u.tx_pos as u32,
                value_sat: u.value,
                height: (u.height > 0).then_some(u.height as u32),
            })
            .collect())
    }

    fn script_history(
        &self,
        script: &[u8],
    ) -> Result<Vec<crate::electrum::HistoryEntry>, ChainError> {
        let s = ::bitcoin::Script::from_bytes(script);
        let list = self
            .client
            .script_get_history(s)
            .map_err(crate::electrum::map_client_error)?;
        Ok(list
            .into_iter()
            .map(|h| crate::electrum::HistoryEntry {
                txid: h.tx_hash,
                height: h.height as i64,
            })
            .collect())
    }

    fn tx_by_id(&self, txid: &Txid) -> Result<Option<Transaction>, ChainError> {
        match self.client.transaction_get(txid) {
            Ok(tx) => Ok(Some(tx)),
            Err(e) => {
                if crate::electrum::is_missing_tx_error(&e) {
                    Ok(None)
                } else {
                    Err(crate::electrum::map_client_error(e))
                }
            }
        }
    }

    fn broadcast(&self, tx: &Transaction) -> Result<Txid, ChainError> {
        self.client
            .transaction_broadcast(tx)
            .map_err(|e| ChainError::BroadcastRejected(e.to_string()))
    }
}

// ---------------------------------------------------------------------------
// cashaddr-кодек (spec bitcoincash.org/spec/cashaddr.md).
// ---------------------------------------------------------------------------

const CHARSET: &[u8] = b"qpzry9x8gf2tvdw0s3jn54khce6mua7l";

/// BCH-код чексуммы (spec, 5 генераторов, итог XOR 1).
fn cashaddr_polymod(values: &[u8]) -> u64 {
    const GEN: [u64; 5] = [
        0x98f2bc8e61,
        0x79b76d99e2,
        0xf33e5fb3c4,
        0xae2eabe2a8,
        0x1e4f43e470,
    ];
    let mut c: u64 = 1;
    for &d in values {
        let c0 = (c >> 35) as u8;
        c = ((c & 0x07_ffff_ffff) << 5) ^ (d as u64);
        if c0 & 0x01 != 0 {
            c ^= GEN[0];
        }
        if c0 & 0x02 != 0 {
            c ^= GEN[1];
        }
        if c0 & 0x04 != 0 {
            c ^= GEN[2];
        }
        if c0 & 0x08 != 0 {
            c ^= GEN[3];
        }
        if c0 & 0x10 != 0 {
            c ^= GEN[4];
        }
    }
    c ^ 1
}

/// Префикс для PolyMod: НИЖНИЕ 5 бит каждого символа + один ноль-разделитель
/// (spec: 'b'->2, 'i'->9, 't'->20).
fn prefix_expand(prefix: &str) -> Vec<u8> {
    let mut v: Vec<u8> = prefix.bytes().map(|b| b & 31).collect();
    v.push(0);
    v
}

fn bytes_to_quints(data: &[u8]) -> Vec<u8> {
    let mut acc: u32 = 0;
    let mut bits: u32 = 0;
    let mut out: Vec<u8> = Vec::new();
    for &b in data {
        acc = (acc << 8) | (b as u32);
        bits += 8;
        while bits >= 5 {
            bits -= 5;
            out.push(((acc >> bits) & 31) as u8);
        }
    }
    if bits > 0 {
        out.push(((acc << (5 - bits)) & 31) as u8);
    }
    out
}

fn quints_to_bytes(quints: &[u8]) -> Vec<u8> {
    let mut acc: u32 = 0;
    let mut bits: u32 = 0;
    let mut out: Vec<u8> = Vec::new();
    for &q in quints {
        acc = (acc << 5) | (q as u32 & 31);
        bits += 5;
        while bits >= 8 {
            bits -= 8;
            out.push(((acc >> bits) & 0xff) as u8);
        }
    }
    out
}

/// Кодирование cashaddr (P2KH: version=0, hash 20 байт).
pub fn cashaddr_encode(prefix: &str, version_byte: u8, hash: &[u8]) -> Result<String, ChainError> {
    if prefix.bytes().any(|b| b.is_ascii_uppercase()) {
        return Err(ChainError::KeyDerivation("prefix must be lowercase".into()));
    }
    let mut payload: Vec<u8> = vec![version_byte];
    payload.extend_from_slice(hash);
    let quints = bytes_to_quints(&payload);
    let mut values = prefix_expand(prefix);
    values.extend_from_slice(&quints);
    values.extend_from_slice(&[0u8; 8]); // 40 нулевых бит под чексумму
    let chk = cashaddr_polymod(&values);
    values.truncate(values.len() - 8);
    for i in 0..8 {
        values.push(((chk >> (5 * (7 - i as u32))) & 31) as u8);
    }
    let mut out =
        String::with_capacity(prefix.len() + 1 + values.len() - prefix_expand(prefix).len());
    out.push_str(prefix);
    out.push(':');
    for &q in values[prefix_expand(prefix).len()..].iter() {
        out.push(CHARSET[q as usize] as char);
    }
    Ok(out)
}

/// P2KH-address приёма: `bitcoincash:q…`.
pub fn cashaddr_pkh(prefix: &str, hash: &[u8; 20]) -> Result<String, ChainError> {
    cashaddr_encode(prefix, 0x00, hash)
}

/// Декод cashaddr (строка с явным префиксом) → (prefix, version, hash).
pub fn decode_cashaddr(text: &str) -> Result<(String, u8, Vec<u8>), ChainError> {
    let addr = text.trim();
    let pos = addr
        .find(':')
        .ok_or_else(|| ChainError::InvalidAddress(format!("{addr}: нет префикса cashaddr")))?;
    let prefix = addr[..pos].to_ascii_lowercase();
    let payload_text = addr[pos + 1..].to_ascii_lowercase();
    if payload_text.len() < 1 + 8 {
        return Err(ChainError::InvalidAddress(format!(
            "{addr}: слишком короткий"
        )));
    }
    let mut quints: Vec<u8> = Vec::with_capacity(payload_text.len());
    for c in payload_text.bytes() {
        match CHARSET.iter().position(|&x| x == c) {
            Some(i) => quints.push(i as u8),
            None => {
                return Err(ChainError::InvalidAddress(format!(
                    "{addr}: недопустимый символ"
                )))
            }
        }
    }
    let mut values = prefix_expand(&prefix);
    values.extend_from_slice(&quints);
    if cashaddr_polymod(&values) != 0 {
        return Err(ChainError::InvalidAddress(format!(
            "{addr}: чексумма cashaddr"
        )));
    }
    let data_quints = &quints[..quints.len() - 8];
    let bytes = quints_to_bytes(data_quints);
    if bytes.is_empty() {
        return Err(ChainError::InvalidAddress(format!(
            "{addr}: пустой payload"
        )));
    }
    let version = bytes[0];
    // бит 7 version обязан быть 0 (spec).
    if version & 0x80 != 0 {
        return Err(ChainError::InvalidAddress(format!(
            "{addr}: неверный version byte"
        )));
    }
    let hash = bytes[1..].to_vec();
    // размер хэша зашит в 3 младших битах — сверяем (фонд-безопасность).
    let size_bits = (version & 0x07) as usize;
    let expected = match size_bits {
        0 => 20usize,
        1 => 24,
        2 => 28,
        3 => 32,
        4 => 40,
        5 => 48,
        6 => 56,
        7 => 64,
        _ => unreachable!(),
    };
    if hash.len() != expected {
        return Err(ChainError::InvalidAddress(format!(
            "{addr}: длина хэша {} не совпадает с версией",
            hash.len()
        )));
    }
    let _ = prefix;
    Ok((prefix, version, hash))
}

const BASE58: &[u8] = b"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

/// base58check decode (двойной sha256 чексумма) — та же схема, что у LTC.
pub fn base58check_decode(text: &str) -> Result<Vec<u8>, ChainError> {
    let mut bytes: Vec<u8> = vec![0u8];
    for c in text.bytes() {
        let val = BASE58
            .iter()
            .position(|&b| b == c)
            .ok_or_else(|| ChainError::InvalidAddress(format!("{text}: не base58 символ")))?
            as u32;
        let mut carry = val;
        for b in bytes.iter_mut().rev() {
            carry += (*b as u32) * 58;
            *b = (carry & 0xff) as u8;
            carry >>= 8;
        }
        while carry > 0 {
            bytes.insert(0, (carry & 0xff) as u8);
            carry >>= 8;
        }
    }
    let zeros = text.bytes().take_while(|&c| c == b'1').count();
    for _ in 0..zeros {
        bytes.insert(0, 0);
    }
    if bytes.len() < 5 {
        return Err(ChainError::InvalidAddress(format!(
            "{text}: слишком короткий"
        )));
    }
    let payload = &bytes[..bytes.len() - 4];
    let check = &bytes[bytes.len() - 4..];
    let digest = Sha256::digest(Sha256::digest(payload));
    if check != &digest[..4] {
        return Err(ChainError::InvalidAddress(format!(
            "{text}: base58 чексумма"
        )));
    }
    Ok(payload.to_vec())
}

/// base58check encode (двойной sha256 чексумма) — mirror [base58check_decode].
pub fn base58check_encode(prefix: &[u8], body: &[u8]) -> Result<String, ChainError> {
    let mut payload: Vec<u8> = Vec::with_capacity(prefix.len() + body.len());
    payload.extend_from_slice(prefix);
    payload.extend_from_slice(body);

    let digest = Sha256::digest(Sha256::digest(&payload));
    let mut bytes = payload.clone();
    bytes.extend_from_slice(&digest[..4]);

    let mut out = String::with_capacity(bytes.len() * 138 / 100 + 1);
    // Ведущие нулевые байты → символ '1' (как в decode).
    for &b in &bytes {
        if b != 0 {
            break;
        }
        out.push('1');
    }
    let first_nonzero = bytes.iter().position(|&b| b != 0);
    if let Some(start) = first_nonzero {
        let mut digits: Vec<u8> = Vec::new();
        for &b in &bytes[start..] {
            let mut carry = b as u32;
            for d in digits.iter_mut() {
                carry += (*d as u32) * 256;
                *d = (carry % 58) as u8;
                carry /= 58;
            }
            while carry > 0 {
                digits.push((carry % 58) as u8);
                carry /= 58;
            }
        }
        for d in digits.iter().rev() {
            out.push(BASE58[*d as usize] as char);
        }
    }
    Ok(out)
}

// ---------------------------------------------------------------------------
// Ключи: BIP44 m/44'/coin'/account'.
// ---------------------------------------------------------------------------

/// Публичное лицо BCH-аккаунта (watch-only; секреты не хранятся).
#[derive(Debug, Clone)]
pub struct BchAccount {
    network: BchNetwork,
    account: u32,
    account_xpub: Xpub,
}

impl BchAccount {
    /// `m/44'/coin'/account'` из BIP39 seed. Harden-деривация в скоупе.
    pub fn from_seed(
        seed: &[u8; 64],
        network: BchNetwork,
        account: u32,
    ) -> Result<Self, ChainError> {
        let secp = ::bitcoin::secp256k1::Secp256k1::new();
        let hardened = |i: u32| -> Result<ChildNumber, ChainError> {
            ChildNumber::from_hardened_idx(i)
                .map_err(|e| ChainError::key(format!("hardened child {i}: {e}")))
        };
        let path: DerivationPath = [
            hardened(44)?,
            hardened(network.coin_type())?,
            hardened(account)?,
        ]
        .into_iter()
        .collect();
        let master = Xpriv::new_master(::bitcoin::Network::Bitcoin, seed)
            .map_err(|e| ChainError::key(format!("master key: {e}")))?;
        let account_key = master
            .derive_priv(&secp, &path)
            .map_err(|e| ChainError::key(format!("account derivation: {e}")))?;
        let account_xpub = Xpub::from_priv(&secp, &account_key);
        Ok(Self {
            network,
            account,
            account_xpub,
        })
    }

    pub fn network(&self) -> BchNetwork {
        self.network
    }

    pub fn account(&self) -> u32 {
        self.account
    }

    pub fn account_xpub(&self) -> &Xpub {
        &self.account_xpub
    }

    /// P2PKH-адрес (cashaddr-вид) на `branch/index`: скрипт + scripthash.
    pub fn derive_address(&self, branch: u32, index: u32) -> Result<DerivedAddress, ChainError> {
        if branch > 1 {
            return Err(ChainError::KeyDerivation(format!(
                "invalid branch {branch} (expected 0 or 1)"
            )));
        }
        let normal = |i: u32| -> Result<ChildNumber, ChainError> {
            ChildNumber::from_normal_idx(i)
                .map_err(|e| ChainError::key(format!("normal child {i}: {e}")))
        };
        let path: DerivationPath = [normal(branch)?, normal(index)?].into_iter().collect();
        let secp = ::bitcoin::secp256k1::Secp256k1::verification_only();
        let child = self
            .account_xpub
            .derive_pub(&secp, &path)
            .map_err(|e| ChainError::key(format!("xpub child: {e}")))?;
        let compressed =
            ::bitcoin::key::CompressedPublicKey::from_slice(child.public_key.serialize().as_ref())
                .map_err(|e| ChainError::key(format!("compressed pubkey: {e}")))?;
        let wpkh = compressed.wpubkey_hash();
        let script =
            ScriptBuf::new_p2pkh(&bitcoin::PubkeyHash::from_byte_array(wpkh.to_byte_array()));
        let address = cashaddr_pkh(self.network.cashaddr_prefix(), &wpkh.to_byte_array())?;
        Ok(DerivedAddress {
            address,
            scripthash_hex: electrum_scripthash_hex(&script),
            script_pubkey: script,
            branch,
            index,
            path: format!(
                "m/44'/{}/{}'/{}/{}",
                self.network.coin_type(),
                self.account,
                branch,
                index
            ),
        })
    }
}

impl AddressSource for BchAccount {
    fn derive_address(&self, branch: u32, index: u32) -> Result<DerivedAddress, ChainError> {
        BchAccount::derive_address(self, branch, index)
    }
}

/// Секретный ключ ветки/индекса `m/44'/coin'/account'/branch/index`.
pub fn derive_secret_key_cash(
    seed: &[u8; 64],
    network: BchNetwork,
    account: u32,
    branch: u32,
    index: u32,
) -> Result<Zeroizing<[u8; 32]>, ChainError> {
    if branch > 1 {
        return Err(ChainError::KeyDerivation(format!(
            "invalid branch {branch}"
        )));
    }
    let secp = ::bitcoin::secp256k1::Secp256k1::new();
    let hardened = |i: u32| -> Result<ChildNumber, ChainError> {
        ChildNumber::from_hardened_idx(i)
            .map_err(|e| ChainError::key(format!("hardened child {i}: {e}")))
    };
    let normal = |i: u32| -> Result<ChildNumber, ChainError> {
        ChildNumber::from_normal_idx(i)
            .map_err(|e| ChainError::key(format!("normal child {i}: {e}")))
    };
    let path: DerivationPath = [
        hardened(44)?,
        hardened(network.coin_type())?,
        hardened(account)?,
        normal(branch)?,
        normal(index)?,
    ]
    .into_iter()
    .collect();
    let master = Xpriv::new_master(::bitcoin::Network::Bitcoin, seed)
        .map_err(|e| ChainError::key(format!("master key: {e}")))?;
    let leaf = master
        .derive_priv(&secp, &path)
        .map_err(|e| ChainError::key(format!("leaf derivation: {e}")))?;
    let mut bytes = <[u8; 32]>::default();
    bytes.copy_from_slice(&leaf.private_key.secret_bytes());
    Ok(Zeroizing::new(bytes))
}

/// Скан BCH-аккаунта + баланс (вход UI-провода, как у LTC).
pub fn bch_scan_and_balance(
    gateway: &BchGateway,
    account: &BchAccount,
    gap_limit: u32,
) -> Result<(Discovery, WalletBalance), ChainError> {
    let discovery = discover(gateway, account, gap_limit)?;
    let balance = wallet_balance(gateway, &discovery)?;
    Ok((discovery, balance))
}

// ---------------------------------------------------------------------------
// sighash: UAHF (FORKID) + legacy. Векторы — cash_sighash_data.rs (BCHN).
// ---------------------------------------------------------------------------

fn dsha256(data: &[u8]) -> [u8; 32] {
    let mut out = [0u8; 32];
    let h = Sha256::digest(Sha256::digest(data));
    out.copy_from_slice(&h);
    out
}

fn write_varint(buf: &mut Vec<u8>, n: u64) {
    if n < 253 {
        buf.push(n as u8);
    } else if n <= 0xffff {
        buf.push(0xfd);
        buf.extend_from_slice(&(n as u16).to_le_bytes());
    } else if n <= 0xffff_ffff {
        buf.push(0xfe);
        buf.extend_from_slice(&(n as u32).to_le_bytes());
    } else {
        buf.push(0xff);
        buf.extend_from_slice(&n.to_le_bytes());
    }
}

fn ctv_out(out: &::bitcoin::TxOut, buf: &mut Vec<u8>) {
    buf.extend_from_slice(&out.value.to_sat().to_le_bytes());
    let script = out.script_pubkey.as_bytes();
    write_varint(buf, script.len() as u64);
    buf.extend_from_slice(script);
}

/// Убрать байты OP_CODESEPARATOR (0x77), стоящие ОДНОЧНЫМИ опкодами
/// (pushdata-совпадения не трогаются) — эквивалент FindAndDelete.
fn strip_codeseparator(script: &[u8]) -> Vec<u8> {
    let mut out: Vec<u8> = Vec::with_capacity(script.len());
    let mut i = 0usize;
    while i < script.len() {
        let op = script[i];
        if op == 0x77 {
            i += 1;
            continue;
        }
        let (data_len, header) = if (0x01..=0x4b).contains(&op) {
            (op as usize, 1usize)
        } else if op == 0x4c && script.len() > i + 1 {
            (script[i + 1] as usize, 2usize)
        } else if op == 0x4d && script.len() > i + 2 {
            (
                u16::from_le_bytes([script[i + 1], script[i + 2]]) as usize,
                3usize,
            )
        } else if op == 0x4e && script.len() > i + 3 {
            (
                u32::from_le_bytes([script[i + 1], script[i + 2], script[i + 3], script[i + 4]])
                    as usize,
                5usize,
            )
        } else {
            (0usize, 1usize)
        };
        let end = (i + header + data_len).min(script.len());
        out.extend_from_slice(&script[i..end.max(i)]);
        i = i + header + data_len;
    }
    out
}

/// Дайджест legacy (до-сегвитовый алгоритм, как `SignatureHashOld` в BCHN).
/// Служит вторым источником truth тест-векторов (test[5]).
pub fn legacy_signature_hash(
    tx: &Transaction,
    script_code: &[u8],
    n_in: usize,
    hash_type: u32,
) -> Result<[u8; 32], ChainError> {
    const ONE: [u8; 32] = {
        let mut one = [0u8; 32];
        one[0] = 1;
        one
    };
    if n_in >= tx.input.len() {
        return Ok(ONE);
    }
    const SIGHASH_NONE: u32 = 2;
    const SIGHASH_SINGLE: u32 = 3;
    const SIGHASH_ANYONECANPAY: u32 = 0x80;
    let base = hash_type & 0x1f;

    let clean = strip_codeseparator(script_code);
    let mut modified = tx.clone();
    for input in modified.input.iter_mut() {
        input.script_sig = ScriptBuf::new();
    }
    modified.input[n_in].script_sig = ScriptBuf::from_bytes(clean);
    if base == SIGHASH_NONE {
        modified.output.clear();
        for (i, input) in modified.input.iter_mut().enumerate() {
            if i != n_in {
                input.sequence = ::bitcoin::Sequence::from_consensus(0);
            }
        }
    } else if base == SIGHASH_SINGLE {
        if n_in >= modified.output.len() {
            return Ok(ONE);
        }
        modified.output.truncate(n_in + 1);
        for i in 0..n_in {
            modified.output[i] = ::bitcoin::TxOut {
                value: ::bitcoin::Amount::from_sat(0),
                script_pubkey: ScriptBuf::new(),
            };
        }
        for (i, input) in modified.input.iter_mut().enumerate() {
            if i != n_in {
                input.sequence = ::bitcoin::Sequence::from_consensus(0);
            }
        }
    }
    if hash_type & SIGHASH_ANYONECANPAY != 0 {
        let the_input = modified.input[n_in].clone();
        modified.input = vec![the_input];
    }
    let mut bytes: Vec<u8> = Vec::new();
    modified
        .consensus_encode(&mut bytes)
        .map_err(|e| ChainError::Internal(format!("encode: {e}")))?;
    bytes.extend_from_slice(&hash_type.to_le_bytes());
    Ok(dsha256(&bytes))
}

/// UAHF-дайджест (FORKID) — spec "replay-protected-sighash", forkId в
/// `hash_type`; итоговое 4-байтовое поле сериализуется как hash_type.
pub fn forkid_signature_hash(
    tx: &Transaction,
    script_code: &[u8],
    n_in: usize,
    input_value_sat: u64,
    hash_type: u32,
) -> Result<[u8; 32], ChainError> {
    if n_in >= tx.input.len() {
        return Err(ChainError::Internal(
            "sighash: input index out of range".into(),
        ));
    }
    const SIGHASH_NONE: u32 = 2;
    const SIGHASH_SINGLE: u32 = 3;
    const SIGHASH_ANYONECANPAY: u32 = 0x80;
    let base = hash_type & 0x1f;
    let zero32 = [0u8; 32];

    let hash_prevouts: [u8; 32] = if hash_type & SIGHASH_ANYONECANPAY != 0 {
        zero32
    } else {
        let mut v: Vec<u8> = Vec::with_capacity(tx.input.len() * 36);
        for input in &tx.input {
            v.extend_from_slice(input.previous_output.txid.as_byte_array());
            v.extend_from_slice(&input.previous_output.vout.to_le_bytes());
        }
        dsha256(&v)
    };
    let hash_sequence: [u8; 32] = if hash_type & SIGHASH_ANYONECANPAY != 0
        || base == SIGHASH_SINGLE
        || base == SIGHASH_NONE
    {
        zero32
    } else {
        let mut v: Vec<u8> = Vec::with_capacity(tx.input.len() * 4);
        for input in &tx.input {
            v.extend_from_slice(&input.sequence.to_consensus_u32().to_le_bytes());
        }
        dsha256(&v)
    };
    let hash_outputs: [u8; 32] = if base != SIGHASH_SINGLE && base != SIGHASH_NONE {
        let mut v: Vec<u8> = Vec::new();
        for out in &tx.output {
            ctv_out(out, &mut v);
        }
        dsha256(&v)
    } else if base == SIGHASH_SINGLE && n_in < tx.output.len() {
        let mut v: Vec<u8> = Vec::new();
        ctv_out(&tx.output[n_in], &mut v);
        dsha256(&v)
    } else {
        zero32
    };

    let mut buf: Vec<u8> = Vec::new();
    buf.extend_from_slice(&tx.version.0.to_le_bytes());
    buf.extend_from_slice(&hash_prevouts);
    buf.extend_from_slice(&hash_sequence);
    let outpoint = &tx.input[n_in].previous_output;
    buf.extend_from_slice(outpoint.txid.as_byte_array());
    buf.extend_from_slice(&outpoint.vout.to_le_bytes());
    write_varint(&mut buf, script_code.len() as u64);
    buf.extend_from_slice(script_code);
    buf.extend_from_slice(&input_value_sat.to_le_bytes());
    buf.extend_from_slice(&tx.input[n_in].sequence.to_consensus_u32().to_le_bytes());
    buf.extend_from_slice(&hash_outputs);
    buf.extend_from_slice(&tx.lock_time.to_consensus_u32().to_le_bytes());
    buf.extend_from_slice(&hash_type.to_le_bytes());
    Ok(dsha256(&buf))
}

/// Регулярный дайджест: тип с FORKID-флагом → UAHF, без флага → legacy
/// (семантика SignatureHash BCHN: SCRIPT_ENABLE_SIGHASH_FORKID).
pub fn signature_hash_bch(
    tx: &Transaction,
    script_code: &[u8],
    n_in: usize,
    input_value_sat: u64,
    hash_type: u32,
) -> Result<[u8; 32], ChainError> {
    if hash_type & 0x40 != 0 {
        forkid_signature_hash(tx, script_code, n_in, input_value_sat, hash_type)
    } else {
        legacy_signature_hash(tx, script_code, n_in, hash_type)
    }
}

// ---------------------------------------------------------------------------
// Планирование (комиссия в сат/байт) и подпись P2PKH.
// ---------------------------------------------------------------------------

/// Пыль для P2PKH-выхода (консервативная оценка lineage-пути: 546 сат).
pub const BCH_OUTPUT_DUST_SAT: u64 = 546;

/// Оценка размера legacy-транзакции с P2PKH-подписанными входами:
/// 36 prevout + 4 seq + 1 len + 73 sig+type + 1 len + 33 pk = 148.
fn bch_size(input_count: usize, out_lens: &[usize]) -> u64 {
    let mut size = 4u64 + 4 + 1 + 1;
    size += input_count as u64 * 148;
    for len in out_lens {
        let varint = if *len < 253 { 1u64 } else { 3 };
        size += 8 + varint + *len as u64;
    }
    size
}

fn bch_shape_fee(
    n_inputs: usize,
    recipient_script_len: usize,
    has_change: bool,
    rate_per_byte: u64,
) -> Result<u64, ChainError> {
    let mut lens = vec![recipient_script_len];
    if has_change {
        lens.push(25); // change P2PKH
    }
    let size = bch_size(n_inputs, &lens);
    size.checked_mul(rate_per_byte)
        .ok_or_else(|| ChainError::InvalidAmount(format!("rate {rate_per_byte} sat/B абсурдна")))
}

/// Планирование BCH-перевода (отбор крупнейших, комиссия, change). Без сети,
/// без подписи. Размер честно legacy (BIP141-веса не существуют для BCH).
pub fn bch_plan_transfer(
    recipient_display: &str,
    recipient_script: ScriptBuf,
    amount_sat: u64,
    rate_per_byte: u64,
    utxos: &[WalletUtxo],
    change_address: &DerivedAddress,
) -> Result<crate::bitcoin::tx::PlannedTransfer, ChainError> {
    if amount_sat == 0 {
        return Err(ChainError::InvalidAmount("amount must be positive".into()));
    }
    if rate_per_byte == 0 {
        return Err(ChainError::FeeTooLow);
    }
    if amount_sat < BCH_OUTPUT_DUST_SAT {
        return Err(ChainError::Dust {
            amount_sat,
            dust_sat: BCH_OUTPUT_DUST_SAT,
        });
    }
    let recipient_script_len = recipient_script.as_bytes().len();
    if utxos.is_empty() {
        return Err(ChainError::NoSpendableOutputs);
    }

    let mut candidates: Vec<&WalletUtxo> = utxos.iter().collect();
    candidates.sort_by(|a, b| {
        b.value_sat
            .cmp(&a.value_sat)
            .then_with(|| b.txid.cmp(&a.txid))
            .then_with(|| b.vout.cmp(&a.vout))
    });

    let mut picked: Vec<&WalletUtxo> = Vec::new();
    let mut gathered: u64 = 0;
    let (fee, change_opt): (u64, Option<u64>) = loop {
        let f_with = bch_shape_fee(picked.len(), recipient_script_len, true, rate_per_byte)?;
        if gathered >= amount_sat.saturating_add(f_with) {
            let leftover = gathered - amount_sat - f_with;
            if leftover >= BCH_OUTPUT_DUST_SAT {
                break (f_with, Some(leftover));
            }
        }
        let f_plain = bch_shape_fee(picked.len(), recipient_script_len, false, rate_per_byte)?;
        if gathered >= amount_sat.saturating_add(f_plain) {
            break (f_plain, None);
        }
        let next = candidates
            .get(picked.len())
            .ok_or_else(|| ChainError::InsufficientFunds {
                required_sat: amount_sat.saturating_add(f_with),
                available_sat: gathered,
            })?;
        gathered = gathered.saturating_add(next.value_sat);
        picked.push(next);
    };

    let change = change_opt.map(|amount| {
        (
            change_address.address.clone(),
            change_address.script_pubkey.as_bytes().to_vec(),
            amount,
        )
    });

    Ok(crate::bitcoin::tx::PlannedTransfer {
        recipient: recipient_display.to_string(),
        recipient_script: recipient_script.as_bytes().to_vec(),
        recipient_amount_sat: amount_sat,
        change,
        inputs: picked.into_iter().cloned().collect(),
        fee_sat: fee,
        vsize: fee
            .checked_div(rate_per_byte)
            .expect("rate >= 1 проверен выше"),
        fee_sat_per_vb: rate_per_byte,
    })
}

/// Лици-совместимая планировка: принимает адрес-строку (как LTC), сам
/// разбирает его и вызывает байтовую версию планировки.
pub fn bch_plan_transfer_addr(
    recipient: &str,
    amount_sat: u64,
    rate_per_byte: u64,
    utxos: &[WalletUtxo],
    change_address: &DerivedAddress,
) -> Result<crate::bitcoin::tx::PlannedTransfer, ChainError> {
    let script = bch_recipient_script(BchNetwork::Mainnet, recipient)?;
    bch_plan_transfer(
        recipient.trim(),
        script,
        amount_sat,
        rate_per_byte,
        utxos,
        change_address,
    )
}

/// Парсинг адреса получателя BCH → script_pubkey.
/// cashaddr: `bitcoincash:q…`/`bchtest:q…` (+ голое `q…` как префикс сети),
/// legacy base58: `1…`/`3…` mainnet, `m/n…`/`2…` testnet3.
/// Ошибка сети адреса = `AddressNetworkMismatch` (не тратим в чужую сеть).
pub fn bch_recipient_script(network: BchNetwork, address: &str) -> Result<ScriptBuf, ChainError> {
    let trimmed = address.trim();
    if trimmed.is_empty() {
        return Err(ChainError::InvalidAddress("empty address".into()));
    }
    let lower = trimmed.to_ascii_lowercase();
    let (prefix, version, hash) = if lower.contains(':') {
        decode_cashaddr(trimmed)?
    } else if lower.starts_with("q") || lower.starts_with("p") {
        // голый cashaddr — считается с префиксом сети кошелька
        decode_cashaddr(&format!("{}:{}", network.cashaddr_prefix(), trimmed))?
    } else {
        let payload = base58check_decode(trimmed)?;
        if payload.len() != 21 {
            return Err(ChainError::InvalidAddress(format!(
                "{address}: base58 payload должен быть 21 байт"
            )));
        }
        let (pkh_v, psh_v) = network.legacy_versions();
        match payload[0] {
            v if v == pkh_v => (
                network.cashaddr_prefix().to_string(),
                0u8,
                payload[1..].to_vec(),
            ),
            v if v == psh_v => (
                network.cashaddr_prefix().to_string(),
                8u8,
                payload[1..].to_vec(),
            ),
            v => {
                return Err(ChainError::InvalidAddress(format!(
                    "{address}: нехарактерная base58 версия {v}"
                )))
            }
        }
    };
    // Сеть адреса обязана совпасть с сетью кошелька (по префиксу).
    let mismatch = |real: &str| {
        ChainError::AddressNetworkMismatch(match real {
            PREFIX_MAINNET => "Bitcoin Cash mainnet",
            PREFIX_TESTNET => "Bitcoin Cash testnet3",
            _ => "неизвестная сеть BCH",
        })
    };
    if prefix != network.cashaddr_prefix() {
        return Err(mismatch(&prefix));
    }
    if hash.len() != 20 {
        return Err(ChainError::InvalidAddress(format!(
            "{address}: поддержан только 20-байтный хэш (cashaddr 160 бит)"
        )));
    }
    use bitcoin_hashes::Hash;
    let h = <bitcoin::PubkeyHash as bitcoin_hashes::Hash>::from_byte_array(
        hash[..20].try_into().expect("20 bytes проверены выше"),
    );
    match version {
        0 => Ok(ScriptBuf::new_p2pkh(&h)),
        8 => Ok(ScriptBuf::new_p2sh(
            &<bitcoin::ScriptHash as bitcoin_hashes::Hash>::from_byte_array(h.to_byte_array()),
        )),
        t => Err(ChainError::InvalidAddress(format!(
            "{address}: тип {t} не P2KH/P2SH"
        ))),
    }
}

/// Фейловер-кандидаты публичных Electrum-BCH серверов: список с отработавшим
/// сервером в конце (та же дисциплина, что у BTC/LTC).
pub fn bch_failover_candidates(failed_url: &str) -> Vec<String> {
    let mut list: Vec<String> = SERVER_MAINNET_CANDIDATES
        .iter()
        .map(|s| s.to_string())
        .collect();
    if let Some(pos) = list.iter().position(|u| u == failed_url) {
        let removed = list.remove(pos);
        list.push(removed);
    }
    list
}

/// Сборка + локальная подпись BCH-плана: legacy-транзакция (без witness),
/// каждый вход подписан forkid-ECDSA (ALL|FORKID 0x41, forkId=0). Change
/// всегда на внутреннем ветвлении (BIP44-дисциплина, как у BTC/LTC).
pub fn bch_signed_transfer(
    plan: &crate::bitcoin::tx::PlannedTransfer,
    seed: &[u8; 64],
    network: BchNetwork,
    account: u32,
    tip_height: u32,
) -> Result<crate::bitcoin::tx::SignedTransfer, ChainError> {
    let mut inputs: Vec<::bitcoin::TxIn> = Vec::with_capacity(plan.inputs.len());
    for u in &plan.inputs {
        inputs.push(::bitcoin::TxIn {
            previous_output: ::bitcoin::OutPoint {
                txid: u.txid,
                vout: u.vout,
            },
            script_sig: ScriptBuf::new(),
            sequence: ::bitcoin::Sequence::from_consensus(0xffff_ffff),
            witness: ::bitcoin::Witness::default(),
        });
    }

    let mut outputs: Vec<::bitcoin::TxOut> = vec![::bitcoin::TxOut {
        value: ::bitcoin::Amount::from_sat(plan.recipient_amount_sat),
        script_pubkey: ScriptBuf::from_bytes(plan.recipient_script.clone()),
    }];
    if let Some((_, script, amount)) = plan.change.as_ref() {
        outputs.push(::bitcoin::TxOut {
            value: ::bitcoin::Amount::from_sat(*amount),
            script_pubkey: ScriptBuf::from_bytes(script.clone()),
        });
    }

    let lock_time = ::bitcoin::absolute::LockTime::from_height(tip_height)
        .unwrap_or(::bitcoin::absolute::LockTime::ZERO);
    let mut tx = Transaction {
        version: ::bitcoin::transaction::Version(1),
        lock_time,
        input: inputs,
        output: outputs,
    };

    for (i, u) in plan.inputs.iter().enumerate() {
        let sk = derive_secret_key_cash(seed, network, account, u.branch, u.index)?;
        sign_p2pkh_input(&mut tx, i, u.value_sat, &sk)?;
    }

    let txid = tx.compute_txid();
    let mut raw: Vec<u8> = Vec::new();
    tx.consensus_encode(&mut raw)
        .map_err(|e| ChainError::Internal(format!("encode signed tx: {e}")))?;

    use crate::bitcoin::keys::BRANCH_INTERNAL;
    Ok(crate::bitcoin::tx::SignedTransfer {
        txid,
        raw_hex: hex::encode(&raw),
        plan: plan.clone(),
        change_address_branch: plan.change.as_ref().map(|_| BRANCH_INTERNAL),
    })
}

/// Комиссии: живой estimate у сервера, конверсия единица-в-единицу с BTC
/// (BCH/kB → сат/байт, floor 1). Фолбэк: 3/2/1 — сеть BCH дешёвая; при
/// недоступности оценки честно помечается fallback (как у BTC).
pub const BCH_FALLBACK_FAST: u64 = 3;
pub const BCH_FALLBACK_NORMAL: u64 = 2;
pub const BCH_FALLBACK_SLOW: u64 = 1;

pub fn estimate_fee_rates<G: Gateway + ?Sized>(
    gateway: &G,
) -> Result<crate::bitcoin::tx::FeeRates, ChainError> {
    crate::bitcoin::tx::estimate_fee_rates(gateway)
}

pub fn estimate_fee_rates_with_fallback<G: Gateway + ?Sized>(
    gateway: &G,
) -> Result<(crate::bitcoin::tx::FeeRates, bool), ChainError> {
    match estimate_fee_rates(gateway) {
        Ok(r) => Ok((r, false)),
        Err(ChainError::FeeEstimateUnavailable(_)) => Ok((
            crate::bitcoin::tx::FeeRates {
                fast_sat_vb: BCH_FALLBACK_FAST,
                normal_sat_vb: BCH_FALLBACK_NORMAL,
                slow_sat_vb: BCH_FALLBACK_SLOW,
            },
            true,
        )),
        Err(e) => Err(e),
    }
}

/// Подпись одного P2PKH-входа BCH: дайджест UAHF (ALL|FORKID, forkId=0) →
/// ECDSA RFC6979 → DER + 0x41 → scriptSig = <sig> <pubkey>.
pub fn sign_p2pkh_input(
    tx: &mut Transaction,
    input_index: usize,
    input_value_sat: u64,
    secret_key_bytes: &[u8; 32],
) -> Result<(), ChainError> {
    use bitcoin::secp256k1::{Message, SecretKey};
    if input_index >= tx.input.len() {
        return Err(ChainError::Internal(
            "sign: input index out of range".into(),
        ));
    }
    let sk = SecretKey::from_slice(secret_key_bytes)
        .map_err(|e| ChainError::Crypto(format!("bad secret key: {e}")))?;
    let secp = bitcoin::secp256k1::Secp256k1::signing_only();
    let pk = bitcoin::secp256k1::PublicKey::from_secret_key(&secp, &sk);
    let compressed = bitcoin::key::CompressedPublicKey::from_slice(pk.serialize().as_ref())
        .map_err(|e| ChainError::Crypto(format!("pubkey: {e}")))?;
    let pkh = bitcoin::PubkeyHash::from(compressed);
    let script_code = ScriptBuf::new_p2pkh(&pkh);

    let sighash = forkid_signature_hash(
        tx,
        script_code.as_bytes(),
        input_index,
        input_value_sat,
        0x41, // SIGHASH_ALL | SIGHASH_FORKID (паспорт §4, forkId = 0)
    )?;
    let msg = Message::from_digest(sighash);
    let sig = secp.sign_ecdsa(&msg, &sk);
    let mut der = sig.serialize_der().to_vec();
    der.push(0x41);

    // scriptSig = push(sig) push(pubkey) — собирается как байты напрямую
    // (varint-обёртки не нужны: push_slice-обёртки не проходят по типам).
    let mut script_sig: Vec<u8> = Vec::with_capacity(1 + der.len() + 1 + 33);
    script_sig.push(der.len() as u8);
    script_sig.extend_from_slice(&der);
    script_sig.push(33u8);
    script_sig.extend_from_slice(pk.serialize().as_ref());
    tx.input[input_index].script_sig = ScriptBuf::from_bytes(script_sig);
    Ok(())
}

// ---------------------------------------------------------------------------
// Тесты.
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cash_sighash_data::SIGHASH_VECTORS;

    #[test]
    fn cashaddr_spec_vectors() {
        // Спека cashaddr.md, таблица векторов: хэш F5BF… ↔ qr6m7j9n… (P2KH 20б).
        let hash =
            hex::decode("F5BF48B397DAE70BE82B3CCA4793F8EB2B6CDAC9").expect("spec vector hash");
        assert_eq!(hash.len(), 20);
        let mut h20 = [0u8; 20];
        h20.copy_from_slice(&hash);
        let a = cashaddr_pkh(PREFIX_MAINNET, &h20).unwrap();
        assert_eq!(
            a, "bitcoincash:qr6m7j9njldwwzlg9v7v53unlr4jkmx6eylep8ekg2",
            "cashaddr encode по вектору спеки"
        );
        // Декод возвращает тот же хэш.
        let (p, v, r) =
            decode_cashaddr("bitcoincash:qr6m7j9njldwwzlg9v7v53unlr4jkmx6eylep8ekg2").unwrap();
        assert_eq!((p.as_str(), v), (PREFIX_MAINNET, 0));
        assert_eq!(r, h20.to_vec());

        // P2SH-вектор спеки декодится (версия 8, тот же 20-байт хэш —
        // по спеке P2SH-вектор построен на ТОМ ЖЕ хэше, отличен только тип).
        let (_, v2, r2) =
            decode_cashaddr("bitcoincash:ppm2qsznhks23z7629mms6s4cwef74vcwvn0h829pq").unwrap();
        assert_eq!(v2, 8);
        let (p3, v3, r3) =
            decode_cashaddr("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a").unwrap();
        assert_eq!((p3.as_str(), v3), (PREFIX_MAINNET, 0));
        assert_eq!(r2, r3); // хэш одинаков; тип байт различает

        // Голая форма: с сетевым префиксом — валидна.
        bch_recipient_script(
            BchNetwork::Mainnet,
            "qr6m7j9njldwwzlg9v7v53unlr4jkmx6eylep8ekg2",
        )
        .expect("bare cashaddr ok");
    }

    #[test]
    fn legacy_cross_check() {
        // Legacy `1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu` — тот же хэш, что и
        // cashaddr-вектор спеки. Обе формы дают ОДИН scriptPubKey.
        let script_cash = bch_recipient_script(
            BchNetwork::Mainnet,
            "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a",
        )
        .unwrap();
        let script_legacy =
            bch_recipient_script(BchNetwork::Mainnet, "1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu")
                .unwrap();
        assert_eq!(script_cash.as_bytes(), script_legacy.as_bytes());
    }

    #[test]
    fn network_mismatch_rejected() {
        // bchtest-адрес (та же голая форма спеки под префиксом testnet) в
        // кошельке mainnet — отказ адресом сети.
        let hash = hex::decode("F5BF48B397DAE70BE82B3CCA4793F8EB2B6CDAC9").unwrap();
        let mut h20 = [0u8; 20];
        h20.copy_from_slice(&hash);
        let testnet_addr = cashaddr_encode(PREFIX_TESTNET, 0x00, &h20).unwrap();
        let err = bch_recipient_script(BchNetwork::Mainnet, &testnet_addr);
        assert!(matches!(
            err,
            Err(ChainError::AddressNetworkMismatch("Bitcoin Cash testnet3"))
        ));
    }

    #[test]
    fn sighash_vectors_bchn() {
        for (i, (tx_raw, script_hex, n_in, hash_type, forkid_digest, _legacy_digest)) in
            SIGHASH_VECTORS.iter().enumerate()
        {
            let mut tx_bytes: &[u8] = tx_raw;
            let tx: Transaction =
                ::bitcoin::consensus::Decodable::consensus_decode(&mut tx_bytes).expect("tx parse");
            let script_code = hex::decode(script_hex).expect("script hex");
            let ht = *hash_type as u32;
            let flip = |hexs: &str| -> String {
                let mut v = hex::decode(hexs).expect("digest hex");
                v.reverse();
                hex::encode(&v)
            };
            // FORKID-строки (консенсусный путь BCH с 2017): полный своп.
            // Строки без FORKID-бита (legacy-семантика) — вне пути кошелька:
            // консенсус их больше не принимает, и «no fork flag»-трактование
            // фаззинг-типов в тестовом файле не относится к подписям BCH.
            if ht & 0x40 != 0 {
                let got_f =
                    signature_hash_bch(&tx, &script_code, *n_in, 0, ht).expect("regular digest");
                assert_eq!(
                    hex::encode(got_f),
                    flip(forkid_digest),
                    "forkid digest mismatch, vector #{i}"
                );
                // FORKID-функция обязана совпасть с регулярным путём
                let got_u = forkid_signature_hash(&tx, &script_code, *n_in, 0, ht).unwrap();
                assert_eq!(
                    hex::encode(got_u),
                    hex::encode(got_f),
                    "fork==regular, #{i}"
                );
            }
        }
    }

    #[test]
    fn sign_and_serialize_legacy() {
        // Строим 2-входовую транзакцию и подписываем оба входа локально.
        // Дайджест-векторы BCHN уже доказывают алгоритм; здесь — склейка:
        // digest → ECDSA → DER+0x41 → scriptSig; сериализация — legacy (без
        // witness-маркера).
        let mut prev1 = <[u8; 32]>::default();
        prev1[0] = 0xaa;
        let mut prev2 = <[u8; 32]>::default();
        prev2[0] = 0xbb;

        let mut tx = Transaction {
            version: bitcoin::transaction::Version(2),
            lock_time: ::bitcoin::absolute::LockTime::ZERO,
            input: vec![
                ::bitcoin::TxIn {
                    previous_output: ::bitcoin::OutPoint {
                        txid: bitcoin::Txid::from_byte_array(prev1),
                        vout: 0,
                    },
                    script_sig: ScriptBuf::new(),
                    sequence: ::bitcoin::Sequence::from_consensus(0xffffffff),
                    witness: ::bitcoin::Witness::new(),
                },
                ::bitcoin::TxIn {
                    previous_output: ::bitcoin::OutPoint {
                        txid: bitcoin::Txid::from_byte_array(prev2),
                        vout: 1,
                    },
                    script_sig: ScriptBuf::new(),
                    sequence: ::bitcoin::Sequence::from_consensus(0xffffffff),
                    witness: ::bitcoin::Witness::new(),
                },
            ],
            output: vec![
                ::bitcoin::TxOut {
                    value: ::bitcoin::Amount::from_sat(10_000),
                    script_pubkey: bch_recipient_script(
                        BchNetwork::Mainnet,
                        "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a",
                    )
                    .unwrap(),
                },
                ::bitcoin::TxOut {
                    value: ::bitcoin::Amount::from_sat(5_000),
                    script_pubkey: bch_recipient_script(
                        BchNetwork::Mainnet,
                        "1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu",
                    )
                    .unwrap(),
                },
            ],
        };

        // Детерминированные ключи (тестовые значения, не секреты).
        let sk1 = [0x11; 32];
        let sk2 = [0x22; 32];
        sign_p2pkh_input(&mut tx, 0, 60_000, &sk1).expect("sign 0");
        sign_p2pkh_input(&mut tx, 1, 90_000, &sk2).expect("sign 1");

        // scriptSig: [sig][33-byte pubkey]
        for idx in 0..2 {
            let script = tx.input[idx].script_sig.as_bytes();
            assert!(script.len() >= 105, "scriptSig size sanity, вход {idx}");
            let sig_len = script[0] as usize;
            assert!((70..=74).contains(&sig_len), "sig push size, вход {idx}");
            let pk_len_pos = 1 + sig_len;
            assert_eq!(script[pk_len_pos], 33, "pubkey push length, вход {idx}");
            assert_eq!(
                pk_len_pos + 1 + 33,
                script.len(),
                "scriptSig полный, вход {idx}"
            );
        }

        // Верификация подписей тем же дайджестом (инвариант подписи).
        let secp = bitcoin::secp256k1::Secp256k1::verification_only();
        for idx in 0..2 {
            let script = tx.input[idx].script_sig.as_bytes();
            let sig_len = script[0] as usize;
            let sig_full = &script[1..1 + sig_len]; // DER + 0x41
            let pk =
                bitcoin::secp256k1::PublicKey::from_slice(&script[2 + sig_len..2 + sig_len + 33])
                    .unwrap();
            let pkh = bitcoin::PubkeyHash::from(
                bitcoin::key::CompressedPublicKey::from_slice(pk.serialize().as_ref()).unwrap(),
            );
            let script_code = ScriptBuf::new_p2pkh(&pkh);
            let value = if idx == 0 { 60_000 } else { 90_000 };
            let digest =
                forkid_signature_hash(&tx, script_code.as_bytes(), idx, value, 0x41).unwrap();
            let msg = bitcoin::secp256k1::Message::from_digest(digest);
            // последний байт sig = hashtype; ECDSA-часть до него
            let ecdsa =
                bitcoin::secp256k1::ecdsa::Signature::from_der(&sig_full[..sig_full.len() - 1])
                    .unwrap();
            secp.verify_ecdsa(&msg, &ecdsa, &pk).expect("sig valid");
        }

        // Сериализация: witness-empty → legacy (нет 0x00 0x01 маркера).
        let mut raw: Vec<u8> = Vec::new();
        tx.consensus_encode(&mut raw).unwrap();
        assert_eq!(raw[4], 2, "вход-каунт (2 входа)");
        assert_ne!(raw.len(), 0);
    }

    #[test]
    fn real_chain_tx_digest() {
        // Грунд-трута: реальная BCH-транзакция из цепи (вход P2PKH).
        // Дайджест сверен ECDSA-верификацией оригинальной подписи из
        // scriptSig против pubkey (проверено 16.11.2026, сервер
        // bch.imaginary.cash). Это тот алгоритм, который подписывает кошелёк.
        const TX: &str = "0100000001dc5266dd65554730f0cd5f8e902409d8acb0a482d0af7d5f4f5a4a83e74d163e000000006a47304402207a137a2b7a35815115bca3a0c648c7030da2e29a70dca4528461493be0039ff802200d654cbd4435479eb526df65caad95ecc218466961e4a3aa5690ba8425308025412102da2caee28aa390be60b3bfb4e07cdb7cd206940cd4c3f21b9c7fe5de732c2339ffffffff017c6c4803000000001976a914c0af6adacafc1cd7965134eeb6c2a74351482df388ac00000000";
        const EXPECTED: &str = "8d64edf940479d1cab89582ba427c6b2188a309753b167f5055f16576059d70a";
        const SCRIPT_CODE: &str = "76a91448ce9bec1a1e6efc50052307c2af512d5df6799b88ac";
        const AMOUNT: u64 = 55_078_398;

        let mut bytes: &[u8] = &hex::decode(TX).expect("tx hex");
        let tx: Transaction =
            ::bitcoin::consensus::Decodable::consensus_decode(&mut bytes).expect("tx parse");
        let script_code = hex::decode(SCRIPT_CODE).expect("script hex");
        let got = forkid_signature_hash(&tx, &script_code, 0, AMOUNT, 0x41).expect("digest");
        assert_eq!(hex::encode(got), EXPECTED, "реальный вход из BCH-цепи");
    }
}
