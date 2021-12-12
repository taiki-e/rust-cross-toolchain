#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Check the toolchain.
# This does not include building the source code and checking its output.

x() {
    local cmd="$1"
    shift
    (
        set -x
        "$cmd" "$@"
    )
}

toolchain_dir="/${RUST_TARGET}"

for bin_dir in "${toolchain_dir}/bin" "${toolchain_dir}/${RUST_TARGET}/bin"; do
    if [[ -d "${bin_dir}" ]]; then
        for path in "${bin_dir}"/*; do
            if file "${path}" | grep -E 'not stripped' >/dev/null; then
                x strip "${path}"
            fi
        done
        x file "${bin_dir}"/*
        case "${RUST_TARGET}" in
            hexagon-unknown-linux-musl) ;;
            *-linux-musl*)
                if file "${toolchain_dir}/bin"/* | grep -E 'dynamically linked' >/dev/null; then
                    echo >&2 "binaries must be statically linked"
                    exit 1
                fi
                ;;
        esac
    fi
done

x du -h "${toolchain_dir}"

x find "${toolchain_dir}" -name "${RUST_TARGET}*" | LC_ALL=C sort
x find "${toolchain_dir}" -name 'libstdc++*'
x find "${toolchain_dir}" -name 'libc++*'

for cc in "${RUST_TARGET}-gcc" "${RUST_TARGET}-g++" "${RUST_TARGET}-clang" "${RUST_TARGET}-clang++" emcc; do
    if type -P "${cc}"; then
        x "${cc}" --version
        x file "$(type -P "${cc}")"
    fi
done
if [[ -f "${toolchain_dir}/bin/${RUST_TARGET}-clang" ]]; then
    x tail -n +1 "${toolchain_dir}/bin/${RUST_TARGET}-clang" "${toolchain_dir}/bin/${RUST_TARGET}-clang++"
fi
