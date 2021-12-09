#!/bin/bash
set -euxo pipefail
IFS=$'\n\t'

# Check the toolchain.
# This does not include building the source code and checking its output.

toolchain_dir="/${RUST_TARGET}"
dev_tools_dir="/${RUST_TARGET}-dev"
mkdir -p "${dev_tools_dir}/bin"

set +x
for bin_dir in "${toolchain_dir}/bin" "${toolchain_dir}/${RUST_TARGET}/bin"; do
    if [[ -d "${bin_dir}" ]]; then
        for path in "${bin_dir}"/*; do
            if file "${path}" | grep -E 'not stripped' >/dev/null; then
                llvm-strip "${path}"
            fi
        done
    fi
done
set -x
file "${toolchain_dir}/bin"/*
if file "${toolchain_dir}/bin"/* | grep -E 'not stripped' >/dev/null; then
    echo >&2 "binaries must be stripped"
    exit 1
fi

case "${RUST_TARGET}" in
    *-musl*)
        if file "${toolchain_dir}/bin"/* | grep -E 'dynamically linked' >/dev/null; then
            echo >&2 "binaries must be statically linked"
            exit 1
        fi
        ;;
esac

du -h "${toolchain_dir}"

find "${toolchain_dir}" -name "${RUST_TARGET}*" | LC_ALL=C sort
find "${toolchain_dir}" -name 'libstdc++*'
find "${toolchain_dir}" -name 'libc++*'
for cc in gcc clang; do
    if type -P "${RUST_TARGET}-${cc}"; then
        "${RUST_TARGET}-${cc}" --version
        file "$(type -P "${RUST_TARGET}-${cc}")"
    fi
done
