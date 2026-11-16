//! Failover candidate rotation and missing-tx classification (pure logic, no
//! network — servers listed here are only used as strings).

use chains::electrum::{failover_candidates, is_missing_tx_error, BtcNetwork};
use chains::litecoin::ltc_failover_candidates;

#[test]
fn btc_failover_rotates_failed_server_to_last() {
    let all = failover_candidates(BtcNetwork::Mainnet, "");
    assert_eq!(all.len(), 3);

    // The failed URL moves to the end; the others keep their order.
    let rotated = failover_candidates(BtcNetwork::Mainnet, &all[1]);
    assert_eq!(rotated[0], all[0]);
    assert_eq!(rotated[1], all[2]);
    assert_eq!(rotated[2], all[1]);
    assert_ne!(
        rotated.first().unwrap(),
        &all[1],
        "failed server must not be first"
    );

    // A single-preset network (testnet) still yields its one preset.
    let t = failover_candidates(BtcNetwork::Testnet, &all[0]);
    assert_eq!(t.len(), 1);
    assert_eq!(t[0], "ssl://electrum.blockstream.info:60002");
}

#[test]
fn ltc_failover_rotates_failed_server_to_last() {
    let all = ltc_failover_candidates("");
    assert_eq!(all.len(), 3);
    let rotated = ltc_failover_candidates(&all[0]);
    assert_eq!(rotated.len(), 3);
    assert_ne!(rotated.first().unwrap(), &all[0]);
    for url in &all {
        assert!(rotated.contains(url), "rotation must keep every candidate");
    }
}

#[test]
fn missing_tx_only_from_protocol_errors() {
    // Server-reported absence indicators — recognized (Fulcrum/ElectrumX
    // wordings for mempool and confirmed txs).
    assert!(is_missing_tx_error(&electrum_client::Error::Protocol(
        "no such mempool transaction".into()
    )));
    assert!(is_missing_tx_error(&electrum_client::Error::Protocol(
        "tx not in block chain".into()
    )));
    assert!(is_missing_tx_error(&electrum_client::Error::Message(
        "unknown transaction".into()
    )));

    // Transport failures must NEVER be mistaken for "tx missing", even when
    // their text contains a matching substring (DNS "host not found").
    let dns = electrum_client::Error::IOError(std::io::Error::other("dns lookup: host not found"));
    assert!(!is_missing_tx_error(&dns));

    let attempts = electrum_client::Error::AllAttemptsErrored(vec![dns]);
    assert!(!is_missing_tx_error(&attempts));
}
