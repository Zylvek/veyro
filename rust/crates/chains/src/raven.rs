//! Ravencoin (RVN) adapter (docs/coins/RVN.md — верdict: реализуемость
//! полная; статус матрицы честно поднимается только после живого цикла).
//!
//! Профиль «как BTC/LTC», упрощённый до legacy: UTXO, транзакция без
//! SegWit-расходов (адреса base58 P2PKH), Electrum TLS (Electrum-RVN),
//! подпись ECDSA SIGHASH_ALL (0x01) стандартным legacy-дайджестом —
//! общий модуль cash.rs, проверенный векторами BCHN (test[5] legacy).
//!
//! Отличия от BCH/XEC:
//! - сеть НЕ форкнула UAHF → подпись БЕЗ forkid (plain legacy sighash);
//! - адреса: base58 P2PKH `R…` (версия 60) / P2SH `r…` (122); testnet7
//!   111/196 (chainparams.cpp, официальные assert-значения);
//! - деривация BIP44 m/44'/175'/account' (nExtCoinType 175, официальный
//!   узел); testnet7 coin type 1 (nExtCoinType testnet, официальный);
//! - asset-слой (OP_RVN_ASSET) вне scope: обычные UTXO-переводы не
//!   затронуты (паспорт §4: базовые переводы не зависят от asset-поля).
//!
//! Серверы — официальные дефолты клиента Electrum-RVN (servers.json /
//! servers_testnet.json) + документированный testnet.rvn.rocks (паспорт
//! §5, Dart-клиент raven_electrum).

use crate::bitcoin::keys::{AddressSource, DerivedAddress};
use crate::bitcoin::scan::WalletUtxo;
use crate::electrum::Gateway;
use crate::{electrum_scripthash_hex, ChainError};
use ::bitcoin::bip32::{ChildNumber, DerivationPath, Xpriv, Xpub};
use ::bitcoin::consensus::Encodable;
use ::bitcoin::{ScriptBuf, Transaction, Txid};
use bitcoin_hashes::Hash;
use electrum_client::ElectrumApi;
use zeroize::Zeroizing;

/// SLIP-44 coin type RVN mainnet (nExtCoinType, chainparams.cpp).
pub const RVN_COIN_TYPE: u32 = 175;

/// Legacy base58 версии (паспорт §3, chainparams.cpp): (P2PKH, P2SH).
pub const MAINNET_VERSIONS: (u8, u8) = (60, 122);
pub const TESTNET7_VERSIONS: (u8, u8) = (111, 196);

/// Genesis RVN mainnet (assert в chainparams.cpp).
pub const GENESIS_MAINNET_HEX: &str =
    "0000006b444bc2f2ffe627be9d9e7e7a0730000870ef6eb6da46c8eae389df90";
/// Genesis RVN testnet7 (assert в chainparams.cpp).
pub const GENESIS_TESTNET7_HEX: &str =
    "000000ecfc5e6324a079542221d00e10362bdc894d56500c414060eea8a3ad5a";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RvnNetwork {
    Mainnet,
    Testnet7,
}

impl RvnNetwork {
    pub fn coin_type(self) -> u32 {
        match self {
            RvnNetwork::Mainnet => RVN_COIN_TYPE,
            RvnNetwork::Testnet7 => 1,
        }
    }

    pub fn display_name(self) -> &'static str {
        match self {
            RvnNetwork::Mainnet => "Ravencoin mainnet",
            RvnNetwork::Testnet7 => "Ravencoin testnet7",
        }
    }

    /// Legacy-base58 версии (паспорт §3): (P2PKH, P2SH).
    pub fn base58_versions(self) -> (u8, u8) {
        match self {
            RvnNetwork::Mainnet => MAINNET_VERSIONS,
            RvnNetwork::Testnet7 => TESTNET7_VERSIONS,
        }
    }

    pub fn genesis_hash(self) -> [u8; 32] {
        let hex64 = match self {
            RvnNetwork::Mainnet => GENESIS_MAINNET_HEX,
            RvnNetwork::Testnet7 => GENESIS_TESTNET7_HEX,
        };
        let bytes = hex::decode(hex64).expect("genesis hash hex is valid");
        let mut out = [0u8; 32];
        out.copy_from_slice(&bytes);
        out
    }

    pub fn code(self) -> u32 {
        match self {
            RvnNetwork::Mainnet => 0,
            RvnNetwork::Testnet7 => 1,
        }
    }

    pub fn from_code(code: u32) -> Option<Self> {
        match code {
            0 => Some(RvnNetwork::Mainnet),
            1 => Some(RvnNetwork::Testnet7),
            _ => None,
        }
    }
}

