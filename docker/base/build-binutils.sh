#!/bin/bash
set -euxo pipefail
IFS=$'\n\t'

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
