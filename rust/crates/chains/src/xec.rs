//! eCash (XEC) adapter (docs/coins/XEC.md — верdict Send supported).
//!
//! Повторяет профиль LTC/BCH: UTXO, legacy-транзакция без SegWit, Electrum
//! TLS, подпись ECDSA ALL|FORKID (UAHF, forkId=0) — дайджест-модуль
//! переиспользуется из cash.rs (та же спецификация, Bitcoin ABC).
//!
//! Отличия от BCH:
//! - cashaddr-префикс `ecash` (testnet3 `ectest`);
//! - деривация BIP44 `m/44'/899'/account'` (SLIP-44 899, Electrum ABC);
//!   1899 (Cashtab) — опция совместимости при импорте, решениевладельца
//!   фиксируется в docs (основной путь 899);
//! - единицы: внутренние сатоши; **1 XEC = 100 сатоши** (UI показывает
//!   биты, 2 знака) — display-логика на стороне UI, ядро считает сат.
//!
//! Кандидаты серверов — официальные Electrum ABC (паспорт §5, TLS 50002).

use crate::bitcoin::keys::{AddressSource, DerivedAddress};
use crate::bitcoin::scan::{discover, wallet_balance, Discovery, WalletBalance, WalletUtxo};
use crate::electrum::Gateway;
use crate::{electrum_scripthash_hex, ChainError};
use ::bitcoin::bip32::{ChildNumber, DerivationPath, Xpriv, Xpub};
use ::bitcoin::consensus::Encodable;
use ::bitcoin::{ScriptBuf, Transaction, Txid};
use electrum_client::ElectrumApi;

use bitcoin_hashes::Hash;
use zeroize::Zeroizing;

/// SLIP-44 coin type XEC mainnet (паспорт §3).
pub const XEC_COIN_TYPE: u32 = 899;

/// cashaddr-префиксы сетей XEC (паспорт §2).
pub const PREFIX_MAINNET: &str = "ecash";
pub const PREFIX_TESTNET: &str = "ectest";

/// Genesis XEC mainnet — общий с BTC/BCH (паспорт §2, 2 источника).
pub const GENESIS_MAINNET_HEX: &str =
    "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f";
/// Genesis XEC testnet3 — общий с BTC testnet3 (паспорт §2).
pub const GENESIS_TESTNET_HEX: &str =
    "000000000933ea01ad0ee984209779baaec3ced90fa3f408719526f8d77f4943";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum XecNetwork {
    Mainnet,
    Testnet3,
}

impl XecNetwork {
    pub fn coin_type(self) -> u32 {
        match self {
            XecNetwork::Mainnet => XEC_COIN_TYPE,
            XecNetwork::Testnet3 => 1,
        }
    }

    pub fn display_name(self) -> &'static str {
        match self {
            XecNetwork::Mainnet => "eCash mainnet",
            XecNetwork::Testnet3 => "eCash testnet3",
        }
    }

    pub fn cashaddr_prefix(self) -> &'static str {
        match self {
            XecNetwork::Mainnet => PREFIX_MAINNET,
            XecNetwork::Testnet3 => PREFIX_TESTNET,
        }
    }

    pub fn genesis_hash(self) -> [u8; 32] {
        let hex64 = match self {
            XecNetwork::Mainnet => GENESIS_MAINNET_HEX,
            XecNetwork::Testnet3 => GENESIS_TESTNET_HEX,
        };
        let bytes = hex::decode(hex64).expect("genesis hash hex is valid");
        let mut out = [0u8; 32];
        out.copy_from_slice(&bytes);
        out
    }

    /// Legacy-base58 версии (паспорт §3): (P2PKH, P2SH).
    pub fn legacy_versions(self) -> (u8, u8) {
        match self {
            XecNetwork::Mainnet => (0x00, 0x05),
            XecNetwork::Testnet3 => (0x6f, 0xc4),
        }
    }

    pub fn code(self) -> u32 {
        match self {
            XecNetwork::Mainnet => 0,
            XecNetwork::Testnet3 => 1,
        }
    }

    pub fn from_code(code: u32) -> Option<Self> {
        match code {
            0 => Some(XecNetwork::Mainnet),
            1 => Some(XecNetwork::Testnet3),
            _ => None,
        }
    }
}

/// Кандидаты публичных Electrum-XEC серверов (Electrum ABC servers.json,
/// паспорт §5; TLS-порты; живой rustls-фильтран после probe).
pub const SERVER_MAINNET_CANDIDATES: &[&str] = &[
    "ssl://electrum.bitcoinabc.org:50002",
    "ssl://electrum.fabien.cash:50002",
    "ssl://fulcrum.pierre.cash:50002",
];

