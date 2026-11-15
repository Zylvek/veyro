//! BTC session error paths through the bridge API — the fund-safety gate:
//! a wrong network code, a malformed server URL or an unreachable server must
//! leave NO session behind (the seed of the unlocked wallet is dropped with
//! the failed unlock attempt).
//!
//! Live-server flows are covered by the gated E2E test suite; here we only
//! pin the deterministic failure paths of `btc_unlock`.

use veyro_bridge::api::{btc, session, wallet};

fn tmp_base() -> String {
    std::env::var("VEYRO_TEST_TMP").unwrap_or_else(|_| r"D:\tmp\veyro-tests".to_string())
}

fn unique_dir(tag: &str) -> String {
    let dir = std::path::Path::new(&tmp_base()).join(format!("btc-{}-{}", std::process::id(), tag));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir.to_string_lossy().into_owned()
}

#[test]
fn btc_unlock_failure_paths_leave_no_session() {
    let dir = unique_dir("paths");
    let created = wallet::create_wallet(dir.clone(), "Btc".into(), "pw 456".into(), 12).unwrap();

    // Preconditions: no session, and locking without a session is a no-op.
    assert!(session::btc_session_state().unwrap().is_none());
    btc::btc_lock().unwrap();

    // 1. Unknown network code is refused before any I/O.
    let err = btc::btc_unlock(
        dir.clone(),
        created.info.id.clone(),
        "pw 456".into(),
        7,
        "tcp://127.0.0.1:9".into(),
    )
    .unwrap_err();
    assert!(
        err.to_string().contains("unknown Bitcoin network code 7"),
        "got: {err}"
    );
    assert!(session::btc_session_state().unwrap().is_none());

    // 2. Malformed server URL is refused.
    let err = btc::btc_unlock(
        dir.clone(),
        created.info.id.clone(),
        "pw 456".into(),
        1,
        "http://example.com:50001".into(),
    )
    .unwrap_err();
    assert!(
        err.to_string().contains("tcp://") || err.to_string().contains("ssl://"),
        "got: {err}"
    );
    assert!(session::btc_session_state().unwrap().is_none());

    // 3. Unreachable server (connection closed on the discard port) — a
    //    transport error, no session, and the wallet password was correct
    //    (proving the failure happens at the network step, not decrypt).
    let err = btc::btc_unlock(
        dir.clone(),
        created.info.id.clone(),
        "pw 456".into(),
        1,
        "tcp://127.0.0.1:9".into(),
    )
    .unwrap_err();
    assert!(!err.to_string().is_empty(), "transport failure expected");
    assert!(session::btc_session_state().unwrap().is_none());

    // 4. Wrong password fails before connecting (secret path first).
    let err = btc::btc_unlock(
        dir.clone(),
        created.info.id.clone(),
        "wrong".into(),
        1,
        "tcp://127.0.0.1:9".into(),
    )
    .unwrap_err();
    assert!(!err.to_string().is_empty(), "decrypt failure expected");
    assert!(session::btc_session_state().unwrap().is_none());
}
