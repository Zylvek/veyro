//! Безопасная обёртка KAWPOW-хэша (единственное место с `unsafe` в VEYRO —
//! документированно: вендоренный C из MintPond/Ravencoin, см. `ffi/kawpow/`).
//!
//! Контракт C (`libhasherkawpow.cc`): `hash_one(header_hash, nonce*, height,
//! mix_out, hash_out)` — все буферы по 32 байта; `verify(...)->bool` —
//! проверка пары (хэш, mix). Внутри C — static epoch-context (light-cache):
//! генерация кэша эпохи занимает секунды один раз на эпоху (~30k блоков).
//!
//! Вектор — официальный из MintPond (lib.rs -sys 0.1.0): header_hash
//! `63543d39…`, nonce `88a23b0033eb959b`, height 262523 →
//! hash `0000000718ba5143286c46f44eee668fdf59b8eba810df21e4e2f4ec9538fc20`.

unsafe extern "C" {
    #[link_name = "hash_one"]
    fn c_hash_one(
        header_hash_bytes: *const u8,
        nonce64_ptr: *const u64,
        block_height: i32,
        mix_out_bytes: *mut u8,
        hash_out_bytes: *mut u8,
    ) -> ();

    #[link_name = "verify"]
    fn c_verify(
        header_hash_bytes: *const u8,
        nonce64_ptr: *const u64,
        block_height: i32,
        mix_out_bytes: *const u8,
        hash_out_bytes: *const u8,
    ) -> bool;
}

/// # Safety
///
/// Буферы передаются как *mut, но выделяются здесь как локальные массивы
/// фиксированной длины [0u8; 32]; C-функция пишет ровно 32 байта (контракт
/// MintPond). `block_height` < 0 отбрасывается до вызова C.
pub fn hash_pair(header_hash: &[u8; 32], nonce: u64, block_height: i32) -> ([u8; 32], [u8; 32]) {
    let mut mix = [0u8; 32];
    let mut hash = [0u8; 32];
    if block_height < 0 {
        return (mix, hash);
    }
    // SAFETY: см. док-блок функции; буферы локальные [u8;32], C пишет 32 байта.
    unsafe {
        c_hash_one(
            header_hash.as_ptr(),
            &nonce,
            block_height,
            mix.as_mut_ptr(),
            hash.as_mut_ptr(),
        );
    }
    (mix, hash)
}

/// # Safety
///
/// Те же гарантии, что у [hash_pair]; буферы только читаются (const).
pub fn verify(
    header_hash: &[u8; 32],
    nonce: u64,
    block_height: i32,
    mix_out: &[u8; 32],
    hash_out: &[u8; 32],
) -> bool {
    if block_height < 0 {
        return false;
    }
    // SAFETY: см. док-блок функции; буферы локальные [u8;32], C читает их.
    unsafe {
        c_verify(
            header_hash.as_ptr(),
            &nonce,
            block_height,
            mix_out.as_ptr(),
            hash_out.as_ptr(),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(s: &str) -> [u8; 32] {
        let mut out = [0u8; 32];
        for (i, b) in s.as_bytes().chunks(2).enumerate() {
            out[i] = u8::from_str_radix(std::str::from_utf8(b).expect("ascii"), 16).expect("hex");
        }
        out
    }

    /// Официальный вектор MintPond hasher-kawpow из -sys lib.rs.
    #[test]
    fn mintpond_vector_matches() {
        let hh = hex("63543d3913fe56e6720c5e61e8d208d05582875822628f483279a3e8d9c9a8b3");
        // крейт: hex_to_le_u64("88a23b0033eb959b"); в память через *const u64
        // уходит число 0x88a23b0033eb959b (LE-байты == BE-хекс порядок).
        let nonce = 0x88a23b0033eb959bu64;

        let (mix, hash) = hash_pair(&hh, nonce, 262523);
        assert_eq!(
            hash,
            hex("0000000718ba5143286c46f44eee668fdf59b8eba810df21e4e2f4ec9538fc20"),
            "kawpow hash vector mismatch"
        );
        assert!(
            verify(
                &hh,
                nonce,
                262523,
                &mix,
                &hex("0000000718ba5143286c46f44eee668fdf59b8eba810df21e4e2f4ec9538fc20")
            ),
            "kawpow verify vector mismatch"
        );
    }
}
