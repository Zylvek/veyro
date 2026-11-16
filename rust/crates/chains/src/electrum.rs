//! Electrum gateway: the light-server interface every BTC flow reads through.
//!
//! The protocol (Electrum JSON-RPC over TCP/TLS) only ever sees **public**
//! material: script hashes, transaction payloads, fee queries. Seeds and key
//! material never reach this module.
//!
//! The [`Gateway`] trait exists so the scan/build/sign logic can be unit-tested
//! against an in-memory fake (no network), while the production implementation
//! wraps the audited `electrum-client` crate.
//!
//! Network presets are copied from the live-verified server list of
//! `docs/coins/BTC.md` (checked 2026-11-11). Users can always configure their
//! own server (stored in `storage.node_endpoints`).

use crate::ChainError;
use ::bitcoin::{Transaction, Txid};
use electrum_client::ElectrumApi;

/// Bitcoin network variant supported by this adapter. Testnet3 and Testnet4
/// are separate networks (different genesis/ports) — mixing them up is a
/// user-funds hazard, so every API point carries the network explicitly.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BtcNetwork {
    Mainnet,
    Testnet,
    Testnet4,
}

impl BtcNetwork {
    /// `bitcoin::Network` equivalent for address/transaction handling.
    pub fn bitcoin_network(self) -> bitcoin::Network {
        match self {
            BtcNetwork::Mainnet => bitcoin::Network::Bitcoin,
            BtcNetwork::Testnet => bitcoin::Network::Testnet,
            BtcNetwork::Testnet4 => bitcoin::Network::Testnet4,
        }
    }

    /// SLIP-44 style BIP84 coin type: `0` mainnet, `1` any testnet
    /// (BIP84 test vector convention: testnet derivation is m/84'/1'/…).
    pub fn coin_type(self) -> u32 {
        match self {
            BtcNetwork::Mainnet => 0,
            BtcNetwork::Testnet | BtcNetwork::Testnet4 => 1,
        }
    }

    /// Display name used in error messages (`AddressNetworkMismatch` etc.).
    pub fn display_name(self) -> &'static str {
        match self {
            BtcNetwork::Mainnet => "Bitcoin mainnet",
            BtcNetwork::Testnet => "Bitcoin testnet3",
            BtcNetwork::Testnet4 => "Bitcoin testnet4",
        }
    }

    /// Stable wire/UI code: `0` mainnet, `1` testnet3, `2` testnet4.
    /// Documented in the bridge (`network_from_code`).
    pub fn code(self) -> u32 {
        match self {
            BtcNetwork::Mainnet => 0,
            BtcNetwork::Testnet => 1,
            BtcNetwork::Testnet4 => 2,
        }
    }

    /// Inverse of [`BtcNetwork::code`]; `None` for any other value.
    pub fn from_code(code: u32) -> Option<Self> {
        match code {
            0 => Some(BtcNetwork::Mainnet),
            1 => Some(BtcNetwork::Testnet),
            2 => Some(BtcNetwork::Testnet4),
            _ => None,
        }
    }

    /// First block hash of the chain, per `docs/coins/BTC.md` (genesis
    /// vectors are pinned there). Hex here is written in the conventional
    /// big-endian display order, byte 0 first — same order Electrum reports
    /// `genesis_hash` bytes in. Used to verify an Electrum server really
    /// serves the network the user configured: a mismatch means the server
    /// must not be used (fund-safety).
    pub fn genesis_hash(self) -> [u8; 32] {
        const MAINNET: &str = "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f";
        const TESTNET3: &str = "000000000933ea01ad0ee984209779baaec3ced90fa3f408719526f8d77f4943";
        const TESTNET4: &str = "00000000da84f2bafbbc53dee25a72ae507ff4914b867c565be350b0da8bf043";
        let hex64 = match self {
            BtcNetwork::Mainnet => MAINNET,
            BtcNetwork::Testnet => TESTNET3,
            BtcNetwork::Testnet4 => TESTNET4,
        };
        let mut out = [0u8; 32];
        let bytes = hex::decode(hex64).expect("genesis hash hex is valid");
        out.copy_from_slice(&bytes);
        out
    }

    /// Live-verified public Electrum presets (docs/coins/BTC.md, 2026-11-11).
    /// Testnet entries are verified before the E2E run and documented there.
    pub fn preset_servers(self) -> &'static [&'static str] {
        match self {
            BtcNetwork::Mainnet => &[
                "ssl://electrum.qtornado.com:50002",
                "ssl://fulcrum.bullbitcoin.com:50002",
                "ssl://vps.hsmiths.com:50002",
            ],
            BtcNetwork::Testnet => &["ssl://electrum.blockstream.info:60002"],
            BtcNetwork::Testnet4 => &[],
        }
    }
}