/// Жёсткий потолок правдоподобной комиссии XEC в sat/vB.
///
/// ElectrumX/Fulcrum на ABC-семействе возвращает policy-дефолт (по
/// наблюдению testnet: 10 монет/kB → 1e6 sat/vB), когда мемпул не даёт
/// честной оценки. Реальный рынок XEC/BCH-семейства на порядках ниже
/// потолка; значение выше — не оценка, а заглушка: помечаем её как
/// «недоступную» (-1.0), и общий fallback-механизм tx.rs подставляет
/// консервативные пресеты с честной флаг-меткой для UI.
pub const XEC_MAX_SANE_SAT_VB: u64 = 100;

/// Приводит сырую Electrum-оценку (coin/kB в протокольных единицах) к
/// форме, понятной sat_per_vb_from_btc_per_kb: выше потолка → -1.0
/// («unknown at this depth»), NaN/Inf → -1.0, отрицательные — как есть.
fn sanitize_fee_estimate(raw: f64) -> f64 {
    if !raw.is_finite() || raw < 0.0 {
        return if raw < 0.0 { raw } else { -1.0 };
    }
    // Тот же конвертер, что в bitcoin::tx — один источник арифметики.
    let sat_per_vb =
        crate::bitcoin::tx::sat_per_vb_from_btc_per_kb(raw).unwrap_or(XEC_MAX_SANE_SAT_VB + 1);
    if sat_per_vb > XEC_MAX_SANE_SAT_VB {
        -1.0
    } else {
        raw
    }
}

/// Транспорт XEC — Electrum, genesis-верификация на входе.
#[derive(Clone)]
pub struct XecGateway {
    client: std::sync::Arc<electrum_client::Client>,
    url: String,
}

