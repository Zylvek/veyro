//! KAWPOW-хэш через `kawpow_ffi` (весь `unsafe` живёт ТОЛЬКО там —
//! `crates/kawpow_ffi`, документированно; вендор C: `ffi/kawpow`).
//!
//! Вектор MintPond проверен в тестах -ffi-крейта; здесь — тонкий re-export
//! + семантика проверки заголовка RVN/XNA (порядок байтов подтверждается
//! ЖИВОЙ пробой в p2p::headers — без выдумок).

pub use kawpow_ffi::{hash_pair, verify};

/// Точно как `CBlockHeader::GetKAWPOWHeaderHash` (primitives/block.cpp):
/// `SerializeHash(CKAWPOWInput)` — double-SHA256 сериализации
/// (nVersion i32, hashPrevBlock 32, hashMerkleRoot 32, nTime u32, nBits u32,
/// nHeight u32) = 80 байт. Затем блок-хэш = kawpow(header_hash, nonce64, height)
/// (KAWPOWHash_OnlyMix). Полный заголовок kawpow-эры: 120 байт
/// (…nBits u32 | nHeight u32 | nNonce64 u64 | mix_hash 32).
pub fn blockhash_kawpow(header120: &[u8]) -> ([u8; 32], [u8; 32]) {
    if header120.len() != 120 {
        return ([0u8; 32], [0u8; 32]);
    }
    let mut input = [0u8; 80];
    input[..80].copy_from_slice(&header120[..80]);
    let header_hash = crate::sha256d(&input);
    let nonce = u64::from_le_bytes(header120[76..84].try_into().expect("8 bytes"));
    hash_pair(
        &header_hash,
        nonce,
        i32::from_le_bytes(header120[72..76].try_into().expect("4")),
    )
}