/// Failover candidates for reconnects: the live-verified presets of the
/// network, rotated so the server that just failed goes last. A network with
/// a single preset yields just that preset (a dropped socket does not
/// necessarily mean the server is dead).
pub fn failover_candidates(network: BtcNetwork, failed_url: &str) -> Vec<String> {
    let mut list: Vec<String> = network
        .preset_servers()
        .iter()
        .map(|s| s.to_string())
        .collect();
    if let Some(pos) = list.iter().position(|u| u == failed_url) {
        let removed = list.remove(pos);
        list.push(removed);
    }
    list
}

/// Balance of one script, as Electrum reports it (satoshis).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ScriptBalance {
    pub confirmed_sat: u64,
    pub unconfirmed_sat: i64,
}

/// Unspent output as seen by Electrum (satoshis, no floats).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Utxo {
    pub txid: Txid,
    pub vout: u32,
    pub value_sat: u64,
    /// Block height the funding transaction is confirmed at (`None` = mempool).
    pub height: Option<u32>,
}

/// One history occurrence of a script (funding or spending tx).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HistoryEntry {
    pub txid: Txid,
    /// Block height (`-1` = unconfirmed/mempool, `0` = conflicted per Electrum).
    pub height: i64,
}

/// Outcome of a broadcast, made explicit for the double-send guard.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BroadcastOutcome {
    /// The network accepted a new transaction.
    Sent(Txid),
    /// The transaction was already known to the network (mempool/chain) —
    /// no second submission was made.
    AlreadyKnown(Txid),
}

/// Transport-agnostic view of an Electrum server. Production type: [`ElectrumGateway`].
pub trait Gateway {
    /// Which network this gateway is bound to (set up by the caller).
    fn network(&self) -> BtcNetwork;

    /// `server.version`/`server.features` — identity + genesis of the server.
    fn server_features(&self) -> Result<(String, String, String, [u8; 32]), ChainError>;

    /// Known tip height via `blockchain.headers.subscribe` (one-shot snapshot).
    fn tip_height(&self) -> Result<u32, ChainError>;

    /// `blockchain.estimatefee(blocks)` in **BTC per kilobyte** (protocol unit).
    /// A negative return means "unknown" for this depth.
    fn estimate_fee_btc_per_kb(&self, blocks: u32) -> Result<f64, ChainError>;

    /// Several fee depths in ONE round-trip (production clients batch the
    /// `blockchain.estimatefee` calls; the default falls back to sequential
    /// [`Gateway::estimate_fee_btc_per_kb`]).
    fn estimate_fees_batch(&self, blocks: &[u32]) -> Result<Vec<f64>, ChainError> {
        blocks
            .iter()
            .map(|b| self.estimate_fee_btc_per_kb(*b))
            .collect()
    }

    fn script_balance(&self, script: &[u8]) -> Result<ScriptBalance, ChainError>;
    fn script_utxos(&self, script: &[u8]) -> Result<Vec<Utxo>, ChainError>;
    fn script_history(&self, script: &[u8]) -> Result<Vec<HistoryEntry>, ChainError>;

    /// Batch of `script_balance` — one round-trip when the transport
    /// supports Electrum batches (Fulcrum/ElectrumX both do); the default
    /// implementation falls back to sequential single calls.
    fn script_balances_batch(&self, scripts: &[Vec<u8>]) -> Result<Vec<ScriptBalance>, ChainError> {
        scripts
            .iter()
            .map(|s| self.script_balance(s))
            .collect::<Result<Vec<_>, _>>()
    }

    /// Batch of `script_utxos` (same contract as above).
    fn script_utxos_batch(&self, scripts: &[Vec<u8>]) -> Result<Vec<Vec<Utxo>>, ChainError> {
        scripts
            .iter()
            .map(|s| self.script_utxos(s))
            .collect::<Result<Vec<_>, _>>()
    }

    /// Batch of `script_history` (same contract as above).
    fn script_histories_batch(
        &self,
        scripts: &[Vec<u8>],
    ) -> Result<Vec<Vec<HistoryEntry>>, ChainError> {
        scripts
            .iter()
            .map(|s| self.script_history(s))
            .collect::<Result<Vec<_>, _>>()
    }

    /// Fetch a transaction by id; `None` if the server does not know it.
    fn tx_by_id(&self, txid: &Txid) -> Result<Option<Transaction>, ChainError>;

    /// Fetch multiple transactions in one pass; `None` entries = the server
    /// does not know that id. Default: sequential [`Gateway::tx_by_id`];
    /// production clients override this with batched calls.
    fn txs_by_ids(&self, txids: &[Txid]) -> Result<Vec<Option<Transaction>>, ChainError> {
        txids.iter().map(|id| self.tx_by_id(id)).collect()
    }

