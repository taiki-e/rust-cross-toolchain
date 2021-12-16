#!/bin/bash
set -euxo pipefail
IFS=$'\n\t'

# Set up tools to test the toolchain. (target-dependent)

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
# shellcheck disable=SC1091
. "${HOME}/.cargo/env"

case "${RUST_TARGET}" in
    # TODO: remove once https://github.com/rust-lang/libc/pull/2594 and
    # https://github.com/rust-lang/rust/pull/91955 merged and released.
    x86_64-unknown-dragonfly)
        rust_toolchain_version=nightly-2021-12-09
        rustup toolchain add "${rust_toolchain_version}" --no-self-update --component rust-src
        rustup default "${rust_toolchain_version}"
        mkdir -p /tmp/deps/src
        pushd /tmp/deps >/dev/null
        touch src/lib.rs
        cat >Cargo.toml <<EOF
[package]
name = "deps"
version = "0.0.0"
edition = "2021"
[dependencies]
compiler_builtins = "=0.1.55"
EOF
        cargo fetch
        popd >/dev/null
        rm -rf /tmp/deps
        ;;
esac

if rustup target list | grep -E "^${RUST_TARGET}( |$)" >/dev/null; then
    rustup target add "${RUST_TARGET}"
else
    touch /BUILD_STD
fi

libc_version=0.2.108
case "${RUST_TARGET}" in
    hexagon-unknown-linux-musl)
        pushd "${HOME}"/.cargo/registry/src/github.com-*/libc-"${libc_version}" >/dev/null
        # "error[E0425]: cannot find value `SYS_clone3` in this scope" when building std
        # TODO: send patch to upstream
        patch -p1 </test-base/patches/hexagon-unknown-linux-musl-libc.diff
        popd >/dev/null
        ;;
    riscv64gc-unknown-linux-musl)
        pushd "${HOME}"/.cargo/registry/src/github.com-*/libc-"${libc_version}" >/dev/null
        # "error[E0425]: cannot find value `SYS_clone3` in this scope" when building std
        # TODO: send patch to upstream
        patch -p1 </test-base/patches/riscv64gc-unknown-linux-musl-libc.diff
        popd >/dev/null
        ;;
    arm-linux-androideabi)
        # The pre-compiled library distributed by rustup targets armv7a because
        # it uses the default arm-linux-androideabi-clang.
        # To target armv5te, which is the minimum supported architecture of
        # arm-linux-androideabi, the standard library needs to be recompiled.
        # https://android.googlesource.com/platform/ndk/+/refs/heads/ndk-r15-release/docs/user/standalone_toolchain.md#abi-compatibility
        # https://github.com/rust-lang/rust/blob/1d01550f7ea9fce1cf625128fefc73b9da3c1508/src/bootstrap/cc_detect.rs#L174
        # https://developer.android.com/ndk/guides/abis
        # https://github.com/rust-lang/rust/blob/5fa94f3c57e27a339bc73336cd260cd875026bd1/compiler/rustc_target/src/spec/arm_linux_androideabi.rs#L12
        touch /BUILD_STD
        ;;
esac
