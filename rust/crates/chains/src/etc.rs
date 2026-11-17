//! ETC (Ethereum Classic) адаптер: EVM-стек по паспорту docs/coins/ETC.md.
//!
//! Сетка: публичный JSON-RPC через HTTPS (TLS-only, как Electrum-политика);
//! genesis/chainId проверка на входе (fund-safety 1:1 с Electrum-адаптерами).
//! Баланс/nonce/газ/отправка — RPC; история нативных переводов — BlockScout
//! REST v2 (etc.blockscout.com, проверен 11.11.2026). Только legacy-транзакции
//! (EIP-1559 НЕ активирован на ETC, baseFee = 0 — паспорт). Секреты не живут
//! в аккаунте: адреса деривируются из xpub, подпись приходит per-call от seed
//! (тот же паттерн, что у RvnAccount).
//!
//! Единицы: wei (u128); отображение (18 знаков, 1 ETC = 1e18 wei) — слой UI.
//! Нативные переводы ETC; ERC-20/смарт-контракты — честно вне scope.

use sha3::{Digest, Keccak256};
use std::io::Read;
use zeroize::Zeroizing;

use crate::ChainError;
use ::bitcoin::bip32::{ChildNumber, DerivationPath, Xpriv, Xpub};

/// SLIP-44 coin type ETC (паспорт §Криптография, Trezor-таблица).
pub const ETC_COIN_TYPE: u32 = 61;

/// Chain ID 61 — проверено RPC 2026-11-11 (eth_chainId, два эндпоинта).
pub const ETC_MAINNET_CHAIN_ID: u64 = 61;
/// Mordor testnet, chain ID 63 (RPC-проверено 2026-11-11).
pub const MORDOR_CHAIN_ID: u64 = 63;

/// Канонический генезис исходной Ethereum-цепи (ETC продолжает её);
/// получен напрямую eth_getBlockByNumber("0x0") на двух эндпоинтах.
pub const ETC_MAINNET_GENESIS_HEX: &str =
    "0xd4e56740f876aef8c010b86a40d5f56745a118d0906a34e69aec8c0db1cb8fa3";
/// Генезис Mordor (extraData «phoenix chicken absurd banana», 2019-10-03).
pub const MORDOR_GENESIS_HEX: &str =
    "0xa68ebde7932eccb177d38d55dcc6461a019dd795a681e59b5a3e4f3a7259a3f1";

/// Перевод (не создание контрактов): 21000 газа — стандарт EVM; живой
/// estimateGas остаётся честной проверкой (см. EthGateway::estimate_gas).
pub const TRANSFER_GAS: u64 = 21_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EtcNetwork {
    Mainnet,
    Mordor,
}

impl EtcNetwork {
    pub fn chain_id(self) -> u64 {
        match self {
            EtcNetwork::Mainnet => ETC_MAINNET_CHAIN_ID,
            EtcNetwork::Mordor => MORDOR_CHAIN_ID,
        }
    }

    pub fn genesis_hex(self) -> &'static str {
        match self {
            EtcNetwork::Mainnet => ETC_MAINNET_GENESIS_HEX,
            EtcNetwork::Mordor => MORDOR_GENESIS_HEX,
        }
    }

    pub fn coin_type(self) -> u32 {
        ETC_COIN_TYPE
    }

    pub fn display_name(self) -> &'static str {
        match self {
            EtcNetwork::Mainnet => "Ethereum Classic",
            EtcNetwork::Mordor => "Mordor (ETC testnet)",
        }
    }

    /// HTTPS-only публичные кандидаты (проверены 2026-11-11 RPC-пробой;
    /// tls:// — обязательная политика, http:// отклоняется).
    pub fn preset_servers(self) -> &'static [&'static str] {
        match self {
            EtcNetwork::Mainnet => &[
                "https://etc.etcdesktop.com",
                "https://rpc.etcmc.xyz",
                "https://etc.blockscout.com/proxy",
            ],
            EtcNetwork::Mordor => &[
                "https://rpc.mordor.etccooperative.org",
                "https://geth-mordor.etc-network.info",
                "https://0xrpc.io/mordor",
            ],
        }
    }
}

