use electrum_client::{Client, ConfigBuilder, ElectrumApi};

fn main() {
    for url in [
        "ssl://fulcrum.bullbitcoin.com:50002",
        "tcp://electrum.blockstream.info:50001",
    ] {
        let config = ConfigBuilder::new().retry(1).timeout(Some(6)).build();
        println!("try {url}");
        match Client::from_config(url, config) {
            Ok(c) => match c.server_features() {
                Ok(f) => println!("OK {:?}", f.server_version),
                Err(e) => println!("FEATURES ERR {e:#?}"),
            },
            Err(e) => println!("CONNECT ERR {e:#?}"),
        }
    }
}
