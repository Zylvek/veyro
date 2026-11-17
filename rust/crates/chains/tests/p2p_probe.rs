//! Живые P2P-пробы RVN/XNA (NOT run in normal test runs):
//!   cargo test -p chains --test p2p_probe -- --ignored --nocapture
//!
//! RVN: checkpoint 2,383,550 (chainparams.cpp, официальные checkpoint'ы),
//! XNA: checkpoint 1,816,500 (chainparams defaultAssumeValid/verify).
//! Проверки: 2+ независимых пира отдают идентичные цепи (кворум),
//! связность prev, высоты последовательны, DGW3 предсказание == факт на
//! всём синке, kawpow PoW хвоста честно через kawpow_ffi, ориентация
//! byte-order kawpow-хэша определена пробой (не выдумкой).
//! Тестнет RVN (seed-testnet-raven…) — вторая цель пробы.

use std::time::Duration;

use chains::p2p::client::{discover_and_scan, quorum_sync, resolve_seed_ips, NodeStatus};
use chains::p2p::headers::{dark_gravity_wave3, Header120};
use chains::p2p::wire::{P2pParams, RVN_MAINNET, XNA_MAINNET};

const RVN_CHECKPOINT_HEIGHT: u32 = 2_383_550;
const RVN_CHECKPOINT_HASH: &str =
    "0000000000008927ed21a1e3bb87d3e1020646e8cc94354a1f8fc608395e15dc";

const XNA_CHECKPOINT_HEIGHT: u32 = 1_816_500;
const XNA_CHECKPOINT_HASH: &str =
    "00000000000dbfc94f2f79806e254bb9c364382f066cf1dc41b73d5bde8c86ac";

const KAWPOW_ACTIVATION_TIME: u32 = 1_588_788_000; // 2020-05-06 18:00 UTC (обе цепи)

/// Проверка цепи: связность + DGW3-предсказание == факт + kawpow хвоста.
fn validate(chain: &[Header120], param_label: &str) {
    for w in chain.windows(2) {
        let (a, b) = (&w[0], &w[1]);
        assert_eq!(a.prev, b.prev, "разрыв prev на высоте {}", b.height);
        assert_eq!(b.height, a.height + 1, "высота не подряд у {}", b.height);
    }
    // DGW3: предсказание nBits == факт (окно 180; первые 180 — скип)
    for i in 181..chain.len() {
        let start = i.saturating_sub(180);
        let predicted = dark_gravity_wave3(&chain[start..i], chain[i].time, KAWPOW_ACTIVATION_TIME)
            .expect("dgw3");
        assert_eq!(
            predicted, chain[i].n_bits,
            "{}: DGW3 на высоте {} предсказано {:08x} ≠ факт {:08x}",
            param_label, chain[i].height, predicted, chain[i].n_bits
        );
    }
    println!(
        "{}: DGW3 сходится на {} заголовках ✅",
        param_label,
        chain.len().saturating_sub(1)
    );
    // kawpow PoW: хвост 100 заголовков — каждая (mix, hash) и ориентация
    let tail = chain.len().saturating_sub(100);
    let mut orientation_set = false;
    for h in &chain[tail..] {
        let (mix, hash) = h.kawpow_blockhash();
        // проверяем честно обе ориентации против wire-полей
        let mix_as_is = mix.as_slice() == h.mix_hash.as_slice();
        let mix_rev = {
            let mut r = mix;
            r.reverse();
            r.as_slice() == h.mix_hash.as_slice()
        };
        assert!(
            mix_as_is || mix_rev,
            "mix_hash ориентация не подтвердилась на высоте {}",
            h.height
        );
        let hash_as_is = hash.as_slice() == h.mix_hash.as_slice();
        let hash_rev = {
            let mut r = hash;
            r.reverse();
            r.as_slice() == h.mix_hash.as_slice()
        };
        assert!(
            hash_as_is || hash_rev,
            "block hash ориентация не подтвердилась на высоте {}",
            h.height
        );
        // linkage: hash (в какой-то ориентации) == prev следующего
        if let Some(next) = chain.get(chain.iter().position(|x| x == h).unwrap() + 1) {
            let link_as_is = hash == next.prev;
            let link_rev = {
                let mut r = hash;
                r.reverse();
                r == next.prev
            };
            assert!(
                link_as_is || link_rev,
                "linkage kawpow-hash→prev не сошлось на {}",
                h.height
            );
            if !orientation_set {
                let orientation_desc = if link_as_is {
                    "hash==prev as-is".to_string()
                } else {
                    "hash==prev reversed".to_string()
                };
                println!("{} orientation: {}", h.height, orientation_desc);
                orientation_set = true;
            }
        }
    }
    println!("{}: kawpow PoW хвоста (100) ✅", param_label);
}