// ---------------------------------------------------------------------------
// keccak-256 (Keccak-legacy padding — НЕ SHA3-256)
// ---------------------------------------------------------------------------

pub fn keccak256(data: &[u8]) -> [u8; 32] {
    let mut h = Keccak256::new();
    h.update(data);
    h.finalize().into()
}

/// keccak256("") — канонический вектор EVM: c5d246…a470 (unit-тест держит).
pub const KECCAK_EMPTY_HEX: &str =
    "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470";

// ---------------------------------------------------------------------------
// EIP-55 (чексумм-кодирование адреса через keccak низкого hex)
// ---------------------------------------------------------------------------

/// EIP-55: 0x + 40 символов, буквенные — верхний регистр, если соотв. тетрада
/// хэша ≥ 8. Векторы — из официального ERC-55 (erc-55.md, тест-кейсы).
pub fn eip55(addr20: &[u8; 20]) -> String {
    let hex_addr = hex::encode(addr20); // lowercase
    let hash = keccak256(hex_addr.as_bytes());
    let mut out = String::with_capacity(42);
    out.push('0');
    out.push('x');
    for (i, ch) in hex_addr.chars().enumerate() {
        // тетрада хэша, соответствующая позиции: полубайты старше-младше
        let nibble = if i % 2 == 0 {
            hash[i / 2] >> 4
        } else {
            hash[i / 2] & 0x0f
        };
        if ch.is_ascii_digit() {
            out.push(ch);
        } else if nibble >= 8 {
            out.push(ch.to_ascii_uppercase());
        } else {
            out.push(ch);
        }
    }
    out
}

/// Валидация EIP-55: обязательно 0x + 40 hex; если есть хоть одна буква —
/// чексумма обязана сойтись (нечувствительность к регистру при «all lower» /
/// «all caps» тоже принимается, как в ERC-55).
pub fn validate_eip55(s: &str) -> Result<[u8; 20], ChainError> {
    let Some(body) = s.strip_prefix("0x") else {
        return Err(ChainError::InvalidAddress(format!(
            "{s}: отсутствует префикс 0x (EVM)"
        )));
    };
    if body.len() != 40 || !body.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(ChainError::InvalidAddress(format!(
            "{s}: не 20-байтовый hex-адрес"
        )));
    }
    let lower = body.to_ascii_lowercase();
    let bytes =
        hex::decode(&lower).map_err(|e| ChainError::InvalidAddress(format!("{s}: hex: {e}")))?;
    let addr20: [u8; 20] = bytes
        .try_into()
        .map_err(|_| ChainError::InvalidAddress(format!("{s}: длина адреса не 20 байт")))?;
    let mixed = body.chars().any(|c| c.is_ascii_alphabetic())
        && body.chars().any(|c| c.is_ascii_lowercase())
        && body.chars().any(|c| c.is_ascii_uppercase());
    if mixed && eip55(&addr20) != format!("0x{body}") {
        return Err(ChainError::InvalidAddress(format!(
            "{s}: EIP-55 чексумма не сошлась"
        )));
    }
    Ok(addr20)
}

// ---------------------------------------------------------------------------
// RLP (энкодинг достаточно для legacy-tx: строки/целые/списки, длинные формы)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Rlp {
    Bytes(Vec<u8>),
    List(Vec<Rlp>),
}

/// Целое как RLP-строка с минимальным big-endian (0 → пустая строка).
pub fn rlp_int(value: u128) -> Rlp {
    if value == 0 {
        return Rlp::Bytes(Vec::new());
    }
    let be = value.to_be_bytes(); // 16 байт
    let first = be.iter().position(|&b| b != 0).expect("nonzero");
    Rlp::Bytes(be[first..].to_vec())
}

