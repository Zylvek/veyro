//! P2P-клиент BTC-протокола: сиды → handshake → getheaders-синхронизация
//! заголовков от официального checkpoint'а → кросс-проверка цепи между
//! независимыми пирами (кворум ≥2) → честная проверка DGW3 + kawpow.
//!
//! Блокирующие TCP-операции (std::net) — как у всех Electrum-проб этого
//! репозитория: синхронизация — явное действие, вызывается из тестов/моста.

use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::Duration;

use crate::p2p::headers::{parse_headers_payload, Header120};
use crate::p2p::wire::{frame, getheaders_payload, parse_frame, version_payload, P2pParams};
use crate::ChainError;

const UA: &str = "/veyro:0.1/";
const PROTOCOL_VERSION: i32 = 70016;

/// Живой пир: открытый TCP + прочитанный буфер.
pub struct Peer {
    socket: TcpStream,
    buf: Vec<u8>,
    pub label: String,
}

/// Пир + его независимая цепь заголовков (для кворума).
pub struct PeerChain {
    pub label: String,
    pub chain: Vec<Header120>,
}

/// Раскрутка DNS-сидов: домен сам является сидом (возвращает IP узлов).
pub fn resolve_seed_ips(seed: &str) -> Result<Vec<std::net::IpAddr>, ChainError> {
    let addrs: Vec<_> = (seed, 0u16)
        .to_socket_addrs()
        .map_err(|e| ChainError::Transport(format!("{seed}: resolve: {e}")))?
        .map(|a| a.ip())
        .collect();
    Ok(addrs)
}

impl Peer {
    /// Подключение: TCP + version/verack handshake. Таймауты честные.
    pub fn connect(params: &P2pParams, ip: &str, connect_timeout: Duration) -> Result<Self, ChainError> {
        let socket = TcpStream::connect_timeout(
            &format!("{ip}:{}", params.port).parse().map_err(|e| {
                ChainError::InvalidServerUrl(format!("{ip}: parse: {e}"))
            })?,
            connect_timeout,
        )
        .map_err(|e| ChainError::Transport(format!("{ip}:{connect_timeout:?}: {e}")))?;
        socket
            .set_read_timeout(Some(Duration::from_secs(20)))
            .and_then(|_| socket.set_write_timeout(Some(Duration::from_secs(10))))
            .map_err(|e| ChainError::Transport(format!("{ip}: set timeouts: {e}")))?;
        let mut peer = Self {
            socket,
            buf: Vec::with_capacity(64 * 1024),
            label: format!("{}:{}", ip, params.port),
        };
        peer.handshake(params)?;
        Ok(peer)
    }

    /// version → verack; мусор (ping/addr/sendaddrv2) честно отвечает/пропускает.
    pub fn handshake(&mut self, params: &P2pParams) -> Result<(), ChainError> {
        self.send(params, "version", &version_payload(UA))?;
        // ждём их version (или verack сразу — у форков порядок бывает разный)
        let mut saw_peer_version = false;
        loop {
            let reply = self.next_message(params, Duration::from_secs(30))?;
            match reply.command.as_str() {
                "version" => saw_peer_version = true,
                "verack" if saw_peer_version => break,
                "verack" if !saw_peer_version => break,
                "ping" => self.send(params, "pong", &reply.payload)?,
                "sendaddrv2" | "sendcmpct" | "addr" | "sendheaders" => {}
                "reject" => {
                    return Err(ChainError::Protocol(format!(
                        "{}: reject: {}",
                        self.label,
                        String::from_utf8_lossy(&reply.payload[..reply.payload.len().min(120)])
                    )))
                }
                c => {
                    eprintln!("{}: handshake msg {c} (ignored)", self.label);
                }
            }
        }
        self.send(params, "verack", &[])
    }

    fn send(&mut self, params: &P2pParams, command: &str, payload: &[u8]) -> Result<(), ChainError> {
        let f = frame(params, command, payload)?;
        self.socket
            .write_all(&f)
            .map_err(|e| ChainError::Transport(format!("{}: write {command}: {e}", self.label)))
    }

    /// Читает фреймы до первого не-обязательного (ping → pong, мусор — пропуск).
    pub fn next_message(
        &mut self,
        params: &P2pParams,
        read_timeout: Duration,
    ) -> Result<crate::p2p::wire::Reply, ChainError> {
        self.socket
            .set_read_timeout(Some(read_timeout))
            .map_err(|e| ChainError::Transport(format!("read timeout: {e}")))?;
        loop {
            if let Some((reply, used)) = parse_frame(params, &self.buf)? {
                self.buf.drain(..used);
                match reply.command.as_str() {
                    "ping" => {
                        self.send(params, "pong", &reply.payload)?;
                        continue;
                    }
                    "sendaddrv2" | "sendcmpct" | "addr" | "sendheaders" | "feefilter" | "addrv2" => {
                        continue;
                    }
                    _ => return Ok(reply),
                }
            }
            let mut chunk = [0u8; 65536];
            let n = self
                .socket
                .read(&mut chunk)
                .map_err(|e| ChainError::Transport(format!("{}: read: {e}", self.label)))?;
            if n == 0 {
                return Err(ChainError::Transport(format!(
                    "{}: сервер закрыл соединение",
                    self.label
                )));
            }
            self.buf.extend_from_slice(&chunk[..n]);
        }
    }

