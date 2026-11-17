//! Сборка вендоренного KAWPOW (источник: MintPond hasher-kawpow / Ravencoin,
//! скопировано из hasherkawpow-sys 0.1.0 — см. ffi/kawpow/README).
//!
//! CMake-билд -sys крейта на MSVC-профилях ненадёжен, поэтому собираем
//! напрямую компилятором через cc.

use std::path::PathBuf;

fn main() {
    let root = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("manifest dir"))
        .join("ffi")
        .join("kawpow");

    let mut build = cc::Build::new();
    build
        .include(&root)
        .include(root.join("include"))
        .include(root.join("ethash"))
        .include(root.join("compat"))
        .include(root.join("keccak"))
        .include(root.join("support"))
        .cpp(true)
        .cpp_set_stdlib(None);

    // C-часть (keccak)
    build
        .file(root.join("keccak/keccak.c"))
        .file(root.join("keccak/keccakf1600.c"))
        .file(root.join("keccak/keccakf800.c"))
        .file(root.join("ethash/primes.c"));
    if cfg!(target_os = "windows") {
        build.flag_if_supported("/std:c++14");
        build.flag_if_supported("/Zc:__cplusplus");
    } else {
        build.flag_if_supported("-std=c++14");
    }

    // C++ части
    build
        .file(root.join("ethash/ethash.cpp"))
        .file(root.join("ethash/managed.cpp"))
        .file(root.join("ethash/progpow.cpp"))
        .file(root.join("uint256.cpp"))
        .file(root.join("utilstrencodings.cpp"))
        .file(root.join("libhasherkawpow.cc"));

    build.compile("hasherkawpow_vendored");

    println!(
        "cargo:rerun-if-changed={}",
        root.join("libhasherkawpow.cc").display()
    );
    println!("cargo:rerun-if-changed={}", root.join("ethash").display());
    println!("cargo:rerun-if-changed={}", root.join("keccak").display());
}
