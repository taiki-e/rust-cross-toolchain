#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -eEuo pipefail
IFS=$'\n\t'

# shellcheck disable=SC2154
trap 's=$?; echo >&2 "$0: error on line "${LINENO}": ${BASH_COMMAND}"; exit ${s}' ERR

# Set up tools to test the toolchain. (target-dependent)

set -x

bail() {
    set +x
    echo >&2 "error: ${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}: $*"
    exit 1
}

dpkg_arch=$(dpkg --print-architecture)
case "${dpkg_arch##*-}" in
    amd64) ;;
    *)
        if [[ "${REAL_HOST_ARCH}" == "x86_64" ]]; then
            echo >&2 "info: testing on hosts other than amd64 is currently being skipped: '${dpkg_arch}'"
            exit 0
        fi
        ;;
esac

export CARGO_NET_RETRY=10
export RUSTUP_MAX_RETRIES=10
# shellcheck disable=SC1091
. "${HOME}/.cargo/env"

if rustup target list | cut -d' ' -f1 | grep -Eq "^${RUST_TARGET}$"; then
    rustup target add "${RUST_TARGET}"
else
    touch /BUILD_STD
fi

# https://github.com/rust-lang/rust/blob/HEAD/library/Cargo.lock
libc_version=0.2.158
compiler_builtins_version=0.1.123
sysroot=$(rustc --print sysroot)
for patch in /test-base/patches/*.diff; do
    set +x
    t=$(basename "${patch}")
    t="${t%.diff}"
    target="${t#*+}"
    lib="${t%+*}"
    if [[ "${RUST_TARGET}" != "${target}" ]]; then
        continue
    fi
    set -x

    if [[ -d "${sysroot}/lib/rustlib/src/rust/library/${lib}" ]]; then
        pushd "${sysroot}/lib/rustlib/src/rust/library/${lib}"
    elif [[ -d "${sysroot}/lib/rustlib/src/rust/library/stdarch/crates/${lib}" ]]; then
        pushd "${sysroot}/lib/rustlib/src/rust/library/stdarch/crates/${lib}"
    else
        rm -rf /tmp/fetch
        mkdir -p /tmp/fetch/src
        pushd /tmp/fetch >/dev/null
        touch src/lib.rs
        cat >Cargo.toml <<EOF
[package]
name = "fetch-deps"
edition = "2021"
EOF
        cargo fetch -Z build-std --target "${RUST_TARGET}"
        popd >/dev/null
        case "${lib}" in
            libc) lib_version="${libc_version}" ;;
            compiler_builtins) lib_version="${compiler_builtins_version}" ;;
            *) bail "unrecognized lib '${lib}'" ;;
        esac
        pushd "${HOME}"/.cargo/registry/src/index.crates.io-*/"${lib}-${lib_version}" >/dev/null
    fi
    patch -p1 <"${patch}"
    popd >/dev/null
done
