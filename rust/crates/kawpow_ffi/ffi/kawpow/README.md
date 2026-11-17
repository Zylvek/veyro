# Вендоренный KAWPOW C/C++

Источники: MintPond `hasher-kawpow` через крейт `hasherkawpow-sys` 0.1.0
(vpalmerio; MIT), который адаптирует код Ravencoin (Bitcoin ABC ethash/progpow,
Apache-2.0 — ethash.cpp/progpow.cpp/managed.cpp by Pawel Bylica et al., MIT —
libhasherkawpow.cc/uint256*) и keccak (CC0/public-domain keccak Team).

Скопировано как есть (v0.1.0, 2025-09) для честных PoW-проверок заголовков
RVN/XNA без CMake-зависимости: сборка через `chains/build.rs` (cc-крейт).

Точка входа: extern "C" hash_one(header_hash, nonce*, height, mix_out, hash_out)
и verify(...); обёртка: chains/src/p2p/kawpow.rs (тест — официальные векторы
 MintPond из lib.rs -sys-крейта).
