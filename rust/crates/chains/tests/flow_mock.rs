//! Full adapter cycle against a FAKE gateway (no network): discovery →
//! balance → UTXO → fee estimate → plan → local sign → idempotent broadcast →
//! "mining" → history with amounts → confirmation status. Additionally every
//! planned error path: insufficient funds, dust, fee-too-low, cross-network
//! recipient, no-change dust merge, largest-first selection.

use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap};

use bitcoin::consensus::Decodable;
use bitcoin::{Amount, ScriptBuf, Transaction, TxOut};
use bitcoin::absolute::LockTime;
use chains::bitcoin::keys::AccountPubkeys;
use chains::bitcoin::scan::{
    collect_utxos, discover, history_with_amounts, tx_status, HistoryDirection, TxStatus,
};
use chains::bitcoin::tx::{
    estimate_fee_rates, idempotent_broadcast, plan_transfer, sat_per_vb_from_btc_per_kb,
    estimate_vsize, SignedTransferBuilder,
};
use chains::electrum::{BtcNetwork, Gateway, HistoryEntry, ScriptBalance, Utxo};
use chains::ChainError;
use hex::FromHex as _;

use bip39::Mnemonic;

const MNEMONIC: &str = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

fn vector_seed() -> [u8; 64] {
    Mnemonic::parse_normalized(MNEMONIC)
        .expect("vector mnemonic")
        .to_seed_normalized("")
}

// ---------------------------------------------------------------- fake ---

#[derive(Debug)]
struct FakeGateway {
    network: BtcNetwork,
    tip: u32,
    fee_btc_per_kb: f64,
    server_version: String,
    /// script_pubkey bytes → unspent outputs.
    utxos: HashMap<Vec<u8>, Vec<Utxo>>,
    /// script_pubkey bytes → history.
    history: HashMap<Vec<u8>, Vec<HistoryEntry>>,
    /// known transactions (funding data + everything ever broadcast here).
    txs: RefCell<BTreeMap<bitcoin::Txid, Transaction>>,
    /// ids submitted through `broadcast`.
    broadcasts: RefCell<Vec<bitcoin::Txid>>,
}

impl FakeGateway {
    fn new(network: BtcNetwork, tip: u32, fee_btc_per_kb: f64) -> Self {
        Self {
            network,
            tip,
            fee_btc_per_kb,
            server_version: "FakeElectrum 1.0 (VEYRO test)".into(),
            utxos: HashMap::new(),
            history: HashMap::new(),
            txs: RefCell::new(BTreeMap::new()),
            broadcasts: RefCell::new(Vec::new()),
        }
    }

    /// A synthetic funding transaction paying `value_sat` to `script`.
    /// Zero inputs are fine at the fake level — the history amounts resolver
    /// treats them as fee-null, fully-received coinbase-like funding.
    fn fund(&mut self, value_sat: u64, script: &ScriptBuf, height: u32) -> bitcoin::Txid {
        let tx = Transaction {
            version: bitcoin::transaction::Version(2),
            lock_time: LockTime::ZERO,
            input: vec![],
            output: vec![TxOut {
                value: Amount::from_sat(value_sat),
                script_pubkey: script.clone(),
            }],
        };
        let txid = tx.compute_txid();
        self.txs.borrow_mut().insert(txid, tx);
        self.utxos
            .entry(script.as_bytes().to_vec())
            .or_default()
            .push(Utxo {
                txid,
                vout: 0,
                value_sat,
                height: Some(height),
            });
        self.history
            .entry(script.as_bytes().to_vec())
            .or_default()
            .push(HistoryEntry {
                txid,
                height: height as i64,
            });
        txid
    }

