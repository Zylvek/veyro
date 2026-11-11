//! Transaction layer: fee estimation, coin selection, transaction building,
//! **local** BIP143 signing (P2WPKH), idempotent broadcast and confirmation
//! status.
//!
//! Security notes:
//! - signing happens here, in Rust, from seed-derived secret keys; secret
//!   material never leaves the process and is zeroized when signing ends;
//! - every money quantity is `u64` satoshis; the only float in this module is
//!   the Electrum protocol's own `estimatefee` unit (BTC/kB) on its way to an
//!   integer sat/vB rate — floats never represent user amounts;
//! - broadcast is idempotent: a first probe (`tx_by_id`) prevents double
//!   submission, and any "already known" rejection maps to `AlreadyKnown`.

use bitcoin_hashes::Hash as _;
use bitcoin::absolute::LockTime;
use bitcoin::consensus::{Decodable, Encodable};
use bitcoin::secp256k1::{Message, SecretKey};
use bitcoin::sighash::SighashCache;
use bitcoin::{Amount, ScriptBuf, Sequence, Transaction, TxIn, TxOut, Witness};

use crate::bitcoin::keys::{derive_secret_key, DerivedAddress, BRANCH_INTERNAL};
use crate::bitcoin::scan::tx_status as scan_tx_status;
use crate::bitcoin::scan::WalletUtxo;
use crate::bitcoin::{P2WPKH_DUST_SAT, SEQUENCE_NO_RBF};
use crate::{BtcNetwork, BroadcastOutcome, Gateway, ChainError};
pub use crate::bitcoin::scan::TxStatus;

/// Fee rates in sat/vbyte (integers; floats never represent fees either).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FeeRates {
    pub fast_sat_vb: u64,
    pub normal_sat_vb: u64,
    pub slow_sat_vb: u64,
}

/// Convert the Electrum protocol unit (BTC per kilobyte) to sat/vbyte, floored
/// at 1. A negative estimate means "unknown at this depth".
pub fn sat_per_vb_from_btc_per_kb(btc_per_kb: f64) -> Result<u64, ChainError> {
    if btc_per_kb < 0.0 {
        return Err(ChainError::FeeEstimateUnavailable(btc_per_kb));
    }
    // This float math is ONLY the protocol-unit conversion; its output is an
    // integer sat/vB, used in every further (integer) computation.
    let sat_per_kb = (btc_per_kb * 100_000_000.0).round() as i64;
    let sat_per_vb = ((sat_per_kb + 999) / 1000).max(1);
    Ok(sat_per_vb as u64)
}

/// Ask the server for three depth presets (1/3/6 blocks ≈ fast/normal/slow).
pub fn estimate_fee_rates<G: Gateway + ?Sized>(gateway: &G) -> Result<FeeRates, ChainError> {
    let depth = |blocks: u32| -> Result<u64, ChainError> {
        sat_per_vb_from_btc_per_kb(gateway.estimate_fee_btc_per_kb(blocks)?)
    };
    Ok(FeeRates {
        fast_sat_vb: depth(1)?,
        normal_sat_vb: depth(3)?,
        slow_sat_vb: depth(6)?,
    })
}

/// vsize estimate for a transaction made of P2WPKH inputs and standard
/// outputs. Weight (BIP141) = legacy bytes × 4 + witness bytes × 1.
pub fn estimate_vsize(input_count: usize, output_script_lens: &[usize]) -> u64 {
    let mut base = 4u64 /* version */ + 4 /* locktime */ + 1 /* in-count varint */ + 1 /* out-count varint */;
    base += input_count as u64 * 41; // outpoint(36) + scriptsig-len(1) + sequence(4)
    for len in output_script_lens {
        let varint = if *len < 253 { 1u64 } else { 3 };
        base += 8 + varint + *len as u64;
    }
    // per P2WPKH input: item-count + sig-len + sig(≤72) + pk-len + pk(33)
    let witness = input_count as u64 * (1 + 1 + 72 + 1 + 33);
    let weight = base * 4 + 2 /* marker+flag */ + witness;
    weight.div_ceil(4)
}