    fn broadcast(&self, tx: &Transaction) -> Result<Txid, ChainError>;

    /// Fund-safety: the server must actually be on the configured network.
    /// Returns the mismatch as a typed error; call this right after connect.
    fn verify_network(&self) -> Result<(), ChainError> {
        let (_, _, _, server_genesis) = self.server_features()?;
        if server_genesis == self.network().genesis_hash() {
            Ok(())
        } else {
            Err(ChainError::Protocol(format!(
                "server genesis hash {} does not match {} — refusing to use it",
                hex::encode(server_genesis),
                self.network().display_name()
            )))
        }
    }
}

/// Production gateway over the `electrum-client` crate. Cloneable (the
/// client is shared behind an `Arc`) — cheap snapshots for the bridge session.
#[derive(Clone)]
pub struct ElectrumGateway {
    client: std::sync::Arc<electrum_client::Client>,
    network: BtcNetwork,
    url: String,
}

// electrum-client is Sync (documented); expose as such for use behind &self.
impl std::fmt::Debug for ElectrumGateway {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ElectrumGateway")
            .field("network", &self.network)
            .field("url", &self.url)
            .finish()
    }
}

impl ElectrumGateway {
    /// Connect to an Electrum server. URL scheme selects the transport:
    /// `tcp://host:port` (plaintext) or `ssl://host:port` (rustls).
    /// Recommended: `ssl://` everywhere; testnet presets include only ssl.
    pub fn connect(url: &str, network: BtcNetwork) -> Result<Self, ChainError> {
        if url.trim().is_empty() {
            return Err(ChainError::InvalidServerUrl("empty url".into()));
        }
        let lower = url.to_ascii_lowercase();
        if !lower.starts_with("tcp://") && !lower.starts_with("ssl://") {
            return Err(ChainError::InvalidServerUrl(format!(
                "{url} (expected tcp:// or ssl:// scheme)"
            )));
        }
        // Явный таймаут вместо молчаливого зависания + авто-переподключение
        // фонового клиента: долгоживущая сессия обрывается серверами
        // (idle-таймаут публичных серверов), electrum-client сам ставит
        // соединение обратно (3 попытки с его задержками) — иначе после
        // первого разрыва ВСЕ вызовы синхронизации умирают с пустым
        // «AllAttemptsErrored» (наблюдение 15.11). Первое соединение
        // дополнительно подстраховано честным хэндшейк-бэкоффом ниже.
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
            network,
            url: url.to_string(),
        };

        // Живой хэндшейк с прогрессивным бэкоффом: публичные серверы
        // отрезают часть соединений (flaky «unexpected end of file»/
        // «EOF while parsing» — замечено на Fulcrum/electrs 15.11),
        // поэтому первый же сбой соединения не ломает вход: до трёх
        // попыток с паузами 0.7/1.4с, и только если все — честная
        // транспортная ошибка наружу.
        let mut wait = 700u64;
        for attempt in 0..3 {
            match gateway.server_features() {
                Ok(_) => return Ok(gateway),
                Err(e) => {
                    if attempt == 2 {
                        return Err(ChainError::Transport(format!("{url}: {e}")));
                    }
                    std::thread::sleep(std::time::Duration::from_millis(wait));
                    wait *= 2;
                }
            }
        }
        unreachable!("handshake loop returns on the last attempt");
    }

    pub fn url(&self) -> &str {
        &self.url
    }

    fn txs_batched(&self, txids: &[Txid]) -> Result<Vec<Option<Transaction>>, ChainError> {
        const TX_BATCH: usize = 10;
        let mut out: Vec<Option<Transaction>> = Vec::with_capacity(txids.len());
        for chunk in txids.chunks(TX_BATCH) {
            match self.client.batch_transaction_get(chunk.iter()) {
                Ok(txs) => out.extend(txs.into_iter().map(Some)),
                Err(_) => {
                    // Whole batch failed (server quirk / transport): degrade
                    // gracefully to per-id resolution for this chunk.
                    for id in chunk {
                        out.push(self.tx_by_id(id)?);
                    }
                }
            }
        }
        Ok(out)
    }
}

/// True when a `electrum-client` error means "the server does not know this
/// transaction". Only protocol/message errors qualify: I/O, DNS, EOF, timeout
/// and connection errors must surface as real errors, never as "tx missing".
pub fn is_missing_tx_error(e: &electrum_client::Error) -> bool {
    let text = match e {
        electrum_client::Error::Protocol(v) => match v.as_str() {
            Some(s) => s.to_string(),
            None => v.to_string(),
        },
        electrum_client::Error::Message(text) => text.clone(),
        _ => return false,
    };
    let t = text.to_ascii_lowercase();
    t.contains("no such")
        || t.contains("unknown transaction")
        || t.contains("not found")
        || t.contains("no transaction matching")
        || t.contains("tx not in block chain")
}

