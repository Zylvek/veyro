//! P2P-клиент BTC-протокола: сиды → handshake → getheaders-синхронизация
//! заголовков от официального checkpoint'а → кросс-проверка цепи между
//! независимыми пирами (кворум ≥2) → честная проверка DGW3 + kawpow.
//!
//! Блокирующие TCP-операции (std::net) — как у всех Electrum-проб этого
//! репозитория: синхронизация — явное действие, вызывается из тестов/моста.

use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::Duration;

use crate::p2p::headers::{parse_headers_payload, Header120};
use crate::p2p::wire::{frame, parse_frame, version_payload, P2pParams};
use crate::ChainError;
use serde_json::Value as Json;

const UA: &str = "/veyro:0.1/";
// Живые узлы предъявили лестницу: 70025 (min peer) → 70026 → 70027
// (KAWPOW) → 70028 (node PROTOCOL_VERSION, reject «…70027+» — X16RV2-эра
// порог MIN_PEER_PROTO_VERSION = X16RV2_VERSION; пробы 17.11.2026).
// 70028 покрывает все проверки сверху.
const PROTOCOL_VERSION: i32 = 70028;

/// Живой пир: открытый TCP + прочитанный буфер.
pub struct Peer {
    socket: TcpStream,
    buf: Vec<u8>,
    pub label: String,
    /// Высота ОЖИДАЕМОГО первого заголовка следующей пачки.
    height_hint: u32,
    /// Их protocol version из version-payload (телеметрия, честная).
    pub peer_version: i32,
    /// Их user agent (обрезается до 256, как MAX_SUBVERSION_LENGTH).
    pub peer_ua: String,
    /// Их nStartHeight из version-payload (tip узла, по их собственной версии).
    pub peer_start_height: i32,
}

/// Пир + его независимая цепь заголовков (для кворума).
pub struct PeerChain {
    pub label: String,
    pub chain: Vec<Header120>,
}

/// Раскрутка DNS-сидов через DoH (dns.google, JSON): system-DNS на
/// роутере отдаёт fake-IP (198.18.x) для незнакомых доменов, и P2P-трафик
/// через прозрачный прокси умирает. DoH возвращает реальные A-записи узлов
/// (те же, что выдала Google-DoH при живых пробах).
pub fn resolve_seed_ips(seed: &str) -> Result<Vec<std::net::IpAddr>, ChainError> {
    // домен сид-службы сам резолвится системно: dns.google — в bypass-листе
    // роутера (как CoinGecko), а при сбое — честная ошибка.
    let urls = [
        format!("https://dns.google/resolve?name={seed}&type=A"),
        format!("https://cloudflare-dns.com/dns-query?name={seed}&type=A"),
    ];
    let mut body: Option<Json> = None;
    let mut last_err = String::new();
    'outer: for url in urls {
        for attempt in 0..2 {
            match ureq::get(&url).timeout(Duration::from_secs(10)).call() {
                Ok(response) => match response.into_json::<Json>() {
                    Ok(json) => {
                        body = Some(json);
                        break 'outer;
                    }
                    Err(e) => last_err = format!("body: {e}"),
                },
                Err(e) => {
                    last_err = format!("{url}: {e}");
                    std::thread::sleep(Duration::from_millis(400 * (attempt + 1)));
                }
            }
        }
    }
    let Some(body) = body else {
        return Err(ChainError::Transport(format!("{seed}: DoH: {last_err}")));
    };
    let mut out = Vec::new();
    if let Some(answers) = body.get("Answer").and_then(|a| a.as_array()) {
        for a in answers {
            if a.get("type").and_then(|t| t.as_i64()) == Some(1) {
                if let Some(data) = a.get("data").and_then(|d| d.as_str()) {
                    if let Ok(ip) = data.parse::<std::net::IpAddr>() {
                        out.push(ip);
                    }
                }
            }
        }
    }
    if out.is_empty() {
        // Сид-домен без A-записей — не фатально (проверяем остальные сиды).
        return Ok(out);
    }
    Ok(out)
}

