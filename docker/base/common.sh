#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

x() {
    local cmd="$1"
    shift
    (
        set -x
        "$cmd" "$@"
    )
}

x rm -rf "${TOOLCHAIN_DIR}"/share/{doc,lintian,locale,man}

if [[ -f /CC_TARGET ]]; then
    # Some paths still use the target name that passed by --target even if we use
    # options such as --program-prefix. So use the target name for C by default,
    # and create symbolic links with Rust's target name for convenience.
    cc_target="$(</CC_TARGET)"
    while IFS= read -r -d '' path; do
        pushd "$(dirname "${path}")" >/dev/null
        original="$(basename "${path}")"
        link="${original/"${cc_target}"/"${RUST_TARGET}"}"
        [[ -e "${link}" ]] || ln -s "${original}" "${link}"
        popd >/dev/null
    done < <(find "${TOOLCHAIN_DIR}" -name "${cc_target}*" -print0)
fi

for bin_dir in "${TOOLCHAIN_DIR}/bin" "${TOOLCHAIN_DIR}/${RUST_TARGET}/bin"; do
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
                if file "${bin_dir}"/* | grep -E 'dynamically linked' >/dev/null; then
                    echo >&2 "binaries must be statically linked"
                    exit 1
                fi
                ;;
        esac
    fi
done
