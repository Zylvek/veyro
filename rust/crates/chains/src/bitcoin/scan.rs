//! Address discovery (BIP44-style gap limit) and wallet state collection:
//! balances, spendable UTXOs and transaction history **with amounts**.
//!
//! Everything here talks to an Electrum server through the [`Gateway`] trait
//! and therefore only ever sends PUBLIC material (script hashes). No key
//! material is needed for scanning — watch-only by construction.

use std::collections::{BTreeMap, HashMap, HashSet};

use bitcoin::Txid;

use crate::bitcoin::keys::DerivedAddress;
use crate::bitcoin::keys::{AddressSource, BRANCH_EXTERNAL, BRANCH_INTERNAL};
use crate::electrum::{Gateway, HistoryEntry, Utxo};
use crate::{electrum_scripthash_hex, ChainError};

/// Discovery result for one branch: all *scanned* slots plus the highest used
/// index found (needed to persist `addresses` rows and to pick the next fresh
/// receive address after a restart).
#[derive(Debug, Clone)]
pub struct BranchDiscovery {
    /// 0 = external (receiving), 1 = internal (change).
    pub branch: u32,
    /// Slots 0..=last_scanned in index order (gap-limited tail included).
    pub slots: Vec<AddressSlot>,
    /// Highest index with any history (`None` if the branch is unused).
    pub last_used: Option<u32>,
}

impl BranchDiscovery {
    /// The next fresh (never used) receive/change index: `last_used + 1`, or 0
    /// when the branch has no history.
    pub fn next_index(&self) -> u32 {
        self.last_used.map(|i| i + 1).unwrap_or(0)
    }
}

/// One scanned address with its history flag (public data only).
#[derive(Debug, Clone)]
pub struct AddressSlot {
    pub address: String,
    pub script_pubkey: Vec<u8>,
    pub scripthash_hex: String,
    pub branch: u32,
    pub index: u32,
    pub path: String,
    /// `true` when the address has at least one history entry.
    pub used: bool,
}

/// Full scan outcome: both branches + aggregate indexes to persist.
#[derive(Debug, Clone)]
pub struct Discovery {
    pub external: BranchDiscovery,
    pub internal: BranchDiscovery,
    pub gap_limit: u32,
}

impl Discovery {
    /// Iterate over every scanned slot of both branches.
    pub fn slots(&self) -> impl Iterator<Item = &AddressSlot> {
        self.external.slots.iter().chain(self.internal.slots.iter())
    }
}

/// Scan the account: derive addresses under the gap-limit discipline and ask
/// the gateway for the history of each. Stops each branch after `gap_limit`
/// consecutive unused addresses past the last used one (hard-capped to guard
/// against runaway servers/servers with lies).
pub fn discover<A: AddressSource, G: Gateway + ?Sized>(
    gateway: &G,
    account: &A,
    gap_limit: u32,
) -> Result<Discovery, ChainError> {
    if gap_limit == 0 {
        return Err(ChainError::InvalidAmount(
            "gap limit must be at least 1".into(),
        ));
    }
    let external = discover_branch(gateway, account, BRANCH_EXTERNAL, gap_limit)?;
    let internal = discover_branch(gateway, account, BRANCH_INTERNAL, gap_limit)?;
    Ok(Discovery {
        external,
        internal,
        gap_limit,
    })
}

const HARD_SCAN_CAP: u32 = 10_000;