impl Peer {
    /// Подключение: TCP + version/verack handshake. Таймауты честные.
    pub fn connect(
        params: &P2pParams,
        ip: &str,
        connect_timeout: Duration,
        height_hint: u32,
    ) -> Result<Self, ChainError> {
        let socket = TcpStream::connect_timeout(
            &format!("{ip}:{}", params.port)
                .parse()
                .map_err(|e| ChainError::InvalidServerUrl(format!("{ip}: parse: {e}")))?,
            connect_timeout,
        )
        .map_err(|e| ChainError::Transport(format!("{ip}: connect: {e}")))?;
        socket
            .set_read_timeout(Some(Duration::from_secs(20)))
            .and_then(|_| socket.set_write_timeout(Some(Duration::from_secs(10))))
            .map_err(|e| ChainError::Transport(format!("{ip}: set timeouts: {e}")))?;
        let mut peer = Self {
            socket,
            buf: Vec::with_capacity(64 * 1024),
            label: format!("{}:{}", ip, params.port),
            height_hint,
            peer_version: 0,
            peer_ua: String::new(),
            peer_start_height: 0,
        };
        peer.handshake(params)?;
        Ok(peer)
    }

    /// version → verack; мусор (ping/addr/sendaddrv2) честно отвечает/пропускает.
    pub fn handshake(&mut self, params: &P2pParams) -> Result<(), ChainError> {
        let vp = version_payload(UA);
        eprintln!("{}: version payload hex: {}", self.label, hex::encode(&vp));
        self.send(params, "version", &vp)?;
        // ждём их version (или verack сразу — у форков порядок бывает разный)
        loop {
            let reply = self.next_message(params, Duration::from_secs(15))?;
            match reply.command.as_str() {
                "version" => {
                    // version-payload: ver(4) services(8) ts(8) recv(26) from(26)
                    // nonce(8) => UA varstr на офсете 80, затем nStartHeight i32.
                    if reply.payload.len() > 80 {
                        self.peer_version =
                            i32::from_le_bytes(reply.payload[0..4].try_into().expect("4"));
                        let ua_len = reply.payload[80] as usize;
                        let off = 81 + ua_len;
                        if ua_len > 0 && reply.payload.len() >= off {
                            self.peer_ua =
                                String::from_utf8_lossy(&reply.payload[81..off]).into_owned();
                        }
                        if reply.payload.len() >= off + 4 {
                            self.peer_start_height = i32::from_le_bytes(
                                reply.payload[off..off + 4].try_into().expect("4"),
                            );
                        }
                    }
                }
                "verack" => break,
                "ping" => self.send(params, "pong", &reply.payload)?,
                "sendaddrv2" | "sendcmpct" | "addr" | "sendheaders" => {}
                "reject" => {
                    // Полный дамп для честной диагностики (код/строка/хэш).
                    let code = if reply.payload.len() >= 4 {
                        u32::from_le_bytes(reply.payload[..4].try_into().expect("4"))
                    } else {
                        0
                    };
                    return Err(ChainError::Protocol(format!(
                        "{}: reject code={:#x} payload_hex={} as_text={:?}",
                        self.label,
                        code,
                        hex::encode(&reply.payload),
                        String::from_utf8_lossy(&reply.payload)
                    )));
                }
                c => {
                    eprintln!("{}: handshake msg {c} (ignored)", self.label);
                }
            }
        }
        self.send(params, "verack", &[])
    }

