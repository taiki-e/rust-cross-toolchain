#!/bin/bash
set -euxo pipefail
IFS=$'\n\t'

# Set up tools to test the toolchain. (target-independent)

dpkg_arch="$(dpkg --print-architecture)"
case "${dpkg_arch##*-}" in
    amd64) ;;
    *)
        # TODO: don't skip if actual host is arm64
        echo >&2 "info: testing on hosts other than amd64 is currently being skipped: '${dpkg_arch}'"
        exit 0
        ;;
esac

export CARGO_NET_RETRY=10
export RUSTUP_MAX_RETRIES=10

rust_toolchain_version=nightly

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
# See:
# - docker/test/fixtures/rust/Cargo.toml
cat >Cargo.toml <<EOF
[package]
name = "deps"
version = "0.0.0"
edition = "2021"
[dependencies]
cc = "1"
cmake = "0.1"
EOF
case "${1:-}" in
    none)
        # See:
        # - docker/test/fixtures/arm-none/Cargo.toml
        # - docker/test/fixtures/cortex-m/Cargo.toml
        # - docker/test/fixtures/riscv-none/Cargo.toml
        cat >>Cargo.toml <<EOF
cortex-m = "0.7"
cortex-m-rt = "0.7"
cortex-m-semihosting = "0.3"
riscv-rt = "0.8"
[patch.crates-io]
riscv-rt = { git = "https://github.com/taiki-e/riscv-rt.git", rev = "7d2268105af466d2dd2f48ea5f51b593837d8a53" }
EOF
        ;;
esac
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
compiler_builtins = "=0.1.66"
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
