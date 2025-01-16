#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -CeEuo pipefail
IFS=$'\n\t'
trap -- 's=$?; printf >&2 "%s\n" "${0##*/}:${LINENO}: \`${BASH_COMMAND}\` exit with ${s}"; exit ${s}' ERR

# Check the toolchain.
# This does not include building the source code and checking its output.

bail() {
  printf >&2 'error: %s\n' "$*"
  exit 1
}

set -x

toolchain_dir="/${RUST_TARGET}"

# In Ubuntu's binutils-* packages, ${toolchain}/${target}/bin/* are symlinks to ${toolchain}/bin/*.
if [[ -e "${toolchain_dir}/${RUST_TARGET}/bin" ]]; then
  pushd -- "${toolchain_dir}/${RUST_TARGET}/bin" >/dev/null
  set +x
  for path in "${toolchain_dir}/${RUST_TARGET}/bin"/*; do
    tool="${path##*/}"
    if [[ ! -L "${tool}" ]] && [[ -e ../../bin/"${RUST_TARGET}-${tool}" ]]; then
      ln -sf -- ../../bin/"${RUST_TARGET}-${tool}" "${tool}"
    fi
  done
  set -x
  popd >/dev/null
fi

# NB: Sync with base/common.sh
for bin_dir in "${toolchain_dir}/bin" "${toolchain_dir}/${RUST_TARGET}/bin"; do
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
          *-linux-musl* | *-solaris* | *-illumos*) bail "binaries must be statically linked" ;;
          *-freebsd* | *-openbsd*)
            case "${path}" in
              *clang | *clang++) ;; # symlink to host Clang
              *) bail "binaries must be statically linked" ;;
            esac
            ;;
        esac
        printf '%s' "${path}: "
        # https://stackoverflow.com/questions/3436008/how-to-determine-version-of-glibc-glibcxx-binary-will-depend-on
        objdump -T "${path}" | { grep -F GLIBC_ || :; } | sed -E 's/.*GLIBC_([.0-9]*).*/\1/g' | LC_ALL=C sort -Vu | { tail -1 || :; }
      fi
    done
    set -x
    file "${bin_dir}"/*
  fi
done

du -h "${toolchain_dir}"

find "${toolchain_dir}" -name "${RUST_TARGET}*" | LC_ALL=C sort
find "${toolchain_dir}" -name 'libstdc++*'
find "${toolchain_dir}" -name 'libc++*'
find "${toolchain_dir}" -name 'pkgconfig'

for cc in "${RUST_TARGET}-gcc" "${RUST_TARGET}-g++" "${RUST_TARGET}-gfortran" "${RUST_TARGET}-clang" "${RUST_TARGET}-clang++" emcc; do
  if type -P "${cc}"; then
    "${cc}" --version
  fi
done
if [[ -e "${toolchain_dir}/bin/${RUST_TARGET}-clang" ]] && [[ ! -x "${toolchain_dir}/bin/${RUST_TARGET}-clang" ]]; then
  tail -n +1 "${toolchain_dir}/bin/${RUST_TARGET}-clang" "${toolchain_dir}/bin/${RUST_TARGET}-clang++"
fi
