//! One-shot LTC server probe (live network; run manually):
//!   cargo run -p chains --example ltc_probe
//!
//! Connects to every candidate in SERVERS_MAINNET through the real
//! LtcGateway (same path the app will use) and prints identity + tip.

use chains::electrum::Gateway;
use chains::litecoin::{LtcGateway, SERVERS_MAINNET};

fn main() {
    for url in SERVERS_MAINNET {
        print!("{url} => ");
        match LtcGateway::connect(url) {
            Ok(gateway) => match gateway.server_features() {
                Ok((version, pmin, pmax, _genesis)) => {
                    let tip = gateway
                        .tip_height()
                        .map(|t| t.to_string())
                        .unwrap_or_else(|e| format!("tip-err {e}"));
                    println!("{version} {pmin}..{pmax} tip={tip}");
                }
                Err(e) => println!("server_features error: {e}"),
            },
            Err(e) => println!("connect error: {e}"),
        }
    }
}