impl XecGateway {
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
        unreachable!("xec handshake loop returns on the last attempt");
    }

    pub fn url(&self) -> &str {
        &self.url
    }

    /// Fund-safety: genesis XEC == BTC genesis (общая история форка).
    pub fn verify_network(&self, network: XecNetwork) -> Result<(), ChainError> {
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

impl Gateway for XecGateway {
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

// ---------------------------------------------------------------------------
// Адреса: cashaddr `ecash:…` (P2KH) + legacy base58.
// ---------------------------------------------------------------------------

/// P2KH-address приёма: `ecash:q…`.
pub fn cashaddr_pkh(prefix: &str, hash: &[u8; 20]) -> Result<String, ChainError> {
    // Тот же кодек (polyMod/charset), что у BCH — спека cashaddr общая.
    // version byte: type P2KH (0) + размер 160 (0) = 0x00.
    crate::cash::cashaddr_encode(prefix, 0x00, hash)
}

/// Парсинг адреса получателя XEC → script_pubkey (P2PKH; P2SH — допускается).
pub fn xec_recipient_script(network: XecNetwork, address: &str) -> Result<ScriptBuf, ChainError> {
    let trimmed = address.trim();
    if trimmed.is_empty() {
        return Err(ChainError::InvalidAddress("empty address".into()));
    }
    let lower = trimmed.to_ascii_lowercase();
    let (prefix, version, hash) = if lower.contains(':') {
        crate::cash::decode_cashaddr(trimmed)?
    } else if lower.starts_with('q') || lower.starts_with('p') {
        crate::cash::decode_cashaddr(&format!("{}:{}", network.cashaddr_prefix(), trimmed))?
    } else {
        let payload = crate::cash::base58check_decode(trimmed)?;
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
    let mismatch = |real: &str| {
        ChainError::AddressNetworkMismatch(match real {
            PREFIX_MAINNET => "eCash mainnet",
            PREFIX_TESTNET => "eCash testnet3",
            _ => "неизвестная сеть XEC",
        })
    };
    if prefix != network.cashaddr_prefix() {
        return Err(mismatch(&prefix));
    }
    if hash.len() != 20 {
        return Err(ChainError::InvalidAddress(format!(
            "{address}: поддержан только 20-байтный хэш"
        )));
    }
    let h = <::bitcoin::PubkeyHash as bitcoin_hashes::Hash>::from_byte_array(
        hash[..20].try_into().expect("20 bytes проверены выше"),
    );
    match version {
        0 => Ok(ScriptBuf::new_p2pkh(&h)),
        8 => Ok(ScriptBuf::new_p2sh(
            &<::bitcoin::ScriptHash as bitcoin_hashes::Hash>::from_byte_array(h.to_byte_array()),
        )),
        t => Err(ChainError::InvalidAddress(format!(
            "{address}: тип {t} не P2KH/P2SH"
        ))),
    }
}

// ---------------------------------------------------------------------------
// Ключи: BIP44 m/44'/899'/account'.
// ---------------------------------------------------------------------------

/// Публичное лицо XEC-аккаунта (watch-only).
#[derive(Debug, Clone)]
pub struct XecAccount {
    network: XecNetwork,
    account: u32,
    account_xpub: Xpub,
}

impl XecAccount {
    /// `m/44'/899'/account'` (паспорт §3, Electrum ABC официальный путь;
    /// 1899 Cashtab — опция импорта, решениевладельца зафиксировано в docs).
    pub fn from_seed(
        seed: &[u8; 64],
        network: XecNetwork,
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

    pub fn network(&self) -> XecNetwork {
        self.network
    }

    pub fn account(&self) -> u32 {
        self.account
    }

    pub fn account_xpub(&self) -> &Xpub {
        &self.account_xpub
    }

    /// P2PKH-адрес (cashaddr-вид) на `branch/index`.
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
        let script = ScriptBuf::new_p2pkh(&::bitcoin::PubkeyHash::from_byte_array(
            wpkh.to_byte_array(),
        ));
        let address = cashaddr_pkh(self.network.cashaddr_prefix(), &wpkh.to_byte_array())?;
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

impl AddressSource for XecAccount {
    fn derive_address(&self, branch: u32, index: u32) -> Result<DerivedAddress, ChainError> {
        XecAccount::derive_address(self, branch, index)
    }
}

/// Секретный ключ ветки/индекса `m/44'/899'/account'/branch/index`.
pub fn derive_secret_key_xec(
    seed: &[u8; 64],
    network: XecNetwork,
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

/// Скан XEC-аккаунта + баланс (вход UI-провода).
pub fn xec_scan_and_balance(
    gateway: &XecGateway,
    account: &XecAccount,
    gap_limit: u32,
) -> Result<(Discovery, WalletBalance), ChainError> {
    let discovery = discover(gateway, account, gap_limit)?;
    let balance = wallet_balance(gateway, &discovery)?;
    Ok((discovery, balance))
}

/// Фейловер-кандидаты Electrum-XEC серверов (отработавший — в конец).
pub fn xec_failover_candidates(failed_url: &str) -> Vec<String> {
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

// ---------------------------------------------------------------------------
// Планирование (сат/байт) и подпись — re-use BCH-функций (та же спека UAHF):
// bch_plan_transfer (заголовок BCH-именной, но работает на скриптах) и
// sign_p2pkh_input. Единственное отличие XEC — forkId=0 (тот же) и единицы.
// ---------------------------------------------------------------------------

pub const XEC_OUTPUT_DUST_SAT: u64 = 546;

pub fn xec_plan_transfer_on(
    network: XecNetwork,
    recipient: &str,
    amount_sat: u64,
    rate_per_byte: u64,
    utxos: &[WalletUtxo],
    change_address: &DerivedAddress,
) -> Result<crate::bitcoin::tx::PlannedTransfer, ChainError> {
    let script = xec_recipient_script(network, recipient)?;
    crate::cash::bch_plan_transfer(
        recipient.trim(),
        script,
        amount_sat,
        rate_per_byte,
        utxos,
        change_address,
    )
}

/// Mainnet-обёртка (мост работает только с eCash mainnet; тест-цикл
/// ectest использует [xec_plan_transfer_on]).
pub fn xec_plan_transfer(
    recipient: &str,
    amount_sat: u64,
    rate_per_byte: u64,
    utxos: &[WalletUtxo],
    change_address: &DerivedAddress,
) -> Result<crate::bitcoin::tx::PlannedTransfer, ChainError> {
    xec_plan_transfer_on(
        XecNetwork::Mainnet,
        recipient,
        amount_sat,
        rate_per_byte,
        utxos,
        change_address,
    )
}

/// Сборка + локальная подпись XEC-плана (forkid 0x41, forkId=0).
pub fn xec_signed_transfer(
    plan: &crate::bitcoin::tx::PlannedTransfer,
    seed: &[u8; 64],
    network: XecNetwork,
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
        let sk = derive_secret_key_xec(seed, network, account, u.branch, u.index)?;
        crate::cash::sign_p2pkh_input(&mut tx, i, u.value_sat, &sk)?;
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

// ---------------------------------------------------------------------------
// Тесты.
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fee_estimate_sanity_cap() {
        // Policy-заглушка testnet (10 монет/kB → 1e6 sat/vB) → «неизвестно».
        assert_eq!(sanitize_fee_estimate(10.0), -1.0);
        // Реальный уровень (0.00001 coin/kB → 1 sat/vB) проходит как есть.
        assert_eq!(sanitize_fee_estimate(0.00001), 0.00001);
        // Потолочная граница: ровно 100 sat/vB проходит, 101 — нет.
        assert_eq!(sanitize_fee_estimate(0.001), 0.001);
        assert_eq!(sanitize_fee_estimate(0.0011), -1.0);
        // NaN/Inf → «неизвестно», честное -1 сохраняется.
        assert_eq!(sanitize_fee_estimate(f64::NAN), -1.0);
        assert_eq!(sanitize_fee_estimate(f64::INFINITY), -1.0);
        assert_eq!(sanitize_fee_estimate(-1.0), -1.0);
    }

    #[test]
    fn cashaddr_ecash_official_support_address() {
        // Паспорт §3: официальный адрес поддержки eCash (P2SH-форма 'p').
        let (prefix, version, hash) =
            crate::cash::decode_cashaddr("ecash:prfhcnyqnl5cgrnmlfmms675w93ld7mvvqd0y8lz07")
                .expect("official support address decodes");
        assert_eq!(prefix, PREFIX_MAINNET);
        assert_eq!(version, 8); // P2SH
        assert_eq!(hash.len(), 20);
    }

    #[test]
    fn address_roundtrip_mainnet() {
        // Round-trip P2KH: encode → decode → тот же хэш и скрипт.
        let mut hash = [0u8; 20];
        hash.copy_from_slice(
            &hex::decode("751e76e8199196d454941c45d1b3a323f1433bd6").expect("hex"),
        );
        let addr = cashaddr_pkh(PREFIX_MAINNET, &hash).unwrap();
        assert!(addr.starts_with("ecash:q"));
        let (p, v, r) = decode_required_or(&addr, PREFIX_MAINNET);
        assert_eq!(p, PREFIX_MAINNET);
        assert_eq!(v, 0u8);
        assert_eq!(r, hash.to_vec());
        let script = xec_recipient_script(XecNetwork::Mainnet, &addr).unwrap();
        assert_eq!(script.as_bytes()[0], 0x76); // P2PKH
    }

    fn decode_required_or(text: &str, prefix: &str) -> (String, u8, Vec<u8>) {
        let (p, v, h) = crate::cash::decode_cashaddr(text).expect("decode");
        assert_eq!(p, prefix);
        (p, v, h)
    }

    #[test]
    fn network_mismatch_rejected() {
        // ectest-адрес в кошельке mainnet — отказ.
        let mut hash = [0u8; 20];
        hash.copy_from_slice(
            &hex::decode("751e76e8199196d454941c45d1b3a323f1433bd6").expect("hex"),
        );
        let testnet_addr = crate::cash::cashaddr_encode(PREFIX_TESTNET, 0x00, &hash).unwrap();
        let err = xec_recipient_script(XecNetwork::Mainnet, &testnet_addr);
        assert!(matches!(
            err,
            Err(ChainError::AddressNetworkMismatch("eCash testnet3"))
        ));
    }

    #[test]
    fn legacy_cross_check() {
        // Legacy `1…` (0x00) даёт тот же P2PKH-скрипт, что cashaddr.
        let legacy = "1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu";
        let script_legacy = xec_recipient_script(XecNetwork::Mainnet, legacy).unwrap();
        let hash = crate::cash::base58check_decode(legacy).unwrap();
        let mut h = [0u8; 20];
        h.copy_from_slice(&hash[1..]);
        let cash_addr = cashaddr_pkh(PREFIX_MAINNET, &h).unwrap();
        let script_cash = xec_recipient_script(XecNetwork::Mainnet, &cash_addr).unwrap();
        assert_eq!(script_cash.as_bytes(), script_legacy.as_bytes());
    }

    #[test]
    fn derivation_matches_slip44() {
        // Путь в derive_address должен содержать coin type 899.
        // (Сам адрес нефиксирован в паспорте — проверяем формат строки пути.)
        let account = BchLikeTest::account();
        let addr = account.derive_address(0, 0).unwrap();
        assert!(
            addr.path.starts_with("m/44'/899'/0'/0/0"),
            "path: {}",
            addr.path
        );
        assert!(addr.address.starts_with("ecash:q"));
    }

    struct BchLikeTest;
    impl BchLikeTest {
        fn account() -> XecAccount {
            XecAccount::from_seed(&[7u8; 64], XecNetwork::Mainnet, 0).expect("account")
        }
    }
}
