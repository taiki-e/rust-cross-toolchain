#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -CeEuo pipefail
IFS=$'\n\t'
trap -- 's=$?; printf >&2 "%s\n" "${0##*/}:${LINENO}: \`${BASH_COMMAND}\` exit with ${s}"; exit ${s}' ERR

bail() {
  printf '::error::%s\n' "$*"
  exit 1
}

set -x

# https://wiki.ubuntu.com/ReducingDiskFootprint#Documentation
find "${TOOLCHAIN_DIR:?}"/share/doc -depth -type f ! -name '*copyright*' ! -name '*Copyright*' ! -name '*COPYRIGHT*' -exec rm -- {} + || true
find "${TOOLCHAIN_DIR:?}"/share/doc -empty -exec rmdir -- {} + || true
rm -rf -- "${TOOLCHAIN_DIR:?}"/share/{groff,i18n,info,linda,lintian,locale,man}

case "${RUST_TARGET}" in
  csky-*) rm -f -- "${TOOLCHAIN_DIR:?}"/bin/qemu-{,system-}{arm,aarch64,riscv*} ;;
  *) rm -f -- "${TOOLCHAIN_DIR:?}"/bin/qemu-* ;;
esac

if [[ -f /CC_TARGET ]]; then
  if [[ -f /APT_TARGET ]]; then
    cc_target=$(</APT_TARGET)
  else
    cc_target=$(</CC_TARGET)
  fi
  # Some paths still use the target name that passed by --target even if we use
  # options such as --program-prefix. So use the target name for C by default,
  # and create symbolic links with Rust's target name for convenience.
  set +x
  while IFS= read -rd '' path; do
    pushd -- "$(dirname -- "${path}")" >/dev/null
    original="${path##*/}"
    link="${original/"${cc_target}"/"${RUST_TARGET}"}"
    [[ -e "${link}" ]] || ln -s -- "${original}" "${link}"
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
      if grep -Fq 'not stripped' <<<"${file_info}"; then
        strip "${path}"
      fi
      if grep -Fq 'dynamically linked' <<<"${file_info}"; then
        case "${RUST_TARGET}" in
          hexagon-unknown-linux-musl) ;;
          *-linux-musl* | *-solaris* | *-illumos*) bail "binaries must be statically linked: ${path}" ;;
          *-freebsd* | *-openbsd*)
            case "${path}" in
              *clang | *clang++) ;; # symlink to host Clang
              *) bail "binaries must be statically linked: ${path}" ;;
            esac
            ;;
        esac
        printf '%s' "${path}: "
        # https://stackoverflow.com/questions/3436008/how-to-determine-version-of-glibc-glibcxx-binary-will-depend-on
        objdump -T "${path}" | { grep -F GLIBC_ || true; } | sed -E 's/.*GLIBC_([.0-9]*).*/\1/g' | LC_ALL=C sort -Vu | { tail -1 || true; }
      fi
    done
    set -x
    file "${bin_dir}"/*
  fi
done