    /// Confirm a spend: consume the input, credit the change output and add
    /// history entries at `height` (use -1 while in the mempool). Idempotent:
    /// re-applying the same tx only updates the height.
    fn apply_spend(&mut self, spend: &Transaction, funding_script: &[u8], change_script: &[u8], spend_height: i64) {
        let txid = spend.compute_txid();
        // consume the funding output
        if let Some(list) = self.utxos.get_mut(funding_script) {
            list.clear();
        }
        // credit each output that pays the change script, at vout index
        for (vout, out) in spend.output.iter().enumerate() {
            let key = out.script_pubkey.as_bytes().to_vec();
            if key == change_script && key != funding_script {
                let list = self.utxos.entry(key.clone()).or_default();
                match list
                    .iter_mut()
                    .find(|u| u.txid == txid && u.vout == vout as u32)
                {
                    // re-mining: bump the height (mempool → block)
                    Some(existing) => {
                        if spend_height > 0 && existing.height.is_none() {
                            existing.height = Some(spend_height as u32);
                        }
                    }
                    None => list.push(Utxo {
                        txid,
                        vout: vout as u32,
                        value_sat: out.value.to_sat(),
                        height: (spend_height > 0).then_some(spend_height as u32),
                    }),
                }
            }
        }
        // history: upsert (a real Electrum server keeps one entry per tx)
        let involved = vec![
            funding_script.to_vec(),
            change_script.to_vec(),
            spend.output[0].script_pubkey.as_bytes().to_vec(),
        ];
        for script in involved {
            let list = self.history.entry(script).or_default();
            match list.iter_mut().find(|e| e.txid == txid) {
                Some(entry) => entry.height = spend_height,
                None => list.push(HistoryEntry {
                    txid,
                    height: spend_height,
                }),
            }
        }
        self.txs.borrow_mut().insert(txid, spend.clone());
    }
}

impl Gateway for FakeGateway {
    fn network(&self) -> BtcNetwork {
        self.network
    }
    fn server_features(&self) -> Result<(String, String, String, [u8; 32]), ChainError> {
        Ok((
            self.server_version.clone(),
            "1.4".into(),
            "1.4".into(),
            self.network.genesis_hash(),
        ))
    }
    fn tip_height(&self) -> Result<u32, ChainError> {
        Ok(self.tip)
    }
    fn estimate_fee_btc_per_kb(&self, _blocks: u32) -> Result<f64, ChainError> {
        Ok(self.fee_btc_per_kb)
    }
    fn script_balance(&self, script: &[u8]) -> Result<ScriptBalance, ChainError> {
        let mut bal = ScriptBalance {
            confirmed_sat: 0,
            unconfirmed_sat: 0,
        };
        if let Some(list) = self.utxos.get(script) {
            for u in list {
                match u.height {
                    Some(_) => bal.confirmed_sat += u.value_sat,
                    None => bal.unconfirmed_sat += u.value_sat as i64,
                }
            }
        }
        Ok(bal)
    }
    fn script_utxos(&self, script: &[u8]) -> Result<Vec<Utxo>, ChainError> {
        Ok(self.utxos.get(script).cloned().unwrap_or_default())
    }
    fn script_history(&self, script: &[u8]) -> Result<Vec<HistoryEntry>, ChainError> {
        Ok(self.history.get(script).cloned().unwrap_or_default())
    }
    fn tx_by_id(&self, txid: &bitcoin::Txid) -> Result<Option<Transaction>, ChainError> {
        Ok(self.txs.borrow().get(txid).cloned())
    }
    fn broadcast(&self, tx: &Transaction) -> Result<bitcoin::Txid, ChainError> {
        let txid = tx.compute_txid();
        self.txs.borrow_mut().insert(txid, tx.clone());
        self.broadcasts.borrow_mut().push(txid);
        Ok(txid)
    }
}

// ------------------------------------------------------------- the flow ---