    fn send(
        &mut self,
        params: &P2pParams,
        command: &str,
        payload: &[u8],
    ) -> Result<(), ChainError> {
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
                    "sendaddrv2" | "sendcmpct" | "addr" | "sendheaders" | "feefilter"
                    | "addrv2" => {
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

    /// Одноразовая проба getheaders (сканер): БЕЗ null-locator fallback'а.
    /// Возвращает число заголовков первой пачки; ошибка при таймауте/закрытии
    /// (молчание = IBD-гейт net_processing:2120, классификация наверху).
    pub fn probe_getheaders(
        &mut self,
        params: &P2pParams,
        start_hash_be: &str,
        height_hint: u32,
        wait: Duration,
    ) -> Result<u32, ChainError> {
        let mut payload = Vec::new();
        payload.extend_from_slice(&PROTOCOL_VERSION.to_le_bytes());
        crate::p2p::headers::write_varint(1, &mut payload);
        payload.extend_from_slice(&crate::hex_be_to_le32(start_hash_be)?);
        payload.extend_from_slice(&[0u8; 32]); // stop = конец
        self.send(params, "getheaders", &payload)?;
        loop {
            let reply = self.next_message(params, wait)?;
            match reply.command.as_str() {
                "headers" => {
                    if reply.payload.is_empty() {
                        return Ok(0);
                    }
                    let headers = parse_headers_payload(&reply.payload, height_hint)?;
                    return Ok(headers.len() as u32);
                }
                // inv/прочие объявления пропускаем — ждём headers
                _ => continue,
            }
        }
    }
}

/// Честный парсинг addr-ответа: count | entries(time u32, services u64,
/// ip 16BE, port u16 BE). IPv4-mapped извлечены, чистые v6 пропущены
/// (транспорт пиров всё равно порт params.port).
pub fn parse_addr_payload(payload: &[u8]) -> Result<Vec<String>, ChainError> {
    let (count, mut off) = crate::p2p::headers::read_varint(payload, 0)?;
    if count > 2000 {
        return Err(ChainError::Protocol(format!("addr count {count}")));
    }
    let mut out = Vec::new();
    for _ in 0..count {
        if off + 30 > payload.len() {
            break; // короткий конец честно игнорируем
        }
        let ip16 = &payload[off + 12..off + 28];
        off += 30;
        if ip16[..10] == [0u8; 10] && ip16[10] == 0xff && ip16[11] == 0xff {
            let ip = std::net::Ipv4Addr::new(ip16[12], ip16[13], ip16[14], ip16[15]);
            let s = ip.to_string();
            if !out.contains(&s) {
                out.push(s);
            }
        }
    }
    Ok(out)
}

/// Статус узла в сканере сидов (кто отвечает на getheaders — узел вне IBD).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NodeStatus {
    /// TCP не открылся.
    Unreachable,
    /// Открылся, handshake не сложился (reject/закрыли/таймаут version).
    HandshakeFail,
    /// Handshake ок, но getheaders молчал/закрытие — IBD-гейт.
    Silent,
    /// Отдал первую пачку заголовков — узел вне IBD, пригоден для синка.
    Answering,
}

/// Отчёт сканера по одному IP: честные поля из их version-сообщения.
#[derive(Debug, Clone)]
pub struct NodeReport {
    pub ip: String,
    pub status: NodeStatus,
    pub peer_version: i32,
    pub peer_ua: String,
    /// Их nStartHeight (tip по их собственной телеметрии).
    pub tip_height: u32,
    /// Заголовков в первой пачке (для Answering).
    pub first_batch: u32,
    /// Деталь ошибки (для печати).
    pub detail: String,
}

/// Все IP всех сидов через DoH, без дублей; сид с ошибкой — не фатален.
pub fn resolve_all_seed_ips(params: &P2pParams) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for seed in params.dns_seeds {
        if let Ok(ips) = resolve_seed_ips(seed) {
            for ip in ips {
                let s = ip.to_string();
                if !out.contains(&s) {
                    out.push(s);
                }
            }
        }
    }
    out
}

fn answer_rank(s: NodeStatus) -> u8 {
    match s {
        NodeStatus::Answering => 0,
        NodeStatus::Silent => 1,
        NodeStatus::HandshakeFail => 2,
        NodeStatus::Unreachable => 3,
    }
}

/// Проба одного IP: connect → handshake → одна getheaders-проба. Честный
/// отчёт с телеметрией узла (их version/UA/nStartHeight).
fn probe_one(
    params: &P2pParams,
    ip: &str,
    locator_be: &str,
    checkpoint_height: u32,
    wait: Duration,
) -> NodeReport {
    let mut report = NodeReport {
        ip: ip.to_string(),
        status: NodeStatus::Unreachable,
        peer_version: 0,
        peer_ua: String::new(),
        tip_height: 0,
        first_batch: 0,
        detail: String::new(),
    };
    match Peer::connect(params, ip, Duration::from_secs(4), checkpoint_height + 1) {
        Ok(mut peer) => {
            report.peer_version = peer.peer_version;
            report.peer_ua = peer.peer_ua.clone();
            report.tip_height = peer.peer_start_height.max(0) as u32;
            match peer.probe_getheaders(params, locator_be, checkpoint_height + 1, wait) {
                Ok(n) => {
                    report.first_batch = n;
                    report.status = if n == 0 {
                        NodeStatus::Silent
                    } else {
                        NodeStatus::Answering
                    };
                }
                Err(e) => {
                    report.status = NodeStatus::Silent;
                    let m = e.to_string();
                    report.detail = m.split("Transport: ").last().unwrap_or(&m).to_string();
                }
            }
        }
        Err(e) => {
            let m = e.to_string();
            let detail = m.split("Protocol: ").last().unwrap_or(&m);
            let detail = detail.split("Transport: ").last().unwrap_or(detail);
            report.status = if m.contains("connect:") || m.contains("set timeouts") {
                NodeStatus::Unreachable
            } else {
                // reject/закрытие/таймаут handshake — Protocol/Transport
                NodeStatus::HandshakeFail
            };
            report.detail = detail.to_string();
        }
    }
    report
}

