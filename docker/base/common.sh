#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -euo pipefail
IFS=$'\n\t'

# shellcheck disable=SC2154
trap 's=$?; echo >&2 "$0: error on line "${LINENO}": ${BASH_COMMAND}"; exit ${s}' ERR

set -x

rm -rf "${TOOLCHAIN_DIR:?}"/share/{doc,i18n,lintian,locale,man}

if [[ -f /CC_TARGET ]]; then
    if [[ -f /APT_TARGET ]]; then
        cc_target="$(</APT_TARGET)"
    else
        cc_target="$(</CC_TARGET)"
    fi
    # Some paths still use the target name that passed by --target even if we use
    # options such as --program-prefix. So use the target name for C by default,
    # and create symbolic links with Rust's target name for convenience.
    set +x
    while IFS= read -r -d '' path; do
        pushd "$(dirname "${path}")" >/dev/null
        original="$(basename "${path}")"
        link="${original/"${cc_target}"/"${RUST_TARGET}"}"
        [[ -e "${link}" ]] || ln -s "${original}" "${link}"
        popd >/dev/null
    done < <(find "${TOOLCHAIN_DIR}" -name "${cc_target}*" -print0)
    set -x
fi

# NB: Sync with test/check.sh
for bin_dir in "${TOOLCHAIN_DIR}/bin" "${TOOLCHAIN_DIR}/${RUST_TARGET}/bin"; do
    if [[ -e "${bin_dir}" ]]; then
        set +x
        for path in "${bin_dir}"/*; do
            file_info=$(file "${path}")
            if grep <<<"${file_info}" -Eq 'not stripped'; then
                strip "${path}"
            fi
            if grep <<<"${file_info}" -Eq 'dynamically linked'; then
                case "${RUST_TARGET}" in
                    hexagon-unknown-linux-musl) ;;
                    *-linux-musl* | *-solaris* | *-illumos*)
                        echo >&2 "binaries must be statically linked"
                        exit 1
                        ;;
                    *-freebsd* | *-openbsd*)
                        case "${path}" in
                            *clang | *clang++) ;; # symlink to host clang
                            *)
                                echo >&2 "binaries must be statically linked"
                                exit 1
                                ;;
                        esac
                        ;;
                esac
                echo -n "${path}: "
                # https://stackoverflow.com/questions/3436008/how-to-determine-version-of-glibc-glibcxx-binary-will-depend-on
                objdump -T "${path}" | grep GLIBC_ | sed 's/.*GLIBC_\([.0-9]*\).*/\1/g' | sort -Vu | tail -1
            fi
        done
        set -x
        file "${bin_dir}"/*
    fi
done