fn discover_branch<A: AddressSource, G: Gateway + ?Sized>(
    gateway: &G,
    account: &A,
    branch: u32,
    gap_limit: u32,
) -> Result<BranchDiscovery, ChainError> {
    let mut slots: Vec<AddressSlot> = Vec::new();
    let mut consecutive_unused: u32 = 0;
    let mut last_used: Option<u32> = None;

    // Batch discipline (решение владельца по скорости + отсутствие банов):
    // запросить историю для gap_limit+1 адресов ОДНИМ round-trip, а гэп
    // применить локально. Диапазон растёт только если вся выборка оказалась
    // использованной (живой хвост аккаунта) — тогда следующий батч.
    let mut index: u32 = 0;
    loop {
        if index >= HARD_SCAN_CAP {
            return Err(ChainError::Internal(format!(
                "branch {branch}: hit the scan cap of {HARD_SCAN_CAP} addresses"
            )));
        }
        let batch_len: usize = gap_limit as usize + 1;
        // Однократная деривация: адреса одного батча выводятся РОВНО один
        // раз (xpub-деривация — реальные secp-операции; повторный вывод на
        // каждый слот удваивал работу синка без всякой пользы).
        let mut derived: Vec<DerivedAddress> = Vec::with_capacity(batch_len);
        let mut scripts: Vec<Vec<u8>> = Vec::with_capacity(batch_len);
        for i in index..(index + batch_len as u32) {
            let d = account.derive_address(branch, i)?;
            scripts.push(d.script_pubkey.as_bytes().to_vec());
            derived.push(d);
        }
        let histories = if batch_len == 1 {
            vec![gateway.script_history(&scripts[0])?]
        } else {
            gateway.script_histories_batch(&scripts)?
        };

        for (offset, history) in histories.into_iter().enumerate() {
            let i = index + offset as u32;
            let slot_source = &derived[offset];
            let used = !history.is_empty();
            if used {
                last_used = Some(i);
                consecutive_unused = 0;
            } else {
                consecutive_unused += 1;
            }
            slots.push(AddressSlot {
                address: slot_source.address.clone(),
                script_pubkey: slot_source.script_pubkey.as_bytes().to_vec(),
                scripthash_hex: slot_source.scripthash_hex.clone(),
                branch,
                index: i,
                path: slot_source.path.clone(),
                used,
            });
            // Дистанция гэпа соблюдена — честная точка остановки.
            if consecutive_unused >= gap_limit {
                return Ok(BranchDiscovery {
                    branch,
                    slots,
                    last_used,
                });
            }
        }
        // Вся выборка использована (живой хвост аккаунта) → следующий батч.
        index += batch_len as u32;
    }
}

/// Aggregated wallet balance in satoshis (never floats).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct WalletBalance {
    pub confirmed_sat: u64,
    /// Sum of per-script unconfirmed deltas (can be negative, e.g. a mempool
    /// spend of confirmed coins).
    pub unconfirmed_delta_sat: i64,
}

/// Balance view across all discovered addresses in ONE batch round-trip
/// (the invariant "balance == Σ utxo values" stays observable).
pub fn wallet_balance<G: Gateway + ?Sized>(
    gateway: &G,
    discovery: &Discovery,
) -> Result<WalletBalance, ChainError> {
    let scripts: Vec<Vec<u8>> = discovery
        .slots()
        .map(|slot| slot.script_pubkey.clone())
        .collect();
    let per = gateway.script_balances_batch(&scripts)?;
    let mut total = WalletBalance::default();
    for s in per {
        total.confirmed_sat = total.confirmed_sat.saturating_add(s.confirmed_sat);
        total.unconfirmed_delta_sat = total
            .unconfirmed_delta_sat
            .saturating_add(s.unconfirmed_sat);
    }
    Ok(total)
}

/// A wallet UTXO together with the owning address slot — this is what the
/// signing layer consumes (the slot pins which key signs it).
#[derive(Debug, Clone)]
pub struct WalletUtxo {
    pub txid: Txid,
    pub vout: u32,
    pub value_sat: u64,
    /// Block height of the funding transaction (`None` = mempool).
    pub height: Option<u32>,
    pub branch: u32,
    pub index: u32,
    pub address: String,
    pub script_pubkey: Vec<u8>,
}

impl WalletUtxo {
    pub fn is_confirmed(&self) -> bool {
        self.height.is_some()
    }
}

/// Collect `WalletUtxo`s across all discovered addresses in deterministic
/// order (branch asc, index asc, txid, vout) — ONE batch round-trip.
pub fn collect_utxos<G: Gateway + ?Sized>(
    gateway: &G,
    discovery: &Discovery,
) -> Result<Vec<WalletUtxo>, ChainError> {
    let slots: Vec<&crate::bitcoin::scan::AddressSlot> = discovery.slots().collect();
    let scripts: Vec<Vec<u8>> = slots
        .iter()
        .map(|slot| slot.script_pubkey.clone())
        .collect();
    let per = gateway.script_utxos_batch(&scripts)?;
    let mut utxos: Vec<WalletUtxo> = Vec::new();
    for (slot, list) in slots.into_iter().zip(per) {
        for u in list {
            let Utxo {
                txid,
                vout,
                value_sat,
                height,
            } = u;
            utxos.push(WalletUtxo {
                txid,
                vout,
                value_sat,
                height,
                branch: slot.branch,
                index: slot.index,
                address: slot.address.clone(),
                script_pubkey: slot.script_pubkey.clone(),
            });
        }
    }
    utxos.sort_by(|a, b| {
        (a.branch, a.index, a.txid, a.vout).cmp(&(b.branch, b.index, b.txid, b.vout))
    });
    Ok(utxos)
}