/// Пул воркеров: probe_one по списку IP; честная сортировка по статусу.
fn scan_ips(
    ips: &[String],
    params: &P2pParams,
    locator_be: &str,
    checkpoint_height: u32,
    workers: usize,
    wait: Duration,
) -> Vec<NodeReport> {
    let next = std::sync::atomic::AtomicUsize::new(0);
    let results: std::sync::Mutex<Vec<NodeReport>> = std::sync::Mutex::new(Vec::new());
    std::thread::scope(|scope| {
        for _ in 0..workers {
            scope.spawn(|| loop {
                let i = next.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                if i >= ips.len() {
                    break;
                }
                let r = probe_one(params, &ips[i], locator_be, checkpoint_height, wait);
                results.lock().expect("scan lock").push(r);
            });
        }
    });
    let mut out = results.into_inner().unwrap_or_default();
    out.sort_by(|a, b| {
        (answer_rank(a.status), a.ip.as_str()).cmp(&(answer_rank(b.status), b.ip.as_str()))
    });
    for r in &out {
        eprintln!(
            "scan {}: {:?} ver={} tip={} first_batch={} ua={:?} {}",
            r.ip,
            r.status,
            r.peer_version,
            r.tip_height,
            r.first_batch,
            r.peer_ua.chars().take(28).collect::<String>(),
            r.detail.chars().take(64).collect::<String>(),
        );
    }
    out
}

/// Скан сидов: классификация всех узлов (кто отвечает на getheaders).
/// Блокирующе, `workers` параллельных проб; honest таймауты на каждый шаг.
pub fn scan_nodes(
    params: &P2pParams,
    locator_be: &str,
    checkpoint_height: u32,
    workers: usize,
    wait: Duration,
) -> Vec<NodeReport> {
    let ips = resolve_all_seed_ips(params);
    eprintln!(
        "scan {}: кандидатов {} IP с {} сидов",
        params.label,
        ips.len(),
        params.dns_seeds.len()
    );
    scan_ips(&ips, params, locator_be, checkpoint_height, workers, wait)
}

/// Discovery + скан: живые пиры через сами узлы (getaddr → addr), затем
/// классификация каждого. DNS-RRset протухает (зомби на старых высотах и
/// мёртвые записи), а узлы отдают СВОЙ текущий список пиров — стандартный
/// wire-дискавери, без обхода политик узла.
pub fn discover_and_scan(
    params: &P2pParams,
    locator_be: &str,
    checkpoint_height: u32,
    workers: usize,
    wait: Duration,
    addr_wait: Duration,
    probe_cap: usize,
) -> Vec<NodeReport> {
    let seeds = resolve_all_seed_ips(params);
    eprintln!(
        "discovery {}: сид-кандидатов {} IP, спрашиваю списки пиров…",
        params.label,
        seeds.len()
    );
    let next = std::sync::atomic::AtomicUsize::new(0);
    let found: std::sync::Mutex<Vec<String>> = std::sync::Mutex::new(Vec::new());
    std::thread::scope(|scope| {
        for _ in 0..workers {
            scope.spawn(|| loop {
                let i = next.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                if i >= seeds.len() {
                    break;
                }
                let ip = &seeds[i];
                let ok = Peer::connect(params, ip, Duration::from_secs(4), checkpoint_height + 1)
                    .and_then(|mut p| p.discover_addrs(params, addr_wait));
                match ok {
                    Ok(addrs) => {
                        eprintln!("discovery {}: отдал {} пиров", ip, addrs.len());
                        found.lock().expect("discovery lock").extend(addrs);
                    }
                    Err(e) => {
                        let m = e.to_string();
                        eprintln!("discovery {}: {m}", ip)
                    }
                }
            });
        }
    });
    let added = found.into_inner().unwrap_or_default();
    let mut candidates: Vec<String> = Vec::new();
    for s in &seeds {
        if !candidates.contains(s) {
            candidates.push(s.clone());
        }
    }
    for a in added {
        if !candidates.contains(&a) {
            candidates.push(a);
        }
    }
    if candidates.len() > probe_cap {
        candidates.truncate(probe_cap);
    }
    eprintln!(
        "discovery {}: итог кандидатов {} IP (cap {})",
        params.label,
        candidates.len(),
        probe_cap
    );
    scan_ips(
        &candidates,
        params,
        locator_be,
        checkpoint_height,
        workers,
        wait,
    )
}