pub fn rlp_encode(item: &Rlp) -> Vec<u8> {
    match item {
        Rlp::Bytes(data) => rlp_bytes(data),
        Rlp::List(items) => {
            let payload: Vec<u8> = items.iter().flat_map(rlp_encode).collect();
            let mut out = length_prefix(payload.len(), 0xc0, 0xf7);
            out.extend_from_slice(&payload);
            out
        }
    }
}

fn rlp_bytes(data: &[u8]) -> Vec<u8> {
    if data.len() == 1 && data[0] < 0x80 {
        return data.to_vec();
    }
    let mut out = length_prefix(data.len(), 0x80, 0xb7);
    out.extend_from_slice(data);
    out
}

/// Префикс длины: < 56 — короткая форма, иначе 0x…7 + длина-длины (BE).
fn length_prefix(len: usize, base_short: u8, base_long: u8) -> Vec<u8> {
    if len < 56 {
        return vec![base_short + len as u8];
    }
    let be = (len as u64).to_be_bytes();
    let first = be.iter().position(|&b| b != 0).expect("len > 0");
    let len_of_len = be.len() - first;
    let mut out = Vec::with_capacity(1 + len_of_len);
    out.push(base_long + len_of_len as u8);
    out.extend_from_slice(&be[first..]);
    out
}

// ---------------------------------------------------------------------------
// Legacy-транзакция EIP-155
// ---------------------------------------------------------------------------

#[derive(Clone, PartialEq, Eq)]
pub struct LegacyTxIntent {
    pub nonce: u64,
    pub gas_price_wei: u128,
    pub gas_limit: u64,
    /// Адрес получателя; создание контрактов (to=null) не поддерживается.
    pub to: [u8; 20],
    pub value_wei: u128,
    /// Пустой для нативного перевода; не-пустой — только для честной
    /// оценки газа (см. estimate), продуктом не используется.
    pub data: Vec<u8>,
}

impl LegacyTxIntent {
    /// Данные для подписи: RLP из NОЛИ элементов (EIP-155 §Spec): цепочка
    /// (nonce, gasprice, startgas, to, value, data, chainid, 0, 0).
    /// Публично — для честных unit-векторов EIP-155.
    pub fn signing_payload(&self, chain_id: u64) -> Vec<u8> {
        let item = Rlp::List(vec![
            rlp_int(self.nonce as u128),
            rlp_int(self.gas_price_wei),
            rlp_int(self.gas_limit as u128),
            Rlp::Bytes(self.to.to_vec()),
            rlp_int(self.value_wei),
            Rlp::Bytes(self.data.clone()),
            rlp_int(chain_id as u128),
            rlp_int(0),
            rlp_int(0),
        ]);
        rlp_encode(&item)
    }

    /// Полный raw-транзакции: RLP из 9 элементов с v = chain_id*2 + 35 + parity.
    fn raw_tx(
        &self,
        chain_id: u64,
        rec_parity: u8,
        sig64: &[u8; 64],
    ) -> Result<Vec<u8>, ChainError> {
        let parity = match rec_parity {
            0 => 0,
            1 => 1,
            other => {
                return Err(ChainError::Protocol(format!(
                    "recovery id {other} вне {{0,1}}"
                )))
            }
        };
        let (r_be, s_be) = sig64.split_at(32);
        // Минимальные формы r/s (без ведущих нулей) — как требует RLP.
        let r = rlp_trim_be(r_be);
        let s = rlp_trim_be(s_be);
        let item = Rlp::List(vec![
            rlp_int(self.nonce as u128),
            rlp_int(self.gas_price_wei),
            rlp_int(self.gas_limit as u128),
            Rlp::Bytes(self.to.to_vec()),
            rlp_int(self.value_wei),
            Rlp::Bytes(self.data.clone()),
            rlp_int((chain_id * 2 + 35 + parity as u64) as u128),
            Rlp::Bytes(r),
            Rlp::Bytes(s),
        ]);
        Ok(rlp_encode(&item))
    }
}

