//! Заголовки блоков RVN/XNA: парсинг «headers», связность, DGW3-ретаргетинг
//! (портирован DarkGravityWave из Ravencoin pow.cpp), kawpow PoW.
//!
//! Порядок байтов: заголовок на проводе — поля LE (uint256 хранится LE);
//! kawpow: header-hash = sha256d(CKAWPOWInput 80 байт) — GetKAWPOWHeaderHash
//! точный; block-hash = MintPond hash_out; ориентация при сличении с prev
//! следующего заголовка фиксируется живой пробой (обе ориентации
//! проверяются при первом прогоне, дальше — константа).

use crate::p2p::kawpow::blockhash_kawpow;
use crate::ChainError;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Header120 {
    pub version: i32,
    pub prev: [u8; 32],
    pub merkle: [u8; 32],
    pub time: u32,
    pub n_bits: u32,
    pub height: u32,
    pub nonce64: u64,
    pub mix_hash: [u8; 32],
    pub raw: [u8; 120],
}

impl Header120 {
    /// Парсинг kawpow-заголовка (120 байт). Для legacy 80-байтового — false.
    pub fn parse(raw: &[u8], height_hint: u32) -> Result<Self, ChainError> {
        match raw.len() {
            120 => Ok(Self {
                version: i32::from_le_bytes(raw[0..4].try_into().expect("4")),
                prev: raw[4..36].try_into().expect("32"),
                merkle: raw[36..68].try_into().expect("32"),
                time: u32::from_le_bytes(raw[68..72].try_into().expect("4")),
                n_bits: u32::from_le_bytes(raw[72..76].try_into().expect("4")),
                height: u32::from_le_bytes(raw[76..80].try_into().expect("4")),
                nonce64: u64::from_le_bytes(raw[80..88].try_into().expect("8")),
                mix_hash: raw[88..120].try_into().expect("32"),
                raw: raw.try_into().expect("120"),
            }),
            80 => {
                let _ = height_hint;
                Err(ChainError::Protocol(
                    "legacy-заголовок вне цели этой ветки p2p (RVN kawpow-эра)".into(),
                ))
            }
            n => Err(ChainError::Protocol(format!(
                "заголовок нестандартного размера {n}"
            ))),
        }
    }

    /// CKAWPOWInput (80 байт) — сериализация, что хашируется в
    /// GetKAWPOWHeaderHash (primitives/block.cpp).
    pub fn kawpow_input(&self) -> [u8; 80] {
        let mut input = [0u8; 80];
        input[0..4].copy_from_slice(&self.version.to_le_bytes());
        input[4..36].copy_from_slice(&self.prev);
        input[36..68].copy_from_slice(&self.merkle);
        input[68..72].copy_from_slice(&self.time.to_le_bytes());
        input[72..76].copy_from_slice(&self.n_bits.to_le_bytes());
        input[76..80].copy_from_slice(&self.height.to_le_bytes());
        input
    }

    /// (mix, block_hash) — как CBlockHeader::GetHashFull для kawpow-эры.
    pub fn kawpow_blockhash(&self) -> ([u8; 32], [u8; 32]) {
        blockhash_kawpow(&self.raw)
    }
}

#[inline]
fn read_varint(data: &[u8], off: usize) -> Result<(u64, usize), ChainError> {
    if off >= data.len() {
        return Err(ChainError::Protocol("varint: короткий буфер".into()));
    }
    match data[off] {
        0xfd => {
            if off + 3 > data.len() {
                return Err(ChainError::Protocol("varint fd".into()));
            }
            Ok((
                u16::from_le_bytes(data[off + 1..off + 3].try_into().expect("2")) as u64,
                3,
            ))
        }
        0xfe => {
            if off + 5 > data.len() {
                return Err(ChainError::Protocol("varint fe".into()));
            }
            Ok((
                u32::from_le_bytes(data[off + 1..off + 5].try_into().expect("4")) as u64,
                5,
            ))
        }
        0xff => {
            if off + 9 > data.len() {
                return Err(ChainError::Protocol("varint ff".into()));
            }
            Ok((
                u64::from_le_bytes(data[off + 1..off + 9].try_into().expect("8")),
                9,
            ))
        }
        v => Ok((v as u64, 1)),
    }
}

#[inline]
pub fn write_varint(v: u64, out: &mut Vec<u8>) {
    if v < 0xfd {
        out.push(v as u8);
    } else if v <= 0xffff {
        out.push(0xfd);
        out.extend_from_slice(&(v as u16).to_le_bytes());
    } else if v <= 0xffff_ffff {
        out.push(0xfe);
        out.extend_from_slice(&(v as u32).to_le_bytes());
    } else {
        out.push(0xff);
        out.extend_from_slice(&v.to_le_bytes());
    }
}