#[test]
fn full_cycle_on_fake_testnet_gateway() {
    let seed = vector_seed();
    let account = AccountPubkeys::from_seed(&seed, BtcNetwork::Testnet, 0).expect("account");
    let recv0 = account.derive_address(0, 0).expect("addr(0,0)");
    let recv9 = account.derive_address(0, 9).expect("addr(0,9)");
    let change0 = account.derive_address(1, 0).expect("addr(1,0)");

    let mut gw = FakeGateway::new(BtcNetwork::Testnet, 800_000, 0.0001 /* BTC/kB */);
    gw.fund(100_000, &recv0.script_pubkey, 800_000);

    // 0) network safety check right after "connect"
    gw.verify_network().expect("fake serves testnet3 genesis");

    // 1) discovery: gap 5
    let discovery = discover(&gw, &account, 5).expect("discovery");
    assert_eq!(discovery.external.last_used, Some(0));
    assert_eq!(discovery.external.slots.len(), 6, "used slot 0 + 5 fresh");
    assert_eq!(discovery.external.next_index(), 1);
    assert_eq!(discovery.internal.last_used, None);
    assert_eq!(discovery.internal.slots.len(), 5);
    assert_eq!(discovery.internal.next_index(), 0);
    assert!(discovery.external.slots[0].used);
    assert!(!discovery.external.slots[1].used);
    assert!(discovery.slots().all(|s| s.scripthash_hex.len() == 64));

    // 2) balance & UTXO
    let balance = chains::bitcoin::scan::wallet_balance(&gw, &discovery).expect("balance");
    assert_eq!(balance.confirmed_sat, 100_000);
    assert_eq!(balance.unconfirmed_delta_sat, 0);
    let utxos = collect_utxos(&gw, &discovery).expect("utxos");
    assert_eq!(utxos.len(), 1);
    assert_eq!(utxos[0].value_sat, 100_000);
    assert_eq!(utxos[0].branch, 0);
    assert_eq!(utxos[0].index, 0);
    assert!(utxos[0].is_confirmed());

    // 3) fee estimate: 0.0001 BTC/kB → 10 sat/vB
    let rates = estimate_fee_rates(&gw).expect("rates");
    assert_eq!(rates.fast_sat_vb, 10);
    assert_eq!(rates.normal_sat_vb, 10);
    assert_eq!(rates.slow_sat_vb, 10);

    // 4) plan: send 60 000 sat
    let plan = plan_transfer(
        BtcNetwork::Testnet,
        &recv9.address,
        60_000,
        rates.normal_sat_vb,
        &utxos,
        &change0,
    )
    .expect("plan");
    assert_eq!(plan.recipient, recv9.address);
    assert_eq!(plan.recipient_amount_sat, 60_000);
    assert_eq!(plan.vsize, 141, "1 P2WPKH in + 2 outs: 113*4+2+108=562 → 141");
    assert_eq!(plan.fee_sat, 1410);
    let change = plan.change.as_ref().expect("change output exists");
    assert_eq!(change.2, 100_000 - 60_000 - 1410);
    assert_eq!(change.0, change0.address);

    // 5) sign locally
    let builder = SignedTransferBuilder {
        seed: &seed,
        network: BtcNetwork::Testnet,
        account: 0,
    };
    let signed = builder.sign(&plan, gw.tip).expect("sign");
    let spend: Transaction = {
        let raw = Vec::from_hex(&signed.raw_hex).unwrap();
        Decodable::consensus_decode(&mut raw.as_slice()).expect("decode own signed tx")
    };
    // structure: 1 input (our UTXO), recipient + change outputs, non-RBF seq
    assert_eq!(spend.input.len(), 1);
    assert_eq!(spend.input[0].previous_output.txid, utxos[0].txid);
    assert_eq!(spend.input[0].previous_output.vout, 0);
    assert_eq!(spend.input[0].sequence.to_consensus_u32(), 0xFFFF_FFFE);
    assert_eq!(spend.output.len(), 2);
    assert_eq!(spend.output[0].value.to_sat(), 60_000);
    assert_eq!(&spend.output[0].script_pubkey, &recv9.script_pubkey);
    assert_eq!(spend.output[1].value.to_sat(), 38_590);
    assert_eq!(&spend.output[1].script_pubkey, &change0.script_pubkey);
    // the witness was actually produced (68–72-byte DER + 33-byte pubkey)
    let wit = spend.input[0].witness.to_vec();
    assert_eq!(wit.len(), 2);
    assert_eq!(wit[1], recv0_pubkey_of(&seed), "witness pubkey = key of (0,0)");
    assert!(wit[0].len() >= 68 && wit[0].len() <= 72, "DER sig + \\x01");
    assert_eq!(*wit[0].last().unwrap(), 0x01, "SIGHASH_ALL");

    // 6) idempotent broadcast
    let outcome = idempotent_broadcast(&gw, &signed).expect("broadcast");
    let txid = signed.txid;
    match outcome {
        chains::electrum::BroadcastOutcome::Sent(t) => assert_eq!(t, txid),
        other => panic!("expected Sent, got {other:?}"),
    }
    assert_eq!(gw.broadcasts.borrow().len(), 1);
    // replay: the network already knows this tx — nothing is re-submitted
    let replay = idempotent_broadcast(&gw, &signed).expect("replay");
    assert_eq!(replay, chains::electrum::BroadcastOutcome::AlreadyKnown(txid));
    assert_eq!(gw.broadcasts.borrow().len(), 1, "NO second submission");

    // 7) pre-inserted "already in mempool" race: a fresh server copy knows it
    let gw2 = FakeGateway::new(BtcNetwork::Testnet, 800_000, 0.0001);
    gw2.txs.borrow_mut().insert(txid, spend.clone());
    let race = idempotent_broadcast(&gw2, &signed).expect("race-guard");
    assert_eq!(race, chains::electrum::BroadcastOutcome::AlreadyKnown(txid));
    assert!(gw2.broadcasts.borrow().is_empty());

    // 8) "mine": confirm the spend on the fake network
    let spk_recv0 = recv0.script_pubkey.as_bytes().to_vec();
    let spk_change = change0.script_pubkey.as_bytes().to_vec();
    gw.apply_spend(&spend, &spk_recv0, &spk_change, -1); // mempool first
    let status_mempool =
        tx_status(&gw, &[spk_recv0.clone(), spk_change.clone()], txid).expect("status");
    assert_eq!(status_mempool, TxStatus::Mempool);

    // re-mine at height 800001 and re-check history + status
    gw.apply_spend(&spend, &spk_recv0, &spk_change, 800_001);
    let items = history_with_amounts(&gw, &discovery).expect("history");
    let funding = items
        .iter()
        .find(|i| i.txid == utxos[0].txid)
        .expect("funding tx in history");
    assert_eq!(funding.direction, Some(HistoryDirection::Incoming));
    assert_eq!(funding.received_sat, 100_000);
    assert_eq!(funding.fee_sat, None, "coinbase-like funding has no fee");
    let spend_item = items.iter().find(|i| i.txid == txid).expect("spend in history");
    assert_eq!(spend_item.direction, Some(HistoryDirection::Outgoing));
    assert_eq!(spend_item.sent_net_sat, 60_000);
    assert_eq!(spend_item.fee_sat, Some(1410));
    assert_eq!(spend_item.received_sat, 38_590, "change lands in the wallet");

    let status = tx_status(&gw, &[spk_recv0, spk_change], txid).expect("status");
    assert_eq!(
        status,
        TxStatus::Confirmed {
            height: 800_001,
            confirmations: 1
        }
    );

    // balance after the spend: only the change output remains
    let balance = chains::bitcoin::scan::wallet_balance(&gw, &discovery).expect("balance");
    assert_eq!(balance.confirmed_sat, 38_590);
}