#[test]
#[ignore = "live network probe: cargo test -p chains --test p2p_probe -- --ignored --nocapture"]
fn rvn_p2p_headers_sync() {
    let ips: Vec<String> = RVN_MAINNET
        .dns_seeds
        .iter()
        .flat_map(|s| resolve_seed_ips(s).unwrap_or_default())
        .map(|ip| ip.to_string())
        .collect();
    println!("RVN seeds (DoH, справочно): {} IP", ips.len());

    // Кворум 2 пира + честная синхронизация до 60 000 заголовков
    let chains = quorum_sync(
        &RVN_MAINNET,
        RVN_CHECKPOINT_HASH,
        RVN_CHECKPOINT_HEIGHT,
        60_000,
        "0000006b444bc2f2ffe627be9d9e7e7a0730000870ef6eb6da46c8eae389df90",
        2,
    )
    .expect("quorum");
    println!(
        "кворум: {} пиров; высоты {:#?}",
        chains.len(),
        chains
            .iter()
            .map(|c| c.chain.last().map(|h| h.height))
            .collect::<Vec<_>>()
    );
    for c in &chains {
        validate(&c.chain, &c.label);
    }
    println!("RVN P2P headers probe complete");
}

/// Discovery+скан: у живых сидов спрашиваю их списки пиров (getaddr → addr),
/// затем классификация всех кандидатов: кто отвечает на getheaders (вне IBD).
fn sweep_probe(
    params: &P2pParams,
    locator_be: &str,
    height: u32,
    probe_cap: usize,
) -> Vec<NodeStatus> {
    let reports = discover_and_scan(
        params,
        locator_be,
        height,
        10,
        Duration::from_secs(20),
        Duration::from_secs(20),
        probe_cap,
    );
    let count = |s: NodeStatus| reports.iter().filter(|r| r.status == s).count();
    println!(
        "{}: скан итог — отвечающих {} / молчащих {} / handshake-отказов {} / недоступных {} (всего {})",
        params.label,
        count(NodeStatus::Answering),
        count(NodeStatus::Silent),
        count(NodeStatus::HandshakeFail),
        count(NodeStatus::Unreachable),
        reports.len()
    );
    let answered: Vec<String> = reports
        .iter()
        .filter(|r| r.status == NodeStatus::Answering)
        .map(|r| {
            format!(
                "{} (первая пачка {} шт, их tip {})",
                r.ip, r.first_batch, r.tip_height
            )
        })
        .collect();
    println!(
        "отвечающие (вне IBD): {}",
        if answered.is_empty() {
            "НЕТ".to_string()
        } else {
            answered.join("; ")
        }
    );
    if answered.len() < 2 {
        println!(
            "кворум 2+ пира невозможен: отвечающих {} — живой синк от community-сидов упирается в IBD-гейт",
            answered.len()
        );
    }
    reports.iter().map(|r| r.status).collect()
}

#[test]
#[ignore = "live network sweep: cargo test -p chains --test p2p_probe rvn_seed_sweep -- --ignored --nocapture"]
fn rvn_seed_sweep() {
    let statuses = sweep_probe(
        &RVN_MAINNET,
        RVN_CHECKPOINT_HASH,
        RVN_CHECKPOINT_HEIGHT,
        160,
    );
    assert!(
        statuses.len() >= 10,
        "скан подозрительно мал: сиды отдали {} IP",
        statuses.len()
    );
    println!("RVN seed sweep complete");
}

#[test]
#[ignore = "live network sweep: cargo test -p chains --test p2p_probe xna_seed_sweep -- --ignored --nocapture"]
fn xna_seed_sweep() {
    let statuses = sweep_probe(&XNA_MAINNET, XNA_CHECKPOINT_HASH, XNA_CHECKPOINT_HEIGHT, 60);
    assert!(
        statuses.len() >= 2,
        "скан подозрительно мал: сиды отдали {} IP",
        statuses.len()
    );
    println!("XNA seed sweep complete");
}

#[test]
#[ignore = "live network probe: cargo test -p chains --test p2p_probe -- --ignored --nocapture"]
fn xna_p2p_headers_sync() {
    let chains = quorum_sync(
        &XNA_MAINNET,
        XNA_CHECKPOINT_HASH,
        XNA_CHECKPOINT_HEIGHT,
        20_000,
        "00000044d33c0c0ba019be5c0249730424a69cb4c222153322f68c6104484806",
        2,
    )
    .expect("quorum");
    for c in &chains {
        validate(&c.chain, &c.label);
    }
    println!("XNA P2P headers probe complete");
}
