# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

# Refs:
# - https://github.com/rust-lang/rust/blob/1.80.0/src/ci/docker/host-x86_64/dist-various-2/build-solaris-toolchain.sh

ARG UBUNTU_VERSION=20.04

ARG SOLARIS_VERSION=2.10
# https://ftp.gnu.org/gnu/binutils
ARG BINUTILS_VERSION=2.33.1
# https://ftp.gnu.org/gnu/gcc
ARG GCC_VERSION=8.5.0

FROM ghcr.io/taiki-e/downloader AS binutils-src
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG BINUTILS_VERSION
RUN mkdir -p -- /binutils-src
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.gz" \
        | tar xzf - --strip-components 1 -C /binutils-src
FROM ghcr.io/taiki-e/downloader AS gcc-src
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG GCC_VERSION
RUN mkdir -p -- /gcc-src
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.gz" \
        | tar xzf - --strip-components 1 -C /gcc-src

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS sysroot
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
RUN mkdir -p -- /tmp/sysroot
WORKDIR /tmp/sysroot
RUN <<EOF
case "${RUST_TARGET}" in
    x86_64*) dpkg_arch=solaris-i386 ;;
    sparcv9-*) dpkg_arch=solaris-sparc ;;
    *) printf >&2 '%s\n' "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
apt-key adv --batch --yes --keyserver keyserver.ubuntu.com --recv-keys 74DA7924C5513486
printf 'deb https://apt.dilos.org/dilos dilos2 main\n' >/etc/apt/sources.list.d/dilos.list
dpkg --add-architecture "${dpkg_arch}"
apt-get -o Acquire::Retries=10 -qq update
apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --download-only --no-install-recommends \
    "libc:${dpkg_arch}" \
    "liblgrp:${dpkg_arch}" \
    "libm-dev:${dpkg_arch}" \
    "libpthread:${dpkg_arch}" \
    "libresolv:${dpkg_arch}" \
    "librt:${dpkg_arch}" \
    "libsendfile:${dpkg_arch}" \
    "libsocket:${dpkg_arch}" \
    "system-crt:${dpkg_arch}" \
    "system-header:${dpkg_arch}"
ls -- /var/cache/apt/archives/
set +x
for deb in /var/cache/apt/archives/*"${dpkg_arch}.deb"; do
    dpkg -x "${deb}" .
    rm -- "${deb}"
done
apt-get clean
EOF
# The -dev packages are not available from the apt repository we're using.
# However, those packages are just symlinks from *.so to *.so.<version>.
# This makes all those symlinks.
RUN <<EOF
set +x
# shellcheck disable=SC2044
for lib in $(find . -name '*.so.*'); do
    target="${lib%.so.*}.so"
    ln -s -- "${lib##*/}" "${target}" || printf '%s\n' "warning: silenced error symlinking ${lib}"
done
EOF
# Remove Solaris 11 functions that are optionally used by libbacktrace.
# This is for Solaris 10 compatibility.
RUN <<EOF
rm -- usr/include/link.h
patch -p0 <<'EOF2'
--- usr/include/string.h
+++ usr/include/string10.h
@@ -93 +92,0 @@
-extern size_t strnlen(const char *, size_t);
EOF2
EOF
RUN <<EOF
case "${RUST_TARGET}" in
    x86_64*) lib_arch=amd64 ;;
    sparcv9-*) lib_arch=sparcv9 ;;
    *) printf >&2 '%s\n' "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
mkdir -p -- /sysroot/{usr,lib}
mv -- usr/include /sysroot/usr/include
mv -- usr/lib/"${lib_arch}"/* /sysroot/lib
mv -- lib/"${lib_arch}"/* /sysroot/lib
ln -s -- usr/include /sysroot/sys-include
ln -s -- usr/include /sysroot/include
EOF
WORKDIR /

FROM ghcr.io/taiki-e/build-base:alpine AS builder
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
RUN apk --no-cache add \
    gmp-dev \
    mpc1-dev \
    mpfr-dev

ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p -- "${TOOLCHAIN_DIR}"
ARG SOLARIS_VERSION
RUN <<EOF
cc_target="${RUST_TARGET}${SOLARIS_VERSION}"
printf '%s\n' "${cc_target}" >/CC_TARGET
cd -- "${TOOLCHAIN_DIR}"
mkdir -p -- "${cc_target}"
ln -s -- "${cc_target}" "${RUST_TARGET}"
EOF

COPY --from=binutils-src /binutils-src /tmp/binutils-src
RUN --mount=type=bind,target=/base \
    CC_TARGET="$(</CC_TARGET)" /base/build-binutils.sh

COPY --from=sysroot /sysroot/. "${SYSROOT_DIR}"

ARG GCC_VERSION
COPY --from=gcc-src /gcc-src /tmp/gcc-src
# https://gcc.gnu.org/install/configure.html
RUN <<EOF
export CFLAGS="-g0 -O2 -fPIC"
export CXXFLAGS="-g0 -O2 -fPIC"
export CFLAGS_FOR_TARGET="-g1 -O2 -fPIC"
export CXXFLAGS_FOR_TARGET="-g1 -O2 -fPIC"
export CC="gcc -static --static"
export CXX="g++ -static --static"
export LDFLAGS="-s -static --static"
mkdir -p -- /tmp/gcc-build
cd -- /tmp/gcc-build
set +C
/tmp/gcc-src/configure \
    --prefix="${TOOLCHAIN_DIR}" \
    --target="$(</CC_TARGET)" \
    --with-sysroot="${SYSROOT_DIR}" \
    --with-debug-prefix-map="$(pwd)"= \
    --with-gnu-as \
    --with-gnu-ld \
    --disable-bootstrap \
    --disable-libada \
    --disable-libcilkrts \
    --disable-libgomp \
    --disable-libquadmath \
    --disable-libquadmath-support \
    --disable-libsanitizer \
    --disable-libssp \
    --disable-libvtv \
    --disable-lto \
    --disable-multilib \
    --disable-nls \
    --enable-languages=c,c++,fortran \
    &>build.log || (tail <build.log -5000 && exit 1)
make -j"$(nproc)" &>build.log || (tail <build.log -5000 && exit 1)
make -p "${TOOLCHAIN_DIR}" &>build.log || (tail <build.log -5000 && exit 1)
make install &>build.log || (tail <build.log -5000 && exit 1)
EOF

RUN --mount=type=bind,target=/base \
    /base/common.sh

FROM ubuntu AS final
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
