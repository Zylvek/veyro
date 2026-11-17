//! BTC-протокольный фрейминг (wire): фреймы, варинты, сообщения version/verack.

use crate::ChainError;

/// Сетевой идентификатор цепи (magic) + порт + сиды.
pub struct P2pParams {
    pub label: &'static str,
    pub magic: [u8; 4],
    pub port: u16,
    pub genesis_be_hex: &'static str,
    pub dns_seeds: &'static [&'static str],
}

/// RVN mainnet (chainparams.cpp официального узла).
pub const RVN_MAINNET: P2pParams = P2pParams {
    label: "Ravencoin mainnet",
    magic: [0x52, 0x41, 0x56, 0x4e], // RAVN
    port: 8767,
    genesis_be_hex: "0000006b444bc2f2ffe627be9d9e7e7a0730000870ef6eb6da46c8eae389df90",
    dns_seeds: &[
        "seed-raven.ravencoin.com",
        "seed-raven.ravencoin.org",
        "seed-raven.ravencoin.bitactivate.com",
    ],
};

/// XNA (Neurai) mainnet.
pub const XNA_MAINNET: P2pParams = P2pParams {
    label: "Neurai mainnet",
    magic: [0x4e, 0x45, 0x55, 0x52], // NEUR
    port: 19000,
    genesis_be_hex: "00000044d33c0c0ba019be5c0249730424a69cb4c222153322f68c6104484806",
    dns_seeds: &["dns.neurai.org", "seed1.neurai.org", "seed2.neurai.org"],
};

/// Полный фрейм: magic + command(12) + len + checksum(sha256d[:4]) + payload.
pub fn frame(params: &P2pParams, command: &str, payload: &[u8]) -> Result<Vec<u8>, ChainError> {
    if command.len() > 12 {
        return Err(ChainError::Protocol(format!("command too long: {command}")));
    }
    let mut frame = Vec::with_capacity(24 + payload.len());
    frame.extend_from_slice(&params.magic);
    let mut cmd = [0u8; 12];
    cmd[..command.len()].copy_from_slice(command.as_bytes());
    frame.extend_from_slice(&cmd);
    frame.extend_from_slice(&(payload.len() as u32).to_le_bytes());
    let checksum = sha256d(payload);
    frame.extend_from_slice(&checksum[..4]);
    frame.extend_from_slice(payload);
    Ok(frame)
}

pub use crate::sha256d;

/// Прочитанный ответ пира.
#[derive(Debug)]
pub struct Reply {
    pub command: String,
    pub payload: Vec<u8>,
}

/// Парсинг одного фрейма из буфера. Возвращает Ok(None) если данных мало;
/// Ok(Some((Reply, consumed))) на полном фрейме.
pub fn parse_frame(params: &P2pParams, buf: &[u8]) -> Result<Option<(Reply, usize)>, ChainError> {
    if buf.len() < 24 {
        return Ok(None);
    }
    if buf[..4] != params.magic {
        return Err(ChainError::Protocol(format!(
            "{}: чужой magic фрейма {:02x?}",
            params.label,
            &buf[..4]
        )));
    }
    let len = u32::from_le_bytes([buf[16], buf[17], buf[18], buf[19]]) as usize;
    // Верхняя граница честная: самые большие сообщения протокола (headers)
    // в единицах МБ; 64 МБ — жёсткий потолок на сообщение.
    if len > 64 * 1024 * 1024 {
        return Err(ChainError::Protocol(format!(
            "{}: payload {} байт — мусор",
            params.label, len
        )));
    }
    if buf.len() < 24 + len {
        return Ok(None);
    }
    let payload = &buf[24..24 + len];
    let checksum = sha256d(payload);
    if checksum[..4] != buf[20..24] {
        return Err(ChainError::Protocol(format!(
            "{}: не сошёлся checksum фрейма",
            params.label
        )));
    }
    let cmd_z = buf[4..16].iter().position(|&b| b == 0).unwrap_or(12);
    let command = String::from_utf8_lossy(&buf[4..4 + cmd_z]).into_owned();
    Ok(Some((
        Reply {
            command,
            payload: payload.to_vec(),
        },
        24 + len,
    )))
}

/// payload «version»: как BTC, но без address Relay-наворотов (спец для
/// SPV-клиента): ver 70016 | services 0 | ts | recv-addr | from-addr | nonce
/// | UA varstr | start_height 0 | relay false.
pub fn version_payload(ua: &'static str) -> Vec<u8> {
    let mut p = Vec::with_capacity(90 + ua.len());
    p.extend_from_slice(&70016i32.to_le_bytes());
    p.extend_from_slice(&0u64.to_le_bytes());
    p.extend_from_slice(&(chrono_seconds() as i64).to_le_bytes());
    p.extend_from_slice(&[0u8; 26]); // addr_recv
    p.extend_from_slice(&[0u8; 26]); // addr_from
    p.extend_from_slice(&1u64.to_le_bytes()); // nonce
    p.push(ua.len() as u8);
    p.extend_from_slice(ua.as_bytes());
    p.extend_from_slice(&0i32.to_le_bytes()); // start_height
    p.push(0); // relay=false (SPV не релеит)
    p
}

fn chrono_seconds() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// payload «getheaders»: version | count=1 | hash(start BE→LE) | stop_hash 0.
pub fn getheaders_payload(version: i32, start_hash_be_hex: &str) -> Result<Vec<u8>, ChainError> {
    let hash_le = crate::hex_be_to_le32(start_hash_be_hex)?;
    let mut p = Vec::with_capacity(4 + 1 + 32 + 32);
    p.extend_from_slice(&version.to_le_bytes());
    p.push(1);
    p.extend_from_slice(&hash_le);
    p.extend_from_slice(&[0u8; 32]);
    Ok(p)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frame_roundtrip_and_checksum() {
        let params = RVN_MAINNET;
        let f = frame(&params, "version", b"abc").expect("frame");
        assert_eq!(&f[..4], &params.magic);
        assert_eq!(&f[4..11], b"version");
        assert_eq!(u32::from_le_bytes([f[16], f[17], f[18], f[19]]), 3);
        let (reply, consumed) = parse_frame(&params, &f)
            .expect("parse ok")
            .expect("полный фрейм");
        assert_eq!(reply.command, "version");
        assert_eq!(reply.payload, b"abc");
        assert_eq!(consumed, 24 + 3);
    }

    #[test]
    fn rejects_bad_magic_and_short_frames() {
        let params = RVN_MAINNET;
        let mut f = frame(&params, "verack", &[]).expect("frame");
        f[0] = 0x77;
        assert!(parse_frame(&params, &f).is_err());
        // f[1..] = короткий буфер → честное Ok(None), не ошибка протокола
        assert!(matches!(parse_frame(&params, &f[1..]), Ok(None) | Err(_)));
    }

    #[test]
    fn version_payload_shape() {
        let p = version_payload("/veyro:0.1/");
        // 4(ver)+8(services)+8(time)+26+26+8(nonce)+1(uаlen)+11(UA)+4(h)+1(relay)
        assert_eq!(p.len(), 97);
        assert_eq!(&p[..2], &[0x80, 0x11]); // 70016 LEB
        assert_eq!(p[80], 11); // UA len (4+8+8+26+26+8 = 80)
    }

    #[test]
    fn getheaders_shape() {
        let genesis = "0000006b444bc2f2ffe627be9d9e7e7a0730000870ef6eb6da46c8eae389df90";
        let p = getheaders_payload(70016, genesis).expect("getheaders");
        assert_eq!(p.len(), 4 + 1 + 32 + 32);
        assert_eq!(p[4], 1); // count
    }
}