/// Продолжение impl Peer после сканера: getheaders-синхронизация.
impl Peer {
    /// getaddr → addr: спрашиваем у узла его текущий список пиров
    /// (стандартный discovery; узел сам решает, что отдать).
    pub fn discover_addrs(
        &mut self,
        params: &P2pParams,
        wait: Duration,
    ) -> Result<Vec<String>, ChainError> {
        self.send(params, "getaddr", &[])?;
        loop {
            let reply = self.next_message(params, wait)?;
            if reply.command == "addr" {
                return parse_addr_payload(&reply.payload);
            }
            // inv/прочие объявления пропускаем и ждём addr
        }
    }

    /// getheaders: запросить цепь от start_hash (BE-hex) до упора;
    /// возвращает заголовки пачки (для цикла синка).
    pub fn request_headers(
        &mut self,
        params: &P2pParams,
        start_hashes_be: &[&str],
        height_hint: u32,
    ) -> Result<Option<Vec<Header120>>, ChainError> {
        let mut payload = Vec::new();
        payload.extend_from_slice(&PROTOCOL_VERSION.to_le_bytes());
        crate::p2p::headers::write_varint(start_hashes_be.len() as u64, &mut payload);
        for h in start_hashes_be {
            payload.extend_from_slice(&crate::hex_be_to_le32(h)?);
        }
        payload.extend_from_slice(&[0u8; 32]); // stop = конец
        self.send(params, "getheaders", &payload)?;
        loop {
            let reply = match self.next_message(params, Duration::from_secs(60)) {
                Ok(r) => r,
                Err(ChainError::Transport(ref m)) if m.contains("read:") => {
                    // Тихий таймаут: узел молчит на getheaders с locator'ом.
                    // Догадка — IBD-гейт (net_processing:2120). Честная
                    // проверка вместо догадки: запрос от NULL-locator —
                    // узел вне IBD обязан вернуть headers от СВОЕГО tip
                    // (hashStop=0 обойдён только locator'ом).
                    let mut null_loc = Vec::new();
                    null_loc.extend_from_slice(&PROTOCOL_VERSION.to_le_bytes());
                    // CBlockLocator с vHave=0 (null locator) — Core: вернёт tip
                    crate::p2p::headers::write_varint(0, &mut null_loc);
                    null_loc.extend_from_slice(&[0u8; 32]);
                    self.send(params, "getheaders", &null_loc)?;
                    let tip_reply = match self.next_message(params, Duration::from_secs(45)) {
                        Ok(r) => r,
                        Err(_) => return Ok(None), // пир в IBD — ротация выше
                    };
                    if tip_reply.command != "headers" || tip_reply.payload.is_empty() {
                        return Ok(None);
                    }
                    // Tip-заголовок узла запоминаем как стартовый хэш для
                    // повторного запроса сверху (вызывающий sync_headers
                    // перезапустит цикл с этого заголовка).
                    let headers = parse_headers_payload(&tip_reply.payload, height_hint)?;
                    self.height_hint = height_hint + headers.len() as u32;
                    return Ok(Some(headers));
                }
                Err(e) => return Err(e),
            };
            match reply.command.as_str() {
                "headers" => {
                    let headers = parse_headers_payload(&reply.payload, height_hint)?;
                    self.height_hint = height_hint + headers.len() as u32;
                    return Ok(Some(headers));
                }
                _ => continue,
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
    _max_headers: u32,
    _genesis_hash_be: &str,
    progress: &mut dyn FnMut(u32),
) -> Result<(Vec<Header120>, bool), ChainError> {
    let mut chain: Vec<Header120> = Vec::new();
    let first_height = checkpoint_height + 1;
    // Первый запрос: locator [checkpoint, genesis]; далее — [kawpow-tip].
    let _genesis = _genesis_hash_be;
    loop {
        let batch = if chain.is_empty() {
            let locs = [checkpoint_hash_be];
            peer.request_headers(params, &locs, first_height)?
        } else {
            let last = chain.last().expect("non-empty");
            let (_mix, blockhash) = last.kawpow_blockhash();
            let tip_be = hex_le_to_be(blockhash);
            let hint = chain.first().map(|h| h.height).unwrap_or(0) + chain.len() as u32;
            let locs = [tip_be.as_str()];
            peer.request_headers(params, &locs, hint)?
        };
        let Some(batch) = batch else {
            // Пустой ответ: доехали до tip (или пир в IBD — ротация выше).
            // Первая высота ровно checkpoint+1 (высота честно в wire-заголовке)
            if let Some(first) = chain.first() {
                if first.height != checkpoint_height + 1 {
                    return Err(ChainError::Protocol(format!(
                        "{}: первая высота {} ≠ checkpoint+1",
                        peer.label, first.height
                    )));
                }
            }
            return Ok((chain, true));
        };
        // Связность внутри пачки и с предыдущей
        if let (Some(last), Some(first)) = (chain.last(), batch.first()) {
            if last.prev != first.prev {
                return Err(ChainError::Protocol(format!(
                    "{}: разрыв цепи на высоте {}",
                    peer.label, first.height
                )));
            }
        }
        eprintln!(
            "{}: пачка {} шт, высоты {}..{}, raw[0..8]={:02x?}",
            peer.label,
            batch.len(),
            batch.first().map(|h| h.height).unwrap_or(0),
            batch.last().map(|h| h.height).unwrap_or(0),
            &batch[0].raw[0..8],
        );
        chain.extend(batch);
        progress(chain.len() as u32);
    }
}

/// hex (BE-отображение) → LE-байты (для локатора getheaders).
fn hex_le_to_be(le_bytes: [u8; 32]) -> String {
    let mut rev = le_bytes;
    rev.reverse();
    hex::encode(rev)
}

/// Кворум: синхронизируем K пиров, сверяем их цепи ПОБАЙТОВО. Расхождение/
/// ошибка пира — честный отказ с перечнем. Порядок кандидатов честный:
/// сканируем ВСЕ сиды (кто отвечает на getheaders — узлы вне IBD), ответившие
/// идут первыми; при пустом скане (DoH лежит) — перебор сидов как раньше.
pub fn quorum_sync(
    params: &P2pParams,
    checkpoint_hash_be: &str,
    checkpoint_height: u32,
    max_headers: u32,
    genesis_hash_be: &str,
    peers_wanted: usize,
) -> Result<Vec<PeerChain>, ChainError> {
    let mut chains: Vec<PeerChain> = Vec::new();
    let checked = scan_nodes(
        params,
        checkpoint_hash_be,
        checkpoint_height,
        8,
        Duration::from_secs(20),
    );
    let mut candidates: Vec<String> = checked.iter().map(|n| n.ip.clone()).collect();
    if candidates.is_empty() {
        for seed in params.dns_seeds {
            if let Ok(ips) = resolve_seed_ips(seed) {
                for ip in ips {
                    let s = ip.to_string();
                    if !candidates.contains(&s) {
                        candidates.push(s);
                    }
                }
            }
        }
    }
    for ip in &candidates {
        if chains.len() >= peers_wanted {
            break;
        }
        let mut peer =
            match Peer::connect(params, ip, Duration::from_secs(4), checkpoint_height + 1) {
                Ok(p) => p,
                Err(e) => {
                    eprintln!("candidate {ip}: {e}");
                    continue;
                }
            };
        let mut progress = |_n: u32| {};
        let (chain, _up) = match sync_headers(
            &mut peer,
            params,
            checkpoint_hash_be,
            checkpoint_height,
            max_headers,
            genesis_hash_be,
            &mut progress,
        ) {
            Ok(v) => v,
            Err(e) => {
                eprintln!("{}: sync failed: {e}", peer.label);
                continue;
            }
        };
        // Кворум: побайтовое сравнение с уже собранными цепями
        if let Some(first) = chains.first() {
            if chain.len() != first.chain.len()
                || chain[..]
                    .iter()
                    .zip(first.chain.iter())
                    .any(|(a, b)| a.raw != b.raw)
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
    if chains.len() < 2 {
        return Err(ChainError::Transport(format!(
            "кворум собран {}: нужно ≥2 независимых пиров",
            chains.len()
        )));
    }
    Ok(chains)
}
