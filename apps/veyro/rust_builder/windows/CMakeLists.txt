# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "veyro_bridge")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
# CARGOKIT_MANIFEST_DIR is resolved from CMAKE_CURRENT_SOURCE_DIR (see
# cargokit.cmake), which on Windows is the symlink path Flutter uses for
# plugins: <app>/windows/flutter/ephemeral/.plugin_symlinks/veyro_bridge/windows.
# 8 levels up from there reaches the repo root, where the VEYRO Rust
# workspace lives (the crate itself is rust/crates/veyro_bridge).
apply_cargokit(${PROJECT_NAME} ../../../../../../../../rust/crates/veyro_bridge veyro_bridge "")

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(veyro_bridge_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