fn trim_leading_zeros(be: &[u8]) -> Vec<u8> {
    let first = be.iter().position(|&b| b != 0).unwrap_or(be.len());
    be[first..].to_vec()
}

/// Минимальная BE-форма целого (v/r/s) — pub для честных векторов и моста.
pub fn rlp_trim_be(be: &[u8]) -> Vec<u8> {
    trim_leading_zeros(be)
}

/// Двухшаговая подпись (как в cash/litecoin-адаптерах): отдельная derivation
/// secrets, отдельное подписание. Секрет возвращается Zeroizing, не логируется.
pub fn etc_secret_key(
    seed: &[u8; 64],
    network: EtcNetwork,
    account: u32,
    index: u32,
) -> Result<(Zeroizing<[u8; 32]>, String), ChainError> {
    let hardened = |i: u32| -> Result<ChildNumber, ChainError> {
        ChildNumber::from_hardened_idx(i)
            .map_err(|e| ChainError::KeyDerivation(format!("hardened child {i}: {e}")))
    };
    let normal = |i: u32| -> Result<ChildNumber, ChainError> {
        ChildNumber::from_normal_idx(i)
            .map_err(|e| ChainError::KeyDerivation(format!("normal child {i}: {e}")))
    };
    let path: DerivationPath = [
        hardened(44)?,
        hardened(network.coin_type())?,
        hardened(account)?,
        normal(0)?,
        normal(index)?,
    ]
    .into_iter()
    .collect();
    let secp = ::bitcoin::secp256k1::Secp256k1::new();
    let master = Xpriv::new_master(::bitcoin::Network::Bitcoin, seed)
        .map_err(|e| ChainError::KeyDerivation(format!("master key: {e}")))?;
    let key = master
        .derive_priv(&secp, &path)
        .map_err(|e| ChainError::KeyDerivation(format!("path derivation: {e}")))?;
    let child_xpub = Xpub::from_priv(&secp, &key);
    let from = address_of_pubkey(&child_xpub.public_key);
    let mut raw = [0u8; 32];
    raw.copy_from_slice(&key.private_key.secret_bytes());
    Ok((Zeroizing::new(raw), from))
}

/// Подписание намерения нативного перевода секретом (EIP-155,
/// v = chainId*2 + 35 + parity). Возвращает (raw 0x…, txhash 0x…, from).
pub fn etc_sign_transfer(
    secret32: &Zeroizing<[u8; 32]>,
    network: EtcNetwork,
    intent: LegacyTxIntent,
) -> Result<(String, String, String), ChainError> {
    let (raw, _sig64, _parity, txhash, from) =
        etc_sign_transfer_parts(secret32, network.chain_id(), intent)?;
    Ok((raw, txhash, from))
}