fn recv0_pubkey_of(seed: &[u8; 64]) -> Vec<u8> {
    // the (0,0) compressed pubkey that must have signed the spend
    let sk = chains::bitcoin::keys::derive_secret_key(seed, BtcNetwork::Testnet, 0, 0, 0)
        .expect("secret");
    let secret = bitcoin::secp256k1::SecretKey::from_slice(sk.as_ref()).unwrap();
    let pk = bitcoin::secp256k1::PublicKey::from_secret_key(
        &bitcoin::secp256k1::Secp256k1::signing_only(),
        &secret,
    );
    pk.serialize().to_vec()
}

// --------------------------------------------------------- error paths ---

#[test]
fn insufficient_funds_is_reported_with_numbers() {
    let seed = vector_seed();
    let account = AccountPubkeys::from_seed(&seed, BtcNetwork::Testnet, 0).unwrap();
    let recv0 = account.derive_address(0, 0).unwrap();
    let recv9 = account.derive_address(0, 9).unwrap();
    let change0 = account.derive_address(1, 0).unwrap();
    let mut gw = FakeGateway::new(BtcNetwork::Testnet, 800_000, 0.0001);
    gw.fund(100_000, &recv0.script_pubkey, 800_000);
    let discovery = discover(&gw, &account, 5).unwrap();
    let utxos = collect_utxos(&gw, &discovery).unwrap();

    let err = plan_transfer(
        BtcNetwork::Testnet,
        &recv9.address,
        99_000,
        10,
        &utxos,
        &change0,
    )
    .unwrap_err();
    match err {
        ChainError::InsufficientFunds {
            required_sat,
            available_sat,
        } => {
            assert_eq!(available_sat, 100_000);
            assert_eq!(required_sat, 99_000 + 1410);
        }
        other => panic!("wrong error: {other:?}"),
    }
}