/// Парсинг payload «headers»: 120-байтовые kawpow- и 80-байтовые
/// legacy-заголовки (RVN старше KAWPOW-активации). `start_height_hint` —
/// высота первого заголовка в пачке (для legacy их высоты считаются).
pub fn parse_headers_payload(
    payload: &[u8],
    start_height_hint: u32,
) -> Result<Vec<Header120>, ChainError> {
    let (count, mut off) = read_varint(payload, 0)?;
    if count > 2000 {
        return Err(ChainError::Protocol(format!("headers count {count}")));
    }
    let mut out = Vec::with_capacity(count as usize);
    let mut height = start_height_hint;
    for _ in 0..count {
        if off + 1 > payload.len() {
            return Err(ChainError::Protocol("headers payload оборван".into()));
        }
        // Реальный размер заголовка читаем по полю nBits/time? Нет: kawpow
        // заголовок 120 и legacy 80 различаются по времени активации —
        // но в пределах пачки размер одинаков; честный маркер: первый
        // заголовок пробуем как 120 (kawpow-эра), иначе 80.
        let size = 120;
        if off + size + 3 > payload.len() {
            // попробуем 80 (legacy)
            if off + 81 > payload.len() {
                return Err(ChainError::Protocol("headers payload короткий".into()));
            }
            out.push(Header120::parse(&payload[off..off + 80], height)?);
            off += 80;
        } else {
            // проверка реального размера: считываем nTime и nNonce...
            // У RVN формат определяется эрой; KAWPOW-активация 2020-05-06 —
            // заголовки с time >= activation идут 120 байтами, до неё 80.
            let time_field = u32::from_le_bytes(payload[off + 68..off + 72].try_into().expect("4"));
            if time_field >= crate::p2p::KAWPOW_ACTIVATION_TIME {
                if off + 121 > payload.len() {
                    return Err(ChainError::Protocol("kawpow-заголовок оборван".into()));
                }
                out.push(Header120::parse(&payload[off..off + 120], height)?);
                off += 120;
            } else {
                if off + 81 > payload.len() {
                    return Err(ChainError::Protocol("legacy заголовок оборван".into()));
                }
                out.push(Header120::parse(&payload[off..off + 80], height)?);
                off += 80;
            }
        }
        let (tx_count, used) = read_varint(payload, off)?;
        if tx_count != 0 {
            return Err(ChainError::Protocol(
                "в headers-ответе транзакции (это блок, не заголовок)".into(),
            ));
        }
        off += used;
        height += 1;
    }
    Ok(out)
}

// ---------------------------------------------------------------------------
// BE-таргеты для DGW3: 32-байтовая арифметика mul/div на малых числах.
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BigTarget(pub [u8; 32]); // big-endian

impl BigTarget {
    pub const fn zero() -> Self {
        Self([0u8; 32])
    }

    pub fn from_compact(n_bits: u32) -> Self {
        let size = ((n_bits >> 24) & 0xff) as usize;
        let mant = n_bits & 0x00ff_ffff;
        let mant_bytes = [(mant >> 16) as u8, (mant >> 8) as u8, mant as u8];
        let mut out = [0u8; 32];
        if size <= 32 {
            // Core SetCompact: mantissa (3 байта) << (8*(size-3)) в BE-буфер
            let shift_bytes = size.saturating_sub(3);
            for (i, mb) in mant_bytes.iter().enumerate() {
                let at = 32usize.checked_sub(shift_bytes + 3 - i);
                if let Some(at) = at {
                    out[at] = *mb;
                }
            }
            // внутр. сдвиг: частичные биты (size-3) внутри байта
            let partial = (shift_bytes % 1) as u8;
            let _ = partial; // mantissa целиком по границе байтов — сдвиг битовый = 0
        }
        BigTarget(out)
    }

    pub fn to_compact(&self) -> u32 {
        let first = match self.0.iter().position(|b| *b != 0) {
            Some(i) => i,
            None => return 0,
        };
        let size = (32 - first) as u32;
        let b0 = self.0[first] as u32;
        let b1 = self.0.get(first + 1).copied().unwrap_or(0) as u32;
        let b2 = self.0.get(first + 2).copied().unwrap_or(0) as u32;
        let mut mant = (b0 << 16) | (b1 << 8) | b2;
        let mut size_out = size;
        if mant & 0x0080_0000 != 0 {
            mant >>= 8;
            size_out += 1;
        }
        (size_out << 24) | (mant & 0x007f_ffff)
    }