/// Внутренний механизм подписи (chain_id напрямую — для честных векторов
/// EIP-155 на произвольной цепи). Возвращает (raw, sig64, parity, from).
#[doc(hidden)]
pub fn etc_sign_transfer_parts(
    secret32: &Zeroizing<[u8; 32]>,
    chain_id: u64,
    intent: LegacyTxIntent,
) -> Result<(String, [u8; 64], u8, String, String), ChainError> {
    if !intent.data.is_empty() {
        return Err(ChainError::Protocol(
            "не-пустой data в нативном переводе — смарт-контракты вне scope".into(),
        ));
    }
    if intent.gas_limit < TRANSFER_GAS {
        return Err(ChainError::Protocol(format!(
            "gas_limit {} < минимума перевода {TRANSFER_GAS}",
            intent.gas_limit
        )));
    }
    let secp = ::bitcoin::secp256k1::Secp256k1::new();
    let secret = ::bitcoin::secp256k1::SecretKey::from_slice(secret32.as_ref())
        .map_err(|e| ChainError::KeyDerivation(format!("secret: {e}")))?;
    let from = address_of_pubkey(&::bitcoin::secp256k1::PublicKey::from_secret_key(
        &secp, &secret,
    ));

    // Подпись: keccak(signing_payload) → ECDSA secp256k1 recoverable
    // (parity входит в v по EIP-155).
    let signing_hash = keccak256(&intent.signing_payload(chain_id));
    let msg = ::bitcoin::secp256k1::Message::from_digest(signing_hash);
    let (rec, sig64) = secp
        .sign_ecdsa_recoverable(&msg, &secret)
        .serialize_compact();
    let raw = intent.raw_tx(chain_id, rec.to_i32() as u8, &sig64)?;
    let raw_hex = format!("0x{}", hex::encode(&raw));
    let tx_hash_hex = format!("0x{}", hex::encode(keccak256(&raw)));
    Ok((raw_hex, sig64, rec.to_i32() as u8, tx_hash_hex, from))
}

/// Адрес EVM по compressed-публичнику: keccak(uncompressed[1..65])[12..32].
/// Публично: мост честно показывает 0x-hex; EIP-55-отображение — derive_address.
pub fn address_of_pubkey(pk: &::bitcoin::secp256k1::PublicKey) -> String {
    let uncompressed = pk.serialize_uncompressed(); // 65 байт, [0]=0x04
    let digest = keccak256(&uncompressed[1..]);
    let mut addr20 = [0u8; 20];
    addr20.copy_from_slice(&digest[12..32]);
    format!("0x{}", hex::encode(addr20)) // честно без чексуммы здесь;
                                         // EIP-55-отображение возвращает derive_address (там же валидация)
}

/// Аккаунт ETC: только xpub (секрет не живёт) — как RvnAccount.
pub struct EtcAccount {
    pub network: EtcNetwork,
    pub account: u32,
    account_xpub: Xpub,
}

#[derive(Debug, Clone)]
pub struct EtcDerivedAddress {
    /// EIP-55 чексумм-адрес (то, что показывает UI).
    pub address: String,
    /// 20 байт для RPC-вызовов (владелец — ядро).
    pub addr20: [u8; 20],
    pub index: u32,
    pub path: String,
}

impl EtcAccount {
    pub fn from_seed(
        seed: &[u8; 64],
        network: EtcNetwork,
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

    pub fn network(&self) -> EtcNetwork {
        self.network
    }

    /// m/44'/61'/<account>'/0/<index> → EIP-55 адрес (без секрета).
    pub fn derive_address(&self, index: u32) -> Result<EtcDerivedAddress, ChainError> {
        let normal = |i: u32| -> Result<ChildNumber, ChainError> {
            ChildNumber::from_normal_idx(i)
                .map_err(|e| ChainError::key(format!("normal child {i}: {e}")))
        };
        let path: DerivationPath = [normal(0)?, normal(index)?].into_iter().collect();
        let secp = ::bitcoin::secp256k1::Secp256k1::verification_only();
        let child = self
            .account_xpub
            .derive_pub(&secp, &path)
            .map_err(|e| ChainError::key(format!("xpub child: {e}")))?;
        let addr_plain = address_of_pubkey(&child.public_key);
        // EIP-55 поверх честного lowercase-адреса
        let mut addr20 = [0u8; 20];
        hex::decode_to_slice(&addr_plain[2..], &mut addr20)
            .map_err(|e| ChainError::key(format!("address hex: {e}")))?;
        Ok(EtcDerivedAddress {
            address: eip55(&addr20),
            addr20,
            index,
            path: format!(
                "m/44'/{coin}'/{account}'/0/{index}",
                coin = self.network.coin_type(),
                account = self.account,
                index = index
            ),
        })
    }
}

// ---------------------------------------------------------------------------
// JSON-RPC транспорт (TLS-only: https://) + genesis-проверка
// ---------------------------------------------------------------------------

const RPC_BODY_CAP: usize = 2 * 1024 * 1024;

pub struct EtcGateway {
    url: String,
    network: EtcNetwork,
}

#[derive(Debug, Clone)]
pub struct EtcReceipt {
    pub status_success: bool,
    pub block_number: Option<u64>,
}

impl EtcGateway {
    /// Подключение с честной fund-safety-проверкой: eth_chainId и генезис.
    pub fn connect(url: &str, network: EtcNetwork) -> Result<Self, ChainError> {
        if url.trim().is_empty() {
            return Err(ChainError::InvalidServerUrl("empty url".into()));
        }
        if !url.to_ascii_lowercase().starts_with("https://") {
            return Err(ChainError::InvalidServerUrl(format!(
                "{url} (expected https:// — TLS-only policy)"
            )));
        }
        let gw = Self {
            url: url.to_string(),
            network,
        };
        gw.verify_chain(network)?;
        Ok(gw)
    }

