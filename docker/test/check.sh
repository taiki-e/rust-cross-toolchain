#!/bin/bash
set -euxo pipefail
IFS=$'\n\t'

# Check the toolchain.
# This does not include building the source code and checking its output.

toolchain_dir="/${RUST_TARGET}"

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
set +x
if file "${toolchain_dir}/bin"/* | grep -E 'not stripped' >/dev/null; then
    echo >&2 "binaries must be stripped"
    exit 1
fi
case "${RUST_TARGET}" in
    *-linux-musl*)
        if file "${toolchain_dir}/bin"/* | grep -E 'dynamically linked' >/dev/null; then
            echo >&2 "binaries must be statically linked"
            exit 1
        fi
        ;;
esac
set -x

du -h "${toolchain_dir}"

find "${toolchain_dir}" -name "${RUST_TARGET}*" | LC_ALL=C sort
find "${toolchain_dir}" -name 'libstdc++*'
find "${toolchain_dir}" -name 'libc++*'

for cc in "${RUST_TARGET}-gcc" "${RUST_TARGET}-g++" "${RUST_TARGET}-clang" "${RUST_TARGET}-clang++" emcc; do
    if type -P "${cc}"; then
        "${cc}" --version
        file "$(type -P "${cc}")"
    fi
done