/// Кандидаты публичных Electrum-RVN серверов (официальные дефолты
/// electrum-ravencoin servers.json; TLS-порты; живой rustls-фильтран
/// после probe; порядок = порядок в списке клиента).
pub const SERVER_MAINNET_CANDIDATES: &[&str] =
    &["ssl://rvn4lyfe.com:50002", "ssl://162.19.153.65:50002"];

/// Testnet7-кандидаты (servers_testnet.json + паспорт §5).
pub const SERVER_TESTNET7_CANDIDATES: &[&str] =
    &["ssl://rvn4lyfe.com:50012", "ssl://testnet.rvn.rocks:50002"];

/// Транспорт RVN — Electrum, genesis-верификация на входе.
#[derive(Clone)]
pub struct RvnGateway {
    client: std::sync::Arc<electrum_client::Client>,
    url: String,
}

impl RvnGateway {
    pub fn connect(url: &str) -> Result<Self, ChainError> {
        if url.trim().is_empty() {
            return Err(ChainError::InvalidServerUrl("empty url".into()));
        }
        let lower = url.to_ascii_lowercase();
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
        unreachable!("raven handshake loop returns on the last attempt");
    }

    pub fn url(&self) -> &str {
        &self.url
    }

    /// Fund-safety: genesis RVN сверяется бит-в-бит.
    pub fn verify_network(&self, network: RvnNetwork) -> Result<(), ChainError> {
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

impl Gateway for RvnGateway {
    fn network(&self) -> crate::electrum::BtcNetwork {
        crate::electrum::BtcNetwork::Mainnet
    }

    fn estimate_fees_batch(&self, blocks: &[u32]) -> Result<Vec<f64>, ChainError> {
        let depths: Vec<usize> = blocks.iter().map(|b| *b as usize).collect();
        self.client
            .batch_estimate_fee(&depths)
            .map_err(crate::electrum::map_client_error)
            .map(|v| v.into_iter().map(sanitize_fee_estimate).collect())
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

/// Жёсткий потолок правдоподобной комиссии RVN в sat/vB (та же честная
/// санитизация policy-заглушек Electrum, что у XEC; реальный рынок RVN
/// на порядках ниже).
pub const RVN_MAX_SANE_SAT_VB: u64 = 100;

/// Приводит сырую Electrum-оценку к форме sat_per_vb_from_btc_per_kb:
/// выше потолка → -1.0 («unknown at this depth»).
fn sanitize_fee_estimate(raw: f64) -> f64 {
    if !raw.is_finite() || raw < 0.0 {
        return if raw < 0.0 { raw } else { -1.0 };
    }
    let sat_per_vb =
        crate::bitcoin::tx::sat_per_vb_from_btc_per_kb(raw).unwrap_or(RVN_MAX_SANE_SAT_VB + 1);
    if sat_per_vb > RVN_MAX_SANE_SAT_VB {
        -1.0
    } else {
        raw
    }
}

/// Фейловер-кандидаты Electrum-RVN серверов (отработавший — в конец).
pub fn rvn_failover_candidates(network: RvnNetwork, failed_url: &str) -> Vec<String> {
    let source: &[&str] = match network {
        RvnNetwork::Mainnet => SERVER_MAINNET_CANDIDATES,
        RvnNetwork::Testnet7 => SERVER_TESTNET7_CANDIDATES,
    };
    let mut list: Vec<String> = source.iter().map(|s| s.to_string()).collect();
    if let Some(pos) = list.iter().position(|u| u == failed_url) {
        let removed = list.remove(pos);
        list.push(removed);
    }
    list
}

// ---------------------------------------------------------------------------
// Адреса: base58 P2PKH `R…` / P2SH `r…` (+ testnet7 111/196).
// ---------------------------------------------------------------------------

/// P2PKH-адрес приёма: `R…` (mainnet) / `r…`-версия (testnet7).
pub fn base58_pkh(version: u8, hash: &[u8; 20]) -> Result<String, ChainError> {
    crate::cash::base58check_encode(&[version], hash)
}

/// Парсинг адреса получателя RVN → script_pubkey (P2PKH; P2SH допускается).
pub fn rvn_recipient_script(network: RvnNetwork, address: &str) -> Result<ScriptBuf, ChainError> {
    let trimmed = address.trim();
    if trimmed.is_empty() {
        return Err(ChainError::InvalidAddress("empty address".into()));
    }
    let payload = crate::cash::base58check_decode(trimmed)?;
    if payload.len() != 21 {
        return Err(ChainError::InvalidAddress(format!(
            "{address}: base58 payload должен быть 21 байт"
        )));
    }
    let (pkh_v, psh_v) = network.base58_versions();
    let version = payload[0];
    if version != pkh_v && version != psh_v {
        let (m_pkh, m_psh) = MAINNET_VERSIONS;
        let (t_pkh, t_psh) = TESTNET7_VERSIONS;
        let real = if version == m_pkh || version == m_psh {
            "Ravencoin mainnet"
        } else if version == t_pkh || version == t_psh {
            "Ravencoin testnet7"
        } else {
            "неизвестная сеть RVN"
        };
        return Err(ChainError::AddressNetworkMismatch(real));
    }
    let hash = <[u8; 20]>::try_from(&payload[1..]).expect("21 байт проверен выше");
    if version == pkh_v {
        let h = <::bitcoin::PubkeyHash as bitcoin_hashes::Hash>::from_byte_array(hash);
        Ok(ScriptBuf::new_p2pkh(&h))
    } else {
        let h = <::bitcoin::ScriptHash as bitcoin_hashes::Hash>::from_byte_array(hash);
        Ok(ScriptBuf::new_p2sh(&h))
    }
}

// ---------------------------------------------------------------------------
// Ключи: BIP44 m/44'/coin_type'/account'.
// ---------------------------------------------------------------------------

/// Публичное лицо RVN-аккаунта (watch-only).
#[derive(Debug, Clone)]
pub struct RvnAccount {
    network: RvnNetwork,
    account: u32,
    account_xpub: Xpub,
}

impl RvnAccount {
    pub fn from_seed(
        seed: &[u8; 64],
        network: RvnNetwork,
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

    pub fn network(&self) -> RvnNetwork {
        self.network
    }

    pub fn account(&self) -> u32 {
        self.account
    }

    pub fn account_xpub(&self) -> &Xpub {
        &self.account_xpub
    }

    /// P2PKH-адрес приёма (base58) на `branch/index`.
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
        let pkh = compressed.wpubkey_hash();
        let script =
            ScriptBuf::new_p2pkh(&::bitcoin::PubkeyHash::from_byte_array(pkh.to_byte_array()));
        let (pkh_v, _) = self.network.base58_versions();
        let address = base58_pkh(pkh_v, &pkh.to_byte_array())?;
        Ok(DerivedAddress {
            address,
            scripthash_hex: electrum_scripthash_hex(&script),
            script_pubkey: script,
            branch,
            index,
            path: format!(
                "m/44'/{}'/{}'/{}/{}",
                self.network.coin_type(),
                self.account,
                branch,
                index
            ),
        })
    }
}

impl AddressSource for RvnAccount {
    fn derive_address(&self, branch: u32, index: u32) -> Result<DerivedAddress, ChainError> {
        RvnAccount::derive_address(self, branch, index)
    }
}

/// Секретный ключ ветки/индекса `m/44'/coin'/account'/branch/index`.
pub fn derive_secret_key_rvn(
    seed: &[u8; 64],
    network: RvnNetwork,
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

// ---------------------------------------------------------------------------
// Планирование и подпись — re-use общих функций (план по скриптам, чистая
// legacy-арифметика; подпись по hash_type 0x01 БЕЗ forkid).
// ---------------------------------------------------------------------------

pub const RVN_OUTPUT_DUST_SAT: u64 = 546;

pub fn rvn_plan_transfer_on(
    network: RvnNetwork,
    recipient: &str,
    amount_sat: u64,
    rate_per_byte: u64,
    utxos: &[WalletUtxo],
    change_address: &DerivedAddress,
) -> Result<crate::bitcoin::tx::PlannedTransfer, ChainError> {
    let script = rvn_recipient_script(network, recipient)?;
    crate::cash::bch_plan_transfer(
        recipient.trim(),
        script,
        amount_sat,
        rate_per_byte,
        utxos,
        change_address,
    )
}

/// Подпись RVN-плана: hash_type SIGHASH_ALL (0x01) — БЕЗ forkid-флага;
/// дайджест legacy (общий модуль cash.rs).
pub fn rvn_signed_transfer(
    plan: &crate::bitcoin::tx::PlannedTransfer,
    seed: &[u8; 64],
    network: RvnNetwork,
    account: u32,
    tip_height: u32,
) -> Result<crate::bitcoin::tx::SignedTransfer, ChainError> {
    use crate::bitcoin::keys::BRANCH_INTERNAL;

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
        let sk = derive_secret_key_rvn(seed, network, account, u.branch, u.index)?;
        crate::cash::sign_p2pkh_input(&mut tx, i, u.value_sat, &sk)?;
    }

    let txid = tx.compute_txid();
    let mut raw: Vec<u8> = Vec::new();
    tx.consensus_encode(&mut raw)
        .map_err(|e| ChainError::Internal(format!("encode signed tx: {e}")))?;

    Ok(crate::bitcoin::tx::SignedTransfer {
        txid,
        raw_hex: hex::encode(&raw),
        plan: plan.clone(),
        change_address_branch: plan.change.as_ref().map(|_| BRANCH_INTERNAL),
    })
}

// ---------------------------------------------------------------------------
// Тесты.
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base58_pkh_roundtrip_mainnet() {
        // Известный hash160 BTC-вектора → версия 60 → base58 'R…'.
        let mut hash = [0u8; 20];
        hash.copy_from_slice(
            &hex::decode("751e76e8199196d454941c45d1b3a323f1433bd6").expect("hex"),
        );
        let addr = base58_pkh(60, &hash).unwrap();
        assert!(addr.starts_with('R'), "{addr}");
        // Round-trip: decode → тот же payload.
        let payload = crate::cash::base58check_decode(&addr).unwrap();
        assert_eq!(payload[0], 60u8);
        assert_eq!(&payload[1..], &hash[..]);
        // И это валидный P2PKH-скрипт.
        let script = rvn_recipient_script(RvnNetwork::Mainnet, &addr).unwrap();
        assert_eq!(script.as_bytes()[0], 0x76);
    }

    #[test]
    fn testnet7_versions() {
        // Проверены из chainparams.cpp: 111/196; coin type testnet = 1.
        let net = RvnNetwork::Testnet7;
        assert_eq!(net.base58_versions(), (111, 196));
        assert_eq!(net.coin_type(), 1);
        let hash = [7u8; 20];
        let addr = base58_pkh(111, &hash).unwrap();
        // Раунд-трип в testnet-версии.
        let payload = crate::cash::base58check_decode(&addr).unwrap();
        assert_eq!(payload[0], 111u8);
        let script = rvn_recipient_script(net, &addr).unwrap();
        assert_eq!(script.as_bytes()[0], 0x76);
    }

    #[test]
    fn network_mismatch_rejected() {
        // Адрес testnet7 в кошельке mainnet — отказ (не тратим в чужую сеть).
        let hash = [7u8; 20];
        let testnet_addr = base58_pkh(TESTNET7_VERSIONS.0, &hash).unwrap();
        let err = rvn_recipient_script(RvnNetwork::Mainnet, &testnet_addr);
        assert!(matches!(
            err,
            Err(ChainError::AddressNetworkMismatch("Ravencoin testnet7"))
        ));
    }

    #[test]
    fn derivation_matches_slip44() {
        let seed = [7u8; 64];
        let account = RvnAccount::from_seed(&seed, RvnNetwork::Mainnet, 0).expect("account");
        let addr = account.derive_address(0, 0).unwrap();
        assert!(
            addr.path.starts_with("m/44'/175'/0'/0/0"),
            "path: {}",
            addr.path
        );
        assert!(addr.address.starts_with('R'), "{}", addr.address);
    }

    #[test]
    fn fee_estimate_sanity_cap() {
        assert_eq!(sanitize_fee_estimate(10.0), -1.0);
        assert_eq!(sanitize_fee_estimate(0.00001), 0.00001);
        assert_eq!(sanitize_fee_estimate(0.001), 0.001);
        assert_eq!(sanitize_fee_estimate(0.0011), -1.0);
        assert_eq!(sanitize_fee_estimate(f64::NAN), -1.0);
        assert_eq!(sanitize_fee_estimate(-1.0), -1.0);
    }
}