/// Fully planned (not yet signed) transfer — shows the user exactly what the
/// signed transaction will look like.
#[derive(Debug, Clone)]
pub struct PlannedTransfer {
    pub network: BtcNetwork,
    pub recipient: String,
    /// Raw recipient script (validated at plan time).
    pub recipient_script: Vec<u8>,
    pub recipient_amount_sat: u64,
    /// `(address, script_pubkey, amount)` when a change output exists.
    pub change: Option<(String, Vec<u8>, u64)>,
    /// Selected inputs in spend order (largest-first, deterministic).
    pub inputs: Vec<WalletUtxo>,
    pub fee_sat: u64,
    pub vsize: u64,
    pub fee_sat_per_vb: u64,
}

impl PlannedTransfer {
    /// Recipient + change (fee is paid from the inputs' surplus).
    pub fn total_out_sat(&self) -> u64 {
        self.recipient_amount_sat + self.change.as_ref().map(|c| c.2).unwrap_or(0)
    }
}

/// Fee for the shape "n inputs + recipient (+ change)" at `rate` sat/vB.
fn shape_fee(n_inputs: usize, recipient_script_len: usize, has_change: bool, rate: u64) -> u64 {
    let mut lens = vec![recipient_script_len];
    if has_change {
        lens.push(22); // our change addresses are always P2WPKH (BIP84)
    }
    estimate_vsize(n_inputs, &lens) * rate
}