    pub fn url(&self) -> &str {
        &self.url
    }

    pub fn network(&self) -> EtcNetwork {
        self.network
    }

    /// Один JSON-RPC POST с границей тела (2 МиБ) и честными ошибками.
    fn rpc(
        &self,
        method: &str,
        params: Vec<serde_json::Value>,
    ) -> Result<serde_json::Value, ChainError> {
        let body = serde_json::json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params,
        });
        let resp = ureq::post(&self.url)
            .set("Content-Type", "application/json")
            .timeout(::std::time::Duration::from_secs(20))
            .send_json(body)
            .map_err(|e| ChainError::Transport(format!("{method}: {e}")))?;
        let mut buf: Vec<u8> = Vec::new();
        resp.into_reader()
            .take(RPC_BODY_CAP as u64 + 1)
            .read_to_end(&mut buf)
            .map_err(|e| ChainError::Transport(format!("{method}: body: {e}")))?;
        if buf.len() > RPC_BODY_CAP {
            return Err(ChainError::Transport(format!(
                "{method}: ответ превышает границу {RPC_BODY_CAP} байт"
            )));
        }
        let json: serde_json::Value = serde_json::from_slice(&buf)
            .map_err(|e| ChainError::Protocol(format!("{method}: json: {e}")))?;
        if let Some(err) = json.get("error") {
            return Err(ChainError::Protocol(format!("{method}: rpc error: {err}")));
        }
        json.get("result")
            .cloned()
            .ok_or_else(|| ChainError::Protocol(format!("{method}: в ответе нет result")))
    }

    fn verify_chain(&self, network: EtcNetwork) -> Result<(), ChainError> {
        let chain_raw = self.rpc("eth_chainId", vec![])?;
        let chain_hex = chain_raw
            .as_str()
            .ok_or_else(|| ChainError::Protocol(format!("eth_chainId не строка: {chain_raw}")))?;
        let chain_hex = chain_hex.trim_start_matches("0x").to_string();
        let got = u64::from_str_radix(&chain_hex, 16)
            .map_err(|e| ChainError::Protocol(format!("eth_chainId: {e}")))?;
        let expected = network.chain_id();
        if got != expected {
            return Err(ChainError::Protocol(format!(
                "chainId {got} ≠ ожидаемого {expected} ({}) — отказ (fund-safety)",
                network.display_name()
            )));
        }
        // Генезис блок: честная проверка, что сервер на той же цепи.
        let block = self.rpc("eth_getBlockByNumber", vec!["0x0".into(), false.into()])?;
        let hash = block
            .get("hash")
            .and_then(|h| h.as_str())
            .ok_or_else(|| ChainError::Protocol("genesis: нет hash".into()))?;
        if !hash.eq_ignore_ascii_case(network.genesis_hex()) {
            return Err(ChainError::Protocol(format!(
                "genesis {hash} не совпал с официальным {} — отказ (fund-safety)",
                network.genesis_hex()
            )));
        }
        Ok(())
    }

    pub fn block_number(&self) -> Result<u64, ChainError> {
        let raw = self.rpc("eth_blockNumber", vec![])?;
        hex_u128("eth_blockNumber", raw.as_str()).map(|v| v as u64)
    }

    /// Баланс в wei (u128 честно; floats нет).
    pub fn balance_wei(&self, addr20: &[u8; 20], pending: bool) -> Result<u128, ChainError> {
        let tag = if pending { "pending" } else { "latest" };
        let raw = self.rpc(
            "eth_getBalance",
            vec![format!("0x{}", hex::encode(addr20)).into(), tag.into()],
        )?;
        hex_u128("eth_getBalance", raw.as_str())
    }

    /// Nonce (эхо-защита повторов: включаем pending-счётчик).
    pub fn nonce(&self, addr20: &[u8; 20]) -> Result<u64, ChainError> {
        let raw = self.rpc(
            "eth_getTransactionCount",
            vec![
                format!("0x{}", hex::encode(addr20)).into(),
                "pending".into(),
            ],
        )?;
        hex_u128("eth_getTransactionCount", raw.as_str()).map(|v| v as u64)
    }

    pub fn gas_price_wei(&self) -> Result<u128, ChainError> {
        let raw = self.rpc("eth_gasPrice", vec![])?;
        hex_u128("eth_gasPrice", raw.as_str())
    }

    /// Честная оценка газа от сервера; без выдуманных fallback'ов —
    /// ошибка транслируется наверх для честного интерфейса.
    pub fn estimate_gas(
        &self,
        from_addr20: &[u8; 20],
        intent: &LegacyTxIntent,
    ) -> Result<u64, ChainError> {
        let mut tx = serde_json::json!({
            "from": format!("0x{}", hex::encode(from_addr20)),
            "to": format!("0x{}", hex::encode(intent.to)),
            "value": format_hex_q(intent.value_wei),
            "gasPrice": format_hex_q(intent.gas_price_wei),
        });
        if !intent.data.is_empty() {
            tx["data"] = format!("0x{}", hex::encode(&intent.data)).into();
        }
        let raw = self.rpc("eth_estimateGas", vec![tx])?;
        hex_u128("eth_estimateGas", raw.as_str()).map(|v| v as u64)
    }

    /// Идемпотентность как в BTC-адаптере: pre-probe getTransactionReceipt
    /// уже возвращает статус, повтор не обязателен; сервер честно отражает.
    pub fn send_raw(&self, raw_hex: &str) -> Result<String, ChainError> {
        let raw = self.rpc("eth_sendRawTransaction", vec![raw_hex.into()])?;
        raw.as_str()
            .map(|s| s.to_string())
            .ok_or_else(|| ChainError::Protocol("eth_sendRawTransaction: нет хэша".into()))
    }

    /// None = транзакции в mempool нет (honest, как is_missing_tx_error).
    pub fn receipt(&self, txhash: &str) -> Result<Option<EtcReceipt>, ChainError> {
        let raw = self.rpc("eth_getTransactionReceipt", vec![txhash.into()])?;
        if raw.is_null() {
            return Ok(None);
        }
        let status = raw
            .get("status")
            .and_then(|s| s.as_str())
            .map(|s| s.trim_start_matches("0x"))
            .unwrap_or("");
        let status_success = u128::from_str_radix(status, 16).unwrap_or(0) == 1;
        let block_number = raw
            .get("blockNumber")
            .and_then(|b| b.as_str())
            .map(|b| u128::from_str_radix(b.trim_start_matches("0x"), 16).unwrap_or(0) as u64);
        Ok(Some(EtcReceipt {
            status_success,
            block_number,
        }))
    }
}