/// Direction of a wallet transaction.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HistoryDirection {
    /// Money entered the wallet (no wallet inputs).
    Incoming,
    /// Money left the wallet (wallet inputs, net after change is negative).
    Outgoing,
    /// Self-transfer (wallet inputs and wallet outputs; only the fee left).
    Internal,
}

/// One wallet transaction with computed amounts. Satoshis only.
#[derive(Debug, Clone)]
pub struct HistoryItem {
    pub txid: Txid,
    /// Block height (`-1` = mempool).
    pub height: i64,
    pub direction: Option<HistoryDirection>,
    /// Total value of outputs paid to wallet addresses.
    pub received_sat: u64,
    /// Net amount that left the wallet (wallet inputs minus wallet outputs
    /// minus fee); 0 for incoming/internal.
    pub sent_net_sat: u64,
    /// Transaction fee when computable (requires fetching all prevouts).
    pub fee_sat: Option<u64>,
}

/// Raw (txid, height) per script as the gateway reports it.
pub type RawHistory = BTreeMap<(u32, u32), Vec<HistoryEntry>>;

/// Fetch the raw per-address history (used by the UI list before amounts are
/// resolved). Returns `(branch, index) → entries` — ONE batch round-trip.
pub fn raw_history<G: Gateway + ?Sized>(
    gateway: &G,
    discovery: &Discovery,
) -> Result<RawHistory, ChainError> {
    let slots: Vec<&crate::bitcoin::scan::AddressSlot> = discovery.slots().collect();
    let scripts: Vec<Vec<u8>> = slots
        .iter()
        .map(|slot| slot.script_pubkey.clone())
        .collect();
    let per = gateway.script_histories_batch(&scripts)?;
    let mut out: RawHistory = BTreeMap::new();
    for (slot, entries) in slots.into_iter().zip(per) {
        out.insert((slot.branch, slot.index), entries);
    }
    Ok(out)
}

/// Safety valve: history resolution above this many per-address entries is
/// capped to the MOST RECENT ones (mempool first, then descending height).
/// The cap bounds the number of network fetches and UI rows; the honest
/// truncation metadata (see [`HistoryResolution`]) lets the UI say exactly
/// what is shown and what is not.
pub const MAX_HISTORY_ITEMS: usize = 500;

/// Result of history resolution: resolved (amount-bearing) items plus honest
/// truncation metadata. `truncated == true` means the wallet history has more
/// entries than [`MAX_HISTORY_ITEMS`]; `items` then contains only the most
/// recent ones and `total_entries` the full count. Never fabricated, never
/// silently dropped.
#[derive(Debug, Clone)]
pub struct HistoryResolution {
    pub items: Vec<HistoryItem>,
    pub total_entries: usize,
    pub truncated: bool,
}