/// True when a `electrum-client` error is of transport/protocol kind that a
/// reconnect-and-retry can plausibly fix (server outage, dropped socket,
/// rate-limit EOF). Content errors (bad address, dust, insufficient funds)
/// are never transient.
pub fn is_transient_error(e: &electrum_client::Error) -> bool {
    matches!(
        e,
        electrum_client::Error::IOError(_)
            | electrum_client::Error::SharedIOError(_)
            | electrum_client::Error::AllAttemptsErrored(_)
            | electrum_client::Error::JSON(_)
    )
}

/// Single mapping point from `electrum-client` errors to `ChainError`:
/// transport-class failures become [`ChainError::Transport`] (the retry
/// signal), server-reported errors stay [`ChainError::Protocol`].
pub fn map_client_error(e: electrum_client::Error) -> ChainError {
    if is_transient_error(&e) {
        ChainError::Transport(e.to_string())
    } else {
        ChainError::Protocol(e.to_string())
    }
}

impl Gateway for ElectrumGateway {
    fn network(&self) -> BtcNetwork {
        self.network
    }

    fn txs_by_ids(&self, txids: &[Txid]) -> Result<Vec<Option<Transaction>>, ChainError> {
        self.txs_batched(txids)
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
        let notif = self
            .client
            .block_headers_subscribe()
            .map_err(crate::electrum::map_client_error)?;
        Ok(notif.height as u32)
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
            .map_err(crate::electrum::map_client_error)?;
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
            .map_err(crate::electrum::map_client_error)?;
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
            .map_err(crate::electrum::map_client_error)?;
        Ok(list
            .into_iter()
            .map(|h| HistoryEntry {
                txid: h.tx_hash,
                height: h.height as i64,
            })
            .collect())
    }

    fn script_balances_batch(&self, scripts: &[Vec<u8>]) -> Result<Vec<ScriptBalance>, ChainError> {
        let refs: Vec<&bitcoin::Script> = scripts
            .iter()
            .map(|s| bitcoin::Script::from_bytes(s))
            .collect();
        let list = self
            .client
            .batch_script_get_balance(refs)
            .map_err(crate::electrum::map_client_error)?;
        Ok(list
            .into_iter()
            .map(|b| ScriptBalance {
                confirmed_sat: b.confirmed,
                unconfirmed_sat: b.unconfirmed,
            })
            .collect())
    }

    fn script_histories_batch(
        &self,
        scripts: &[Vec<u8>],
    ) -> Result<Vec<Vec<HistoryEntry>>, ChainError> {
        let refs: Vec<&bitcoin::Script> = scripts
            .iter()
            .map(|s| bitcoin::Script::from_bytes(s))
            .collect();
        let list = self
            .client
            .batch_script_get_history(refs)
            .map_err(crate::electrum::map_client_error)?;
        Ok(list
            .into_iter()
            .map(|per| {
                per.into_iter()
                    .map(|h| HistoryEntry {
                        txid: h.tx_hash,
                        height: h.height as i64,
                    })
                    .collect()
            })
            .collect())
    }

    fn script_utxos_batch(&self, scripts: &[Vec<u8>]) -> Result<Vec<Vec<Utxo>>, ChainError> {
        let refs: Vec<&bitcoin::Script> = scripts
            .iter()
            .map(|s| bitcoin::Script::from_bytes(s))
            .collect();
        let list = self
            .client
            .batch_script_list_unspent(refs)
            .map_err(crate::electrum::map_client_error)?;
        Ok(list
            .into_iter()
            .map(|per| {
                per.into_iter()
                    .map(|u| Utxo {
                        txid: u.tx_hash,
                        vout: u.tx_pos as u32,
                        value_sat: u.value,
                        height: (u.height > 0).then_some(u.height as u32),
                    })
                    .collect()
            })
            .collect())
    }

    fn tx_by_id(&self, txid: &Txid) -> Result<Option<Transaction>, ChainError> {
        match self.client.transaction_get(txid) {
            Ok(tx) => Ok(Some(tx)),
            // "Unknown transaction" is only trusted when the SERVER said it
            // (Protocol/Message errors). Transport failures (I/O, DNS, EOF,
            // timeouts) must never masquerade as "transaction missing".
            Err(e) => {
                if is_missing_tx_error(&e) {
                    Ok(None)
                } else {
                    Err(map_client_error(e))
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
