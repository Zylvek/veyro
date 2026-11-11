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

    /// First block hash of the chain, per `docs/coins/BTC.md` (genesis
    /// vectors are pinned there). Hex here is written in the conventional
    /// big-endian display order, byte 0 first — same order Electrum reports
    /// `genesis_hash` bytes in. Used to verify an Electrum server really
    /// serves the network the user configured: a mismatch means the server
    /// must not be used (fund-safety).
    pub fn genesis_hash(self) -> [u8; 32] {
        const MAINNET: &str =
            "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f";
        const TESTNET3: &str =
            "000000000933ea01ad0ee984209779baaec3ced90fa3f408719526f8d77f4943";
        const TESTNET4: &str =
            "00000000da84f2bafbbc53dee25a72ae507ff4914b867c565be350b0da8bf043";
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

/// Server identity/tip, reported to the UI ("network info" screen).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GatewayNetworkInfo {
    pub server_version: String,
    pub protocol_min: String,
    pub protocol_max: String,
    pub tip_height: u32,
    /// Genesis hash as the server reports it (network sanity check).
    pub genesis_hash: [u8; 32],
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

    fn script_balance(&self, script: &[u8]) -> Result<ScriptBalance, ChainError>;
    fn script_utxos(&self, script: &[u8]) -> Result<Vec<Utxo>, ChainError>;
    fn script_history(&self, script: &[u8]) -> Result<Vec<HistoryEntry>, ChainError>;

    /// Fetch a transaction by id; `None` if the server does not know it.
    fn tx_by_id(&self, txid: &Txid) -> Result<Option<Transaction>, ChainError>;

    fn broadcast(&self, tx: &Transaction) -> Result<Txid, ChainError>;

    /// Convenience: everything the "network info" screen shows at once.
    fn network_info(&self) -> Result<GatewayNetworkInfo, ChainError> {
        let (server_version, protocol_min, protocol_max, genesis_hash) =
            self.server_features()?;
        let tip_height = self.tip_height()?;
        Ok(GatewayNetworkInfo {
            server_version,
            protocol_min,
            protocol_max,
            tip_height,
            genesis_hash,
        })
    }

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

/// Production gateway over the `electrum-client` crate.
pub struct ElectrumGateway {
    client: electrum_client::Client,
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
        let client = electrum_client::Client::new(url)
            .map_err(|e| ChainError::Transport(format!("{url}: {e}")))?;
        Ok(Self {
            client,
            network,
            url: url.to_string(),
        })
    }

    pub fn url(&self) -> &str {
        &self.url
    }
}

impl Gateway for ElectrumGateway {
    fn network(&self) -> BtcNetwork {
        self.network
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
        let notif = self
            .client
            .block_headers_subscribe()
            .map_err(|e| ChainError::Protocol(e.to_string()))?;
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
            // electrum-client surfaces "unknown transaction"/"no such tx" as an
            // error with the reason in text; treat absence indicators as None.
            // Any other error is a real transport/protocol failure.
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
