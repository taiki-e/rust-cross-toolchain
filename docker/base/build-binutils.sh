#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -eEuo pipefail
IFS=$'\n\t'

# shellcheck disable=SC2154
trap 's=$?; echo >&2 "$0: error on line "${LINENO}": ${BASH_COMMAND}"; exit ${s}' ERR

ldd_version=$(ldd --version 2>&1 || true)
if grep <<<"${ldd_version}" -q 'musl'; then
    export CC="gcc -static --static"
    export CXX="g++ -static --static"
    export LDFLAGS="-s -static --static"
fi

set -x

export CFLAGS="-g0 -O2 -fPIC ${CFLAGS:-}"
export CXXFLAGS="-g0 -O2 -fPIC ${CXXFLAGS:-}"

mkdir -p /tmp/binutils-build
cd /tmp/binutils-build
/tmp/binutils-src/configure \
    --prefix="${TOOLCHAIN_DIR}" \
    --target="${CC_TARGET}" \
    --with-sysroot="${SYSROOT_DIR}" \
    --with-debug-prefix-map="$(pwd)"= \
    --disable-nls \
    &>build.log || (tail <build.log -5000 && exit 1)
make -j"$(nproc)" &>build.log || (tail <build.log -5000 && exit 1)
make -p "${TOOLCHAIN_DIR}" &>build.log || (tail <build.log -5000 && exit 1)
make install &>build.log || (tail <build.log -5000 && exit 1)
