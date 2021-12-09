#!/bin/bash
set -euxo pipefail
IFS=$'\n\t'

# Set up tools to test the toolchain. (target-independent)

export CARGO_NET_RETRY=10
export RUSTUP_MAX_RETRIES=10

rust_toolchain_version=nightly-2021-12-08

# Install Rust.
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --profile minimal --default-toolchain "${rust_toolchain_version}" --component rust-src
# shellcheck disable=SC1091
. "${HOME}/.cargo/env"

# Download Rust dependencies.
# This allows subsequent tests to be run offline.
mkdir -p /tmp/deps/src
pushd /tmp/deps >/dev/null
touch src/lib.rs
tee >Cargo.toml <<EOF
[package]
name = "deps"
version = "0.0.0"
edition = "2021"
[dependencies]
cc = "1"
cmake = "0.1"
EOF
cargo fetch
rm Cargo.lock
# For build-std
# TODO: remove this once https://github.com/rust-lang/cargo/pull/10129 merged.
tee >Cargo.toml <<EOF
[package]
name = "deps"
version = "0.0.0"
edition = "2021"
[dependencies]
getopts = "=0.2.21"
hashbrown = "=0.11.0"
miniz_oxide = "=0.4.0"
memchr = "=2.4.1"
libc = "=0.2.108"
compiler_builtins = "=0.1.55"
addr2line = "=0.16.0"
unicode-width = "=0.1.8"
rustc-demangle = "=0.1.21"
object = "=0.26.2"
gimli = "=0.25.0"
cfg-if = "=0.1.10"
cc = "=1.0.69"
adler = "=0.2.3"
EOF
cargo fetch
popd >/dev/null
rm -rf /tmp/deps