/// Aggregated, de-duplicated history **with amounts**.
///
/// Method: every (script, txid) occurrence from the per-script histories is
/// merged by txid; for each tx the wallet looks up which outputs belong to it,
/// and which inputs spend wallet outputs (this requires fetching the previous
/// transactions of the inputs — cached per run). Fees are computed from the
/// full input/output sums when all prevouts are fetchable.
///
/// Transactions are fetched IN BATCHES ([`Gateway::txs_by_ids`]); a history
/// larger than [`MAX_HISTORY_ITEMS`] is resolved for the most recent entries
/// only — with explicit truncation metadata in the result (never a hard
/// failure, never a silent drop).
pub fn history_with_amounts<G: Gateway + ?Sized>(
    gateway: &G,
    discovery: &Discovery,
) -> Result<HistoryResolution, ChainError> {
    // 1. Merge per-script occurrences. A tx seen by script S gets S in its
    //    involved-scripts set (a tx can touch many wallet scripts).
    struct Occur {
        height: i64,
        scripts: HashSet<Vec<u8>>,
    }
    let mut occurrences: BTreeMap<Txid, Occur> = BTreeMap::new();
    let mut total_entries: usize = 0;
    {
        let slots: Vec<&crate::bitcoin::scan::AddressSlot> = discovery.slots().collect();
        let scripts: Vec<Vec<u8>> = slots
            .iter()
            .map(|slot| slot.script_pubkey.clone())
            .collect();
        let per = gateway.script_histories_batch(&scripts)?;
        for (slot, entries) in slots.into_iter().zip(per) {
            total_entries += entries.len();
            for HistoryEntry { txid, height } in entries {
                let e = occurrences.entry(txid).or_insert(Occur {
                    height,
                    scripts: HashSet::new(),
                });
                if e.height == 0 || (e.height > 0 && height > 0 && height < e.height) {
                    // keep the best-known height (confirmed wins; lowest wins)
                    e.height = height;
                } else if height > 0 && e.height <= 0 {
                    e.height = height;
                }
                e.scripts.insert(slot.script_pubkey.clone());
            }
        }
    }

    // 2. Most-recent-first selection. Mempool entries (height -1/0) are the
    //    newest; confirmed entries order by descending height.
    let mut order: Vec<(Txid, u64)> = occurrences
        .keys()
        .map(|txid| {
            let height = occurrences[txid].height;
            let recency = if height > 0 { height as u64 } else { u64::MAX };
            (*txid, recency)
        })
        .collect();
    order.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    let truncated = total_entries > MAX_HISTORY_ITEMS;
    let selected: Vec<Txid> = order
        .into_iter()
        .map(|(txid, _)| txid)
        .take(MAX_HISTORY_ITEMS)
        .collect();
    if selected.is_empty() {
        return Ok(HistoryResolution {
            items: Vec::new(),
            total_entries,
            truncated: false,
        });
    }

    // 3. Fetch each selected tx once — batched (chunks on the production
    //    gateway; sequential on the default trait impl).
    let fetched = gateway.txs_by_ids(&selected)?;
    let mut tx_cache: HashMap<Txid, bitcoin::Transaction> = HashMap::with_capacity(selected.len());
    let mut staged: Vec<(HistoryItem, HashSet<Vec<u8>>)> = Vec::with_capacity(selected.len());
    for (txid, tx) in selected.iter().zip(fetched) {
        let tx = tx.ok_or_else(|| ChainError::TxNotFound(txid.to_string()))?;
        tx_cache.insert(*txid, tx);
        let occur = &occurrences[txid];
        let item = HistoryItem {
            txid: *txid,
            height: occur.height,
            direction: None,
            received_sat: 0,
            sent_net_sat: 0,
            fee_sat: None,
        };
        staged.push((item, occur.scripts.clone()));
    }

    // 4. Amount resolution with a shared prevout cache.
    let mut prevout_cache: HashMap<(Txid, u32), (Vec<u8>, u64)> = HashMap::new();
    let mut items: Vec<HistoryItem> = Vec::with_capacity(staged.len());
    for (mut item, scripts) in staged {
        resolve_amounts(
            gateway,
            &mut item,
            &scripts,
            &mut tx_cache,
            &mut prevout_cache,
        )?;
        items.push(item);
    }
    Ok(HistoryResolution {
        items,
        total_entries,
        truncated,
    })
}

/// (script, value) of a prevout — fetched once per (txid,vout) per run.
fn prevout<G: Gateway + ?Sized>(
    gateway: &G,
    outpoint: (Txid, u32),
    tx_cache: &mut HashMap<Txid, bitcoin::Transaction>,
    prevout_cache: &mut HashMap<(Txid, u32), (Vec<u8>, u64)>,
) -> Result<(Vec<u8>, u64), ChainError> {
    if let Some(hit) = prevout_cache.get(&outpoint) {
        return Ok(hit.clone());
    }
    if let std::collections::hash_map::Entry::Vacant(entry) = tx_cache.entry(outpoint.0) {
        let tx = gateway
            .tx_by_id(&outpoint.0)?
            .ok_or_else(|| ChainError::TxNotFound(outpoint.0.to_string()))?;
        entry.insert(tx);
    }
    let tx = tx_cache.get(&outpoint.0).expect("just inserted or present");
    let out = tx.output.get(outpoint.1 as usize).ok_or_else(|| {
        ChainError::Internal(format!(
            "prevout {}:{} out of range",
            outpoint.0, outpoint.1
        ))
    })?;
    let res = (txout_script_bytes(out), txout_value_sat(out));
    prevout_cache.insert(outpoint, res.clone());
    Ok(res)
}