// ---------------------------------------------------------------------------
// hex-хелперы (wei из "0x…", вывод без ведущих нулей)
// ---------------------------------------------------------------------------

fn hex_u128(method: &str, raw: Option<&str>) -> Result<u128, ChainError> {
    let s = raw.ok_or_else(|| ChainError::Protocol(format!("{method}: не строка")))?;
    let digits = s.trim_start_matches("0x");
    u128::from_str_radix(digits, 16)
        .map_err(|e| ChainError::Protocol(format!("{method}: '{s}': {e}")))
}

fn format_hex_q(v: u128) -> String {
    if v == 0 {
        "0x0".to_string()
    } else {
        format!("0x{v:x}")
    }
}

// ---------------------------------------------------------------------------
// История: BlockScout REST v2 (etc.blockscout.com) — нативные переводы
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct EtcHistoryEntry {
    pub hash: String,
    pub from: String,
    pub to: String,
    pub value_wei: u128,
    pub block_number: Option<u64>,
    pub status_success: Option<bool>,
    pub fee_wei: Option<u128>,
    pub timestamp: Option<String>,
}

/// Свежая история адреса (нативные переводы ETC) с честной усечённостью.
/// `base` = "https://etc.blockscout.com/api/v2". Пагинация BlockScout:
/// если hasNextPage, клиент честно показывает «latest N of M» (total).
pub fn blockscout_history(
    base: &str,
    addr20: &[u8; 20],
) -> Result<(Vec<EtcHistoryEntry>, usize /*total*/), ChainError> {
    let addr = format!("0x{}", hex::encode(addr20));
    let url = format!("{base}/addresses/{addr}/transactions");
    let resp = ureq::get(&url)
        .timeout(::std::time::Duration::from_secs(20))
        .call()
        .map_err(|e| ChainError::Transport(format!("blockscout: {e}")))?;
    let mut buf: Vec<u8> = Vec::new();
    resp.into_reader()
        .take(RPC_BODY_CAP as u64 + 1)
        .read_to_end(&mut buf)
        .map_err(|e| ChainError::Transport(format!("blockscout: body: {e}")))?;
    if buf.len() > RPC_BODY_CAP {
        return Err(ChainError::Transport(format!(
            "blockscout: ответ превышает границу {RPC_BODY_CAP} байт"
        )));
    }
    let json: serde_json::Value = serde_json::from_slice(&buf)
        .map_err(|e| ChainError::Protocol(format!("blockscout: json: {e}")))?;
    let items = json
        .get("items")
        .and_then(|i| i.as_array())
        .cloned()
        .unwrap_or_default();
    let total = json
        .get("total")
        .and_then(|t| t.as_u64())
        .unwrap_or(items.len() as u64) as usize;
    let mut out = Vec::with_capacity(items.len());
    for it in &items {
        let hash = it
            .get("hash")
            .and_then(|h| h.as_str())
            .unwrap_or("")
            .to_string();
        if hash.is_empty() {
            continue; // честный пропуск неполных записей
        }
        let value_wei = it
            .get("value")
            .and_then(|v| v.as_str())
            .and_then(|v| u128::from_str_radix(v.trim_start_matches("0x"), 16).ok())
            .unwrap_or(0);
        let from = it
            .pointer("/from/hash")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let to = it
            .pointer("/to/hash")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let block_number = it.get("block_number").and_then(|b| b.as_u64());
        let status_success = it
            .get("status")
            .and_then(|s| s.as_str())
            .map(|s| s.eq_ignore_ascii_case("success"));
        let fee_wei = it
            .get("fee")
            .and_then(|d| d.as_str())
            .and_then(|f| f.parse::<u128>().ok());
        let timestamp = it
            .get("timestamp")
            .and_then(|t| t.as_str())
            .map(|s| s.to_string());
        out.push(EtcHistoryEntry {
            hash,
            from,
            to,
            value_wei,
            block_number,
            status_success,
            fee_wei,
            timestamp,
        });
    }
    Ok((out, total))
}
