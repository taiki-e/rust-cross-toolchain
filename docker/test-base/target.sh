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

if rustup target list | grep -Eq "^${RUST_TARGET}( |$)"; then
    rustup target add "${RUST_TARGET}"
else
    touch /BUILD_STD
fi
case "${RUST_TARGET}" in
    arm-linux-androideabi)
        # The pre-compiled library distributed by rustup targets armv7a because
        # it uses the default arm-linux-androideabi-clang.
        # To target armv5te, which is the minimum supported architecture of
        # arm-linux-androideabi, the standard library needs to be recompiled.
        # https://android.googlesource.com/platform/ndk/+/refs/heads/ndk-r15-release/docs/user/standalone_toolchain.md#abi-compatibility
        # https://github.com/rust-lang/rust/blob/1.61.0/src/bootstrap/cc_detect.rs#L174
        # https://developer.android.com/ndk/guides/abis
        # https://github.com/rust-lang/rust/blob/1.61.0/compiler/rustc_target/src/spec/arm_linux_androideabi.rs#L11-L12
        touch /BUILD_STD
        ;;
esac