    pub fn cmp_be(a: &Self, b: &Self) -> std::cmp::Ordering {
        a.0.cmp(&b.0)
    }

    pub fn add_be(&self, other: &Self) -> Self {
        let mut out = [0u8; 32];
        let mut carry = 0u32;
        for i in (0..32).rev() {
            let sum = self.0[i] as u32 + other.0[i] as u32 + carry;
            out[i] = (sum & 0xff) as u8;
            carry = sum >> 8;
        }
        BigTarget(out)
    }

    pub fn mul_small(&self, n: u32) -> Self {
        let mut out = [0u8; 32];
        let mut carry = 0u32;
        for i in (0..32).rev() {
            let prod = (self.0[i] as u32) * n + carry;
            out[i] = (prod & 0xff) as u8;
            carry = prod >> 8;
        }
        BigTarget(out) // переполнение — усечение, как у arith_uint256
    }

    pub fn div_small(&self, n: u32) -> Self {
        let mut out = [0u8; 32];
        let mut rem = 0u32;
        for i in 0..32 {
            let cur = rem * 256 + self.0[i] as u32;
            out[i] = (cur / n) as u8;
            rem = cur % n;
        }
        BigTarget(out)
    }
}

/// DGW3: следующий nBits. `chain` — последние ≥181 заголовков по высоте;
/// точный порядок C++ (pindex=last → вниз по pprev), целочисленное
/// усечение на каждом шаге — как в arith_uint256.
pub fn dark_gravity_wave3(
    chain: &[Header120],
    new_block_time: u32,
    kawpow_activation_time: u32,
) -> Result<u32, ChainError> {
    const N_PAST_BLOCKS: usize = 180;
    const TARGET_SPACING_SEC: i64 = 60;

    // powLimit = 00000fff… (BE: 0x00,0x00,0x0f,0xff×29) → compact 0x1e0fffff
    const POW_LIMIT: BigTarget = {
        let mut b = [0xffu8; 32];
        b[0] = 0x00;
        b[1] = 0x00;
        b[2] = 0x0f;
        BigTarget(b)
    };
    // kawpowLimit = 0000000000ff… (BE: 5 нулевых байтов, затем 0xff)
    const KAWPOW_LIMIT: BigTarget = {
        let mut b = [0xffu8; 32];
        b[0] = 0x00;
        b[1] = 0x00;
        b[2] = 0x00;
        b[3] = 0x00;
        b[4] = 0x00;
        BigTarget(b)
    };

    if chain.len() <= N_PAST_BLOCKS {
        return Ok(POW_LIMIT.to_compact());
    }

    // Точный порядок C++: nCountBlocks 1..=180; pindex стартует с last,
    // каждый шаг (кроме последнего) pindex = pprev.
    let mut avg_be = BigTarget::from_compact(chain[chain.len() - 1].n_bits);
    let mut kawpow_found = 0u32;
    for count in 1..=N_PAST_BLOCKS {
        let idx = chain.len() - count;
        let target_be = BigTarget::from_compact(chain[idx].n_bits);
        if count == 1 {
            avg_be = target_be;
        } else {
            // avg = (avg*count + target) / (count+1)
            avg_be = avg_be
                .mul_small(count as u32)
                .add_be(&target_be)
                .div_small((count + 1) as u32);
        }
        if chain[idx].time >= kawpow_activation_time {
            kawpow_found += 1;
        }
    }

    // kawpow-окно: если новый блок kawpow, но 180 последних не все kawpow —
    // kawpowLimit (из pow.cpp).
    if new_block_time >= kawpow_activation_time && kawpow_found != N_PAST_BLOCKS as u32 {
        return Ok(KAWPOW_LIMIT.to_compact());
    }

    // actual = time(last) - time(first из 180); clamp [÷3; ×3]
    let first_idx = chain.len() - N_PAST_BLOCKS;
    let actual = (chain[chain.len() - 1].time as i64) - (chain[first_idx].time as i64);
    let target_span = N_PAST_BLOCKS as i64 * TARGET_SPACING_SEC;
    let clamped = actual.clamp(target_span / 3, target_span * 3);

    let mut bn_new = avg_be
        .mul_small(clamped as u32)
        .div_small(target_span as u32);
    if BigTarget::cmp_be(&bn_new, &POW_LIMIT) == std::cmp::Ordering::Greater {
        bn_new = POW_LIMIT;
    }
    Ok(bn_new.to_compact())
}