#[test]
fn zero_fee_rate_and_dust_amount_rejected() {
    let seed = vector_seed();
    let account = AccountPubkeys::from_seed(&seed, BtcNetwork::Testnet, 0).unwrap();
    let recv0 = account.derive_address(0, 0).unwrap();
    let recv9 = account.derive_address(0, 9).unwrap();
    let change0 = account.derive_address(1, 0).unwrap();
    let mut gw = FakeGateway::new(BtcNetwork::Testnet, 800_000, 0.0001);
    gw.fund(100_000, &recv0.script_pubkey, 800_000);
    let discovery = discover(&gw, &account, 2).unwrap();
    let utxos = collect_utxos(&gw, &discovery).unwrap();

    let err = plan_transfer(
        BtcNetwork::Testnet,
        &recv9.address,
        60_000,
        0,
        &utxos,
        &change0,
    )
    .unwrap_err();
    assert!(matches!(err, ChainError::FeeTooLow), "got {err}");

    let err = plan_transfer(
        BtcNetwork::Testnet,
        &recv9.address,
        100, // < dust 294
        10,
        &utxos,
        &change0,
    )
    .unwrap_err();
    assert!(
        matches!(err, ChainError::Dust { amount_sat: 100, .. }),
        "got {err}"
    );
}

#[test]
fn foreign_network_recipient_rejected() {
    let seed = vector_seed();
    let account = AccountPubkeys::from_seed(&seed, BtcNetwork::Testnet, 0).unwrap();
    let recv0 = account.derive_address(0, 0).unwrap();
    let change0 = account.derive_address(1, 0).unwrap();
    let mut gw = FakeGateway::new(BtcNetwork::Testnet, 800_000, 0.0001);
    gw.fund(100_000, &recv0.script_pubkey, 800_000);
    let discovery = discover(&gw, &account, 2).unwrap();
    let utxos = collect_utxos(&gw, &discovery).unwrap();

    // OFFICIAL BIP84 MAINNET vector address — valid, but wrong network here.
    let err = plan_transfer(
        BtcNetwork::Testnet,
        "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu",
        60_000,
        10,
        &utxos,
        &change0,
    )
    .unwrap_err();
    assert!(
        matches!(err, ChainError::AddressNetworkMismatch("Bitcoin testnet3")),
        "got {err}"
    );
    // …and the same address on mainnet plans fine (shape sanity).
    let mut gw_main = FakeGateway::new(BtcNetwork::Mainnet, 900_000, 0.0001);
    let acct_main = AccountPubkeys::from_seed(&seed, BtcNetwork::Mainnet, 0).unwrap();
    let r0 = acct_main.derive_address(0, 0).unwrap();
    let c0 = acct_main.derive_address(1, 0).unwrap();
    gw_main.fund(100_000, &r0.script_pubkey, 900_000);
    let d = discover(&gw_main, &acct_main, 2).unwrap();
    let utxos_main = collect_utxos(&gw_main, &d).unwrap();
    assert!(plan_transfer(
        BtcNetwork::Mainnet,
        "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu",
        60_000,
        10,
        &utxos_main,
        &c0,
    )
    .is_ok());
}