/// Satoshi value of an output (kept in one place: the exact accessor for the
/// version of rust-bitcoin depends on whether `TxOut.value` is `Amount`).
#[inline]
fn txout_value_sat(out: &bitcoin::TxOut) -> u64 {
    out.value.to_sat()
}

#[inline]
fn txout_script_bytes(out: &bitcoin::TxOut) -> Vec<u8> {
    out.script_pubkey.as_bytes().to_vec()
}

fn resolve_amounts<G: Gateway + ?Sized>(
    gateway: &G,
    item: &mut HistoryItem,
    our_scripts: &HashSet<Vec<u8>>,
    tx_cache: &mut HashMap<Txid, bitcoin::Transaction>,
    prevout_cache: &mut HashMap<(Txid, u32), (Vec<u8>, u64)>,
) -> Result<(), ChainError> {
    // Snapshot what we need from the tx, then release the immutable borrow so
    // `prevout` may mutate the cache.
    let (outputs, input_points): (Vec<(Vec<u8>, u64)>, Vec<bitcoin::OutPoint>) = {
        let tx = tx_cache
            .get(&item.txid)
            .ok_or_else(|| ChainError::TxNotFound(item.txid.to_string()))?;
        let outs = tx
            .output
            .iter()
            .map(|o| (txout_script_bytes(o), txout_value_sat(o)))
            .collect();
        let ins = tx.input.iter().map(|i| i.previous_output).collect();
        (outs, ins)
    };
    let is_ours = |script: &[u8]| -> bool { our_scripts.contains(script) };

    let mut all_in_sat: u64 = 0;
    let mut all_out_sat: u64 = 0;
    let mut wallet_in_sat: u64 = 0; // wallet outputs received by this tx
    let mut wallet_inputs_sat: u64 = 0;
    let mut wallet_has_inputs = false;

    for (script, value) in &outputs {
        all_out_sat = all_out_sat.saturating_add(*value);
        if is_ours(script) {
            wallet_in_sat = wallet_in_sat.saturating_add(*value);
        }
    }
    for op in input_points {
        let (prev_script, prev_value) =
            prevout(gateway, (op.txid, op.vout), tx_cache, prevout_cache)?;
        all_in_sat = all_in_sat.saturating_add(prev_value);
        if is_ours(&prev_script) {
            wallet_has_inputs = true;
            wallet_inputs_sat = wallet_inputs_sat.saturating_add(prev_value);
        }
    }

    item.received_sat = wallet_in_sat;
    if all_in_sat >= all_out_sat {
        item.fee_sat = Some(all_in_sat - all_out_sat);
    }

    item.direction = Some(if !wallet_has_inputs {
        HistoryDirection::Incoming
    } else {
        let left_wallet = wallet_inputs_sat
            .saturating_sub(wallet_in_sat)
            .saturating_sub(item.fee_sat.unwrap_or(0));
        item.sent_net_sat = left_wallet;
        if left_wallet == 0 {
            HistoryDirection::Internal
        } else {
            HistoryDirection::Outgoing
        }
    });
    if !wallet_has_inputs {
        item.sent_net_sat = 0;
    }
    Ok(())
}

/// Confirmation status of a wallet transaction, resolved from the histories of
/// the given scripts (the statuses of the addresses involved in it).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TxStatus {
    /// The tx appears in no script history we scanned (e.g. before a sync).
    Unknown,
    /// In the mempool (height -1/0).
    Mempool,
    Confirmed {
        height: u32,
        /// tip − height + 1.
        confirmations: u32,
    },
}

pub fn tx_status<G: Gateway + ?Sized>(
    gateway: &G,
    scripts: &[Vec<u8>],
    txid: Txid,
) -> Result<TxStatus, ChainError> {
    for script in scripts {
        for entry in gateway.script_history(script)? {
            if entry.txid == txid {
                return Ok(match entry.height {
                    h if h > 0 => {
                        let tip = gateway.tip_height()?;
                        let height = h as u32;
                        let confirmations = tip.saturating_sub(height).saturating_add(1);
                        TxStatus::Confirmed {
                            height,
                            confirmations,
                        }
                    }
                    _ => TxStatus::Mempool,
                });
            }
        }
    }
    Ok(TxStatus::Unknown)
}

/// Re-derive the Electrum scripthash of a raw script (bridge convenience).
pub fn scripthash_of(script: &[u8]) -> String {
    electrum_scripthash_hex(bitcoin::Script::from_bytes(script))
}
