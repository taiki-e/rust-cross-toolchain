#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -CeEuo pipefail
IFS=$'\n\t'
trap -- 's=$?; printf >&2 "%s\n" "${0##*/}:${LINENO}: \`${BASH_COMMAND}\` exit with ${s}"; exit ${s}' ERR

# Set up tools to test the toolchain. (target-independent)

set -x

dpkg_arch=$(dpkg --print-architecture)
case "${dpkg_arch##*-}" in
    amd64) ;;
    *)
        if [[ "${REAL_HOST_ARCH}" == "x86_64" ]]; then
            printf >&2 '%s\n' "info: testing on hosts other than amd64 is currently being skipped: '${dpkg_arch}'"
            exit 0
        fi
        ;;
esac

export CARGO_NET_RETRY=10
export RUSTUP_MAX_RETRIES=10

rust_toolchain_version=nightly

# Install Rust.
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused https://sh.rustup.rs \
    | sh -s -- -y --profile minimal --default-toolchain "${rust_toolchain_version}" --component rust-src --no-modify-path
