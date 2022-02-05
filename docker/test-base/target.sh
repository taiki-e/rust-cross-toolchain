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

libc_version=0.2.116

if rustup target list | grep -E "^${RUST_TARGET}( |$)" >/dev/null; then
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
        # https://github.com/rust-lang/rust/blob/1d01550f7ea9fce1cf625128fefc73b9da3c1508/src/bootstrap/cc_detect.rs#L174
        # https://developer.android.com/ndk/guides/abis
        # https://github.com/rust-lang/rust/blob/5fa94f3c57e27a339bc73336cd260cd875026bd1/compiler/rustc_target/src/spec/arm_linux_androideabi.rs#L12
        touch /BUILD_STD
        ;;
esac

case "${RUST_TARGET}" in
    hexagon-unknown-linux-musl | riscv64gc-unknown-linux-musl | powerpc-unknown-openbsd)
        pushd "${HOME}"/.cargo/registry/src/github.com-*/libc-"${libc_version}" >/dev/null
        # hexagon-unknown-linux-musl:
        #   "error[E0425]: cannot find value `SYS_clone3` in this scope" when building std
        #   TODO: send patch to upstream
        # riscv64gc-unknown-linux-musl:
        #   "error[E0425]: cannot find value `SYS_clone3` in this scope" when building std
        #   TODO: send patch to upstream
        # powerpc-unknown-openbsd:
        #   TODO: remove this once https://github.com/rust-lang/rust/pull/92061 merged.
        patch -p1 </test-base/patches/"${RUST_TARGET}"-libc.diff
        popd >/dev/null
        ;;
    aarch64-unknown-freebsd)
        pushd "$(rustc --print sysroot)"/lib/rustlib/src/rust/library/stdarch/crates/std_detect >/dev/null
        # error: cannot find macro `asm` in this scope
        # https://github.com/taiki-e/rust-cross-toolchain/runs/4555834110?check_suite_focus=true
        # TODO: send patch to upstream
        patch -p1 </test-base/patches/"${RUST_TARGET}"-std_detect.diff
        popd >/dev/null
        ;;
esac
