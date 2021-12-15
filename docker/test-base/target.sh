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
esac