    /// getheaders: запросить цепь от start_hash (BE-hex) до упора;
    /// возвращает заголовки пачки (для цикла синка).
    pub fn request_headers(
        &mut self,
        params: &P2pParams,
        start_hash_be: &str,
    ) -> Result<Vec<Header120>, ChainError> {
        self.send(
            params,
            "getheaders",
            &getheaders_payload(PROTOCOL_VERSION, start_hash_be)?,
        )?;
        loop {
            let reply = self.next_message(params, Duration::from_secs(45))?;
            match reply.command.as_str() {
                "headers" => return parse_headers_payload(&reply.payload),
                "ping" => continue,
                c if c.starts_with("send") || c == "addr" || c == "feefilter" || c == "verack" => {
                    continue
                }
                c => {
                    return Err(ChainError::Protocol(format!(
                        "{}: ждали headers, получили {c}",
                        self.label
                    )))
                }
            }
        }
    }
}

/// Синхронизация заголовков от checkpoint'а у ОДНОГО пира. Максимум
/// `max_headers` — честная граница пробы; пустой ответ = доехали до tip.
pub fn sync_headers(
    peer: &mut Peer,
    params: &P2pParams,
    checkpoint_hash_be: &str,
    checkpoint_height: u32,
    max_headers: u32,
    progress: &mut dyn FnMut(u32),
) -> Result<(Vec<Header120>, bool), ChainError> {
    let mut chain: Vec<Header120> = Vec::new();
    let mut locator = checkpoint_hash_be.to_string();
    let mut caught_up = false;
    while (chain.len() as u32) < max_headers && !caught_up {
        let batch = peer.request_headers(params, &locator)?;
        if batch.is_empty() {
            caught_up = true;
            break;
        }
        // Связность внутри пачки и с предыдущей
        if let (Some(last), Some(first)) = (chain.last(), batch.first()) {
            if last.prev != first.prev {
                return Err(ChainError::Protocol(format!(
                    "{}: разрыв цепи на высоте {}",
                    peer.label, first.height
                )));
            }
        }
        chain.extend(batch.iter().copied());
        locator = hex_le_to_be(batch.last().expect("batch non-empty").prev);
        progress(chain.len() as u32);
    }
    // Первая высота ровно checkpoint+1 (заголовок nHeight честно в wire)
    if let Some(first) = chain.first() {
        if first.height != checkpoint_height + 1 {
            return Err(ChainError::Protocol(format!(
                "{}: первая высота {} ≠ checkpoint+1",
                peer.label, first.height
            )));
        }
    }
    Ok((chain, caught_up))
}

/// hex (BE-отображение) → LE-байты (для локатора getheaders).
fn hex_le_to_be(le_bytes: [u8; 32]) -> String {
    let mut rev = le_bytes;
    rev.reverse();
    hex::encode(rev)
}

/// Кворум: синхронизируем K пиров (по очереди, от сидов), сверяем их цепи
/// ПОБАЙТОВО. Расхождение/ошибка пира — честный отказ с перечнем.
pub fn quorum_sync(
    params: &P2pParams,
    checkpoint_hash_be: &str,
    checkpoint_height: u32,
    max_headers: u32,
    peers_wanted: usize,
) -> Result<Vec<PeerChain>, ChainError> {
    let mut chains: Vec<PeerChain> = Vec::new();
    let mut tried = 0usize;
    for seed in params.dns_seeds {
        if chains.len() >= peers_wanted || tried >= 12 {
            break;
        }
        let ips = resolve_seed_ips(seed)?;
        for ip in ips {
            if chains.len() >= peers_wanted || tried >= 12 {
                break;
            }
            tried += 1;
            let mut peer = match Peer::connect(params, &ip.to_string(), Duration::from_secs(8)) {
                Ok(p) => p,
                Err(e) => {
                    eprintln!("seed {seed} ip {ip}: {e}");
                    continue;
                }
            };
            let mut progress = |_n: u32| {};
            let (chain, _up) =
                match sync_headers(&mut peer, params, checkpoint_hash_be, checkpoint_height, max_headers, &mut progress) {
                    Ok(v) => v,
                    Err(e) => {
                        eprintln!("{}: sync failed: {e}", peer.label);
                        continue;
                    }
                };
            // Кворум: побайтовое сравнение с уже собранными цепями
            if let Some(first) = chains.first() {
                if chain.len() != first.chain.len()
                    || chain[..].iter().zip(first.chain.iter()).any(|(a, b)| a.raw != b.raw)
                {
                    return Err(ChainError::Protocol(format!(
                        "{}: цепь расходится с первым пиром",
                        peer.label
                    )));
                }
            }
            chains.push(PeerChain {
                label: peer.label.clone(),
                chain,
            });
        }
    }
    if chains.len() < 2 {
        return Err(ChainError::Transport(format!(
            "кворум собран {}: нужно ≥2 независимых пиров",
            chains.len()
        )));
    }
    Ok(chains)
}
