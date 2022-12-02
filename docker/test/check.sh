#!/bin/bash
set -euxo pipefail
IFS=$'\n\t'

# Check the toolchain.
# This does not include building the source code and checking its output.

toolchain_dir="/${RUST_TARGET}"

# In Ubuntu's binutils-* packages, ${toolchain}/${target}/bin/* are symlinks to ${toolchain}/bin/*.
if [[ -e "${toolchain_dir}/${RUST_TARGET}/bin" ]]; then
    pushd "${toolchain_dir}/${RUST_TARGET}/bin" >/dev/null
    set +x
    for path in "${toolchain_dir}/${RUST_TARGET}/bin"/*; do
        tool="$(basename "${path}")"
        if [[ ! -L "${tool}" ]] && [[ -e ../../bin/"${RUST_TARGET}-${tool}" ]]; then
            ln -sf ../../bin/"${RUST_TARGET}-${tool}" "${tool}"
        fi
    done
    set -x
    popd >/dev/null
fi

for bin_dir in "${toolchain_dir}/bin" "${toolchain_dir}/${RUST_TARGET}/bin"; do
    if [[ -e "${bin_dir}" ]]; then
        set +x
        for path in "${bin_dir}"/*; do
            if file "${path}" | grep -Eq 'not stripped'; then
                strip "${path}"
            fi
        done
        set -x
        file "${bin_dir}"/*
        case "${RUST_TARGET}" in
            hexagon-unknown-linux-musl) ;;
            *-linux-musl*)
                if file "${toolchain_dir}/bin"/* | grep -Eq 'dynamically linked'; then
                    echo >&2 "binaries must be statically linked"
                    exit 1
                fi
                ;;
        esac
    fi
done

du -h "${toolchain_dir}"

find "${toolchain_dir}" -name "${RUST_TARGET}*" | LC_ALL=C sort
find "${toolchain_dir}" -name 'libstdc++*'
find "${toolchain_dir}" -name 'libc++*'
find "${toolchain_dir}" -name 'pkgconfig'

for cc in "${RUST_TARGET}-gcc" "${RUST_TARGET}-g++" "${RUST_TARGET}-gdb" "${RUST_TARGET}-clang" "${RUST_TARGET}-clang++" emcc; do
    if type -P "${cc}"; then
        "${cc}" --version
    fi
done
if [[ -e "${toolchain_dir}/bin/${RUST_TARGET}-clang" ]]; then
    tail -n +1 "${toolchain_dir}/bin/${RUST_TARGET}-clang" "${toolchain_dir}/bin/${RUST_TARGET}-clang++"
fi