/// Plan a transfer: validate recipient/amount/rate, select coins (largest
/// first), compute fee and change. Never talks to the network and never signs.
pub fn plan_transfer(
    network: BtcNetwork,
    recipient: &str,
    amount_sat: u64,
    fee_sat_per_vb: u64,
    utxos: &[WalletUtxo],
    change_address: &DerivedAddress,
) -> Result<PlannedTransfer, ChainError> {
    if amount_sat == 0 {
        return Err(ChainError::InvalidAmount("amount must be positive".into()));
    }
    if fee_sat_per_vb == 0 {
        return Err(ChainError::FeeTooLow);
    }
    if amount_sat < P2WPKH_DUST_SAT {
        return Err(ChainError::Dust {
            amount_sat,
            dust_sat: P2WPKH_DUST_SAT,
        });
    }

    // Recipient must be a valid address of a matching network (any standard
    // type: p2wpkh/p2sh/legacy/taproot — `Address::from_str` validates).
    let unchecked: bitcoin::Address<bitcoin::address::NetworkUnchecked> = recipient
        .parse()
        .map_err(|e| ChainError::InvalidAddress(format!("{recipient}: {e}")))?;
    let checked = unchecked
        .require_network(network.bitcoin_network())
        .map_err(|_| ChainError::AddressNetworkMismatch(network.display_name()))?;
    let recipient_script = checked.script_pubkey();
    let recipient_script_len = recipient_script.as_bytes().len();

    if utxos.is_empty() {
        return Err(ChainError::NoSpendableOutputs);
    }

    // Largest-first selection (deterministic tie-break by txid/vout).
    let mut candidates: Vec<&WalletUtxo> = utxos.iter().collect();
    candidates.sort_by(|a, b| {
        b.value_sat
            .cmp(&a.value_sat)
            .then_with(|| b.txid.cmp(&a.txid))
            .then_with(|| b.vout.cmp(&a.vout))
    });

    // Selection: fee grows with the number of inputs, so re-fee after each
    // extra input. The 2-output (with change) and 1-output (change merged
    // into the miner fee) shapes are both probed each round; termination is
    // guaranteed since every round without a break selects one more coin or
    // reports InsufficientFunds.
    let mut picked: Vec<&WalletUtxo> = Vec::new();
    let mut gathered: u64 = 0;
    let (fee, change_opt): (u64, Option<u64>) = loop {
        let f_with_change = shape_fee(picked.len(), recipient_script_len, true, fee_sat_per_vb);
        if gathered >= amount_sat.saturating_add(f_with_change) {
            let leftover = gathered - amount_sat - f_with_change;
            if leftover >= P2WPKH_DUST_SAT {
                break (f_with_change, Some(leftover));
            }
        }
        // No change output is viable (or change would be dust): the leftover
        // goes to the miner, the recipient keeps its exact amount. This is
        // the same equilibrium the reference Electrum client reaches.
        let f_no_change = shape_fee(picked.len(), recipient_script_len, false, fee_sat_per_vb);
        if gathered >= amount_sat.saturating_add(f_no_change) {
            break (f_no_change, None);
        }
        let next = candidates
            .get(picked.len())
            .ok_or_else(|| ChainError::InsufficientFunds {
                required_sat: amount_sat.saturating_add(f_with_change),
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

    Ok(PlannedTransfer {
        network,
        recipient: checked.to_string(),
        recipient_script: recipient_script.as_bytes().to_vec(),
        recipient_amount_sat: amount_sat,
        change,
        inputs: picked.into_iter().cloned().collect(),
        fee_sat: fee,
        vsize: fee
            .checked_div(fee_sat_per_vb)
            .expect("rate ≥ 1 checked above"),
        fee_sat_per_vb,
    })
}

/// Context for local signing: the BIP39 seed stays with the caller (session),
/// each derived secret key is zeroized as soon as its input is signed.
pub struct SignedTransferBuilder<'a> {
    pub seed: &'a [u8; 64],
    pub network: BtcNetwork,
    pub account: u32,
}

impl<'a> SignedTransferBuilder<'a> {
    /// Build the transaction from the plan and sign every input locally.
    pub fn sign(&self, plan: &PlannedTransfer, tip_height: u32) -> Result<SignedTransfer, ChainError> {
        let mut inputs: Vec<TxIn> = Vec::with_capacity(plan.inputs.len());
        for u in &plan.inputs {
            inputs.push(TxIn {
                previous_output: bitcoin::OutPoint {
                    txid: u.txid,
                    vout: u.vout,
                },
                script_sig: ScriptBuf::new(),
                // Not REPLACE-BY-FEE — see SEQUENCE_NO_RBF docs.
                sequence: Sequence::from_consensus(SEQUENCE_NO_RBF),
                witness: Witness::default(),
            });
        }

        let mut outputs: Vec<TxOut> = vec![TxOut {
            value: Amount::from_sat(plan.recipient_amount_sat),
            script_pubkey: ScriptBuf::from_bytes(plan.recipient_script.clone()),
        }];
        if let Some((_, script, amount)) = plan.change.as_ref() {
            outputs.push(TxOut {
                value: Amount::from_sat(*amount),
                script_pubkey: ScriptBuf::from_bytes(script.clone()),
            });
        }

        let lock_time = LockTime::from_height(tip_height).unwrap_or(LockTime::ZERO);
        let mut tx = Transaction {
            version: bitcoin::transaction::Version(2),
            lock_time,
            input: inputs,
            output: outputs,
        };

        for (i, u) in plan.inputs.iter().enumerate() {
            // Zeroizes on drop — the key bytes do not outlive this iteration.
            let sk = derive_secret_key(
                self.seed,
                self.network,
                self.account,
                u.branch,
                u.index,
            )?;
            sign_p2wpkh_input(&mut tx, i, u.value_sat, &sk)?;
        }

        let txid = tx.compute_txid();
        let mut raw: Vec<u8> = Vec::new();
        tx.consensus_encode(&mut raw)
            .map_err(|e| ChainError::Internal(format!("encode signed tx: {e}")))?;

        Ok(SignedTransfer {
            txid,
            raw_hex: hex::encode(&raw),
            plan: plan.clone(),
            // Change always lands on the internal branch (BIP84 discipline).
            change_address_branch: plan.change.as_ref().map(|_| BRANCH_INTERNAL),
        })
    }
}

/// BIP143 signature hash of a P2WPKH input (SIGHASH_ALL), from the *compressed
/// pubkey bytes* — the single source of truth for digests, shared by local
/// signing and the official-vector tests.
///
/// Note: rust-bitcoin's `p2wpkh_signature_hash` takes the **witness-program
/// script** (`0014{keyhash}`) and derives the BIP143 `scriptCode`
/// (`76a914{keyhash}88ac`) internally via `Script::p2wpkh_script_code()`.
pub fn bip143_sighash_p2wpkh(
    tx: &mut Transaction,
    input_index: usize,
    input_value_sat: u64,
    pubkey_compressed: &[u8],
) -> Result<[u8; 32], ChainError> {
    let compressed = bitcoin::key::CompressedPublicKey::from_slice(pubkey_compressed)
        .map_err(|e| ChainError::Crypto(format!("pubkey: {e}")))?;
    let wp = bitcoin::WitnessProgram::p2wpkh(&compressed);
    let script_pubkey = bitcoin::ScriptBuf::new_witness_program(&wp);
    let mut cache = SighashCache::new(tx);
    let sighash = cache
        .p2wpkh_signature_hash(
            input_index,
            &script_pubkey,
            Amount::from_sat(input_value_sat),
            bitcoin::sighash::EcdsaSighashType::All,
        )
        .map_err(|e| ChainError::Crypto(format!("sighash: {e}")))?;
    Ok(*sighash.as_byte_array())
}

/// BIP143 signing of one P2WPKH input with SIGHASH_ALL:
/// digest per BIP143 → RFC6979 ECDSA → DER + `\x01` appended; witness is
/// `[signature, compressed pubkey]`.
pub fn sign_p2wpkh_input(
    tx: &mut Transaction,
    input_index: usize,
    input_value_sat: u64,
    secret_key_bytes: &[u8; 32],
) -> Result<(), ChainError> {
    let sk = SecretKey::from_slice(secret_key_bytes)
        .map_err(|e| ChainError::Crypto(format!("bad secret key: {e}")))?;
    let secp = bitcoin::secp256k1::Secp256k1::signing_only();
    let pk = bitcoin::secp256k1::PublicKey::from_secret_key(&secp, &sk);
    let pk_bytes = pk.serialize().to_vec();

    let sighash = bip143_sighash_p2wpkh(tx, input_index, input_value_sat, &pk_bytes)?;
    let msg = Message::from_digest(sighash);
    let sig = secp.sign_ecdsa(&msg, &sk);

    // Proper DER (with the leading-zero padding the BIP143 vector expects) +
    // the SIGHASH_ALL byte — byte-identical to what bitcoin core broadcasts.
    let mut der = sig.serialize_der().to_vec();
    der.push(0x01); // SIGHASH_ALL

    tx.input[input_index].witness = Witness::from_slice(&[der, pk_bytes]);
    Ok(())
}

/// Ready-to-broadcast transfer together with its display plan.
#[derive(Debug, Clone)]
pub struct SignedTransfer {
    pub txid: bitcoin::Txid,
    /// Signed consensus hex (only for the user's confirm dialog / display).
    pub raw_hex: String,
    pub plan: PlannedTransfer,
    /// Change always lands on the internal branch (BIP84).
    pub change_address_branch: Option<u32>,
}

/// Broadcast with the double-send guard: first ask the server whether this tx
/// is already known (mempool/chain) — if so, no second submission happens.
/// Server text errors like "txn-already-known" also map to `AlreadyKnown`.
pub fn idempotent_broadcast<G: Gateway + ?Sized>(
    gateway: &G,
    signed: &SignedTransfer,
) -> Result<BroadcastOutcome, ChainError> {
    if gateway.tx_by_id(&signed.txid)?.is_some() {
        return Ok(BroadcastOutcome::AlreadyKnown(signed.txid));
    }
    let raw = hex::decode(&signed.raw_hex)
        .map_err(|e| ChainError::Internal(format!("decode own tx: {e}")))?;
    let tx: Transaction = Decodable::consensus_decode(&mut raw.as_slice())
        .map_err(|e| ChainError::Internal(format!("re-decode own tx: {e}")))?;
    match gateway.broadcast(&tx) {
        Ok(txid) => Ok(BroadcastOutcome::Sent(txid)),
        Err(ChainError::BroadcastRejected(text)) => {
            let low = text.to_ascii_lowercase();
            if low.contains("already") {
                Ok(BroadcastOutcome::AlreadyKnown(signed.txid))
            } else {
                Err(ChainError::BroadcastRejected(text))
            }
        }
        Err(e) => Err(e),
    }
}

/// Confirmation status wrapper (history-based lookup over involved scripts).
pub fn confirmation_status<G: Gateway + ?Sized>(
    gateway: &G,
    scripts: &[Vec<u8>],
    txid: bitcoin::Txid,
) -> Result<TxStatus, ChainError> {
    scan_tx_status(gateway, scripts, txid)
}
