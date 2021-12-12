#!/bin/bash
set -euxo pipefail
IFS=$'\n\t'

# Set up tools to test the toolchain. (target-independent)

export CARGO_NET_RETRY=10
export RUSTUP_MAX_RETRIES=10

rust_toolchain_version=nightly-2021-12-09

# Install Rust.
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --profile minimal --default-toolchain "${rust_toolchain_version}" --component rust-src
# shellcheck disable=SC1091
. "${HOME}/.cargo/env"

# Download Rust dependencies.
# This allows subsequent tests to be run offline.
mkdir -p /tmp/deps/src
pushd /tmp/deps >/dev/null
touch src/lib.rs
cat >Cargo.toml <<EOF
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
cat >Cargo.toml <<EOF
[package]
name = "deps"
version = "0.0.0"
edition = "2021"
[dependencies]
addr2line = "=0.16.0"
adler = "=0.2.3"
cc = "=1.0.69"
cfg-if = "=0.1.10"
compiler_builtins = "=0.1.55"
getopts = "=0.2.21"
gimli = "=0.25.0"
hashbrown = "=0.11.0"
libc = "=0.2.108"
memchr = "=2.4.1"
miniz_oxide = "=0.4.0"
object = "=0.26.2"
rustc-demangle = "=0.1.21"
unicode-width = "=0.1.8"
EOF
cargo fetch
popd >/dev/null
rm -rf /tmp/deps