#[test]
fn no_change_output_when_leftover_is_dust() {
    let seed = vector_seed();
    let account = AccountPubkeys::from_seed(&seed, BtcNetwork::Testnet, 0).unwrap();
    let recv0 = account.derive_address(0, 0).unwrap();
    let recv9 = account.derive_address(0, 9).unwrap();
    let change0 = account.derive_address(1, 0).unwrap();
    let mut gw = FakeGateway::new(BtcNetwork::Testnet, 800_000, 0.0001);
    gw.fund(61_374, &recv0.script_pubkey, 800_000);
    let discovery = discover(&gw, &account, 2).unwrap();
    let utxos = collect_utxos(&gw, &discovery).unwrap();

    // fee with change would be 1410 → leftover −36; fee alone-on shape is 1100
    // → leftover 274 (< 294 dust) → the dust goes to the miner, change dropped.
    let plan = plan_transfer(
        BtcNetwork::Testnet,
        &recv9.address,
        60_000,
        10,
        &utxos,
        &change0,
    )
    .expect("plan");
    assert!(plan.change.is_none());
    assert_eq!(plan.fee_sat, 1100);
    assert_eq!(plan.recipient_amount_sat, 60_000, "recipient is never underpaid");
    assert_eq!(plan.vsize, 110);
}

#[test]
fn largest_first_selection_across_two_utxos() {
    let seed = vector_seed();
    let account = AccountPubkeys::from_seed(&seed, BtcNetwork::Testnet, 0).unwrap();
    let recv0 = account.derive_address(0, 0).unwrap();
    let recv1 = account.derive_address(0, 1).unwrap();
    let recv9 = account.derive_address(0, 9).unwrap();
    let change0 = account.derive_address(1, 0).unwrap();
    let mut gw = FakeGateway::new(BtcNetwork::Testnet, 800_000, 0.0001);
    gw.fund(30_000, &recv0.script_pubkey, 800_000);
    gw.fund(40_000, &recv1.script_pubkey, 800_000);
    let discovery = discover(&gw, &account, 2).unwrap();
    let utxos = collect_utxos(&gw, &discovery).unwrap();
    assert_eq!(utxos.len(), 2);

    let plan = plan_transfer(
        BtcNetwork::Testnet,
        &recv9.address,
        60_000,
        10,
        &utxos,
        &change0,
    )
    .expect("plan");
    // 40k picked first, then 30k; leftover after fee keeps change.
    assert_eq!(plan.inputs.len(), 2);
    assert_eq!(plan.inputs[0].value_sat, 40_000);
    assert_eq!(plan.inputs[1].value_sat, 30_000);
    // vsize for 2 in + 2 out: (10+82+62)*4 + 2 + 216 = 834 → 209
    assert_eq!(plan.vsize, 209);
    assert_eq!(plan.fee_sat, 2090);
    assert_eq!(
        plan.change.as_ref().unwrap().2,
        70_000 - 60_000 - 2090
    );
}

// ------------------------------------------------------------ units ---

#[test]
fn fee_unit_conversion_and_vsize_math() {
    assert_eq!(sat_per_vb_from_btc_per_kb(0.0001).unwrap(), 10);
    assert_eq!(sat_per_vb_from_btc_per_kb(0.0).unwrap(), 1);
    assert_eq!(sat_per_vb_from_btc_per_kb(0.0000123).unwrap(), 2, "rounds up");
    assert!(matches!(
        sat_per_vb_from_btc_per_kb(-1.0).unwrap_err(),
        ChainError::FeeEstimateUnavailable(-1.0)
    ));

    // 1 P2WPKH in + 1 out: (8+41+31)*4 + 2 + 108 = 438 → 110 vB
    assert_eq!(estimate_vsize(1, &[22]), 110);
    // 1 in + 2 outs: (8+41+62)*4 + 2 + 108 = 562 → 141 vB
    assert_eq!(estimate_vsize(1, &[22, 22]), 141);
    // 2 in + 2 outs: (8+82+62)*4 + 2 + 216 = 834 → 209 vB
    assert_eq!(estimate_vsize(2, &[22, 22]), 209);
    // long scripts need a 3-byte varint:
    // base = 8 + (8+3+253) = 274 → weight 274*4+2 = 1098 → vsize 275
    assert_eq!(estimate_vsize(0, &[253]), 275);
}
