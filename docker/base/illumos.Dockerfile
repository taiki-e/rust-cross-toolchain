# syntax=docker/dockerfile:1.3-labs

# Refs:
# - https://github.com/rust-lang/rust/blob/27143a9094b55a00d5f440b05b0cb4233b300d33/src/ci/docker/scripts/illumos-toolchain.sh.
# - https://github.com/illumos/sysroot

ARG UBUNTU_VERSION=18.04

# https://github.com/illumos/sysroot/releases
ARG SYSROOT_VERSION=20181213-de6af22ae73b-v1
# I guess illumos was originally based on solaris10, but it looks like they
# didn't against when gcc9 obsoleted solaris10. So using solaris11 here is
# probably ok, but for now, use the same as rust-lang/rust.
# https://gcc.gnu.org/legacy-ml/gcc/2018-10/msg00139.html
# https://github.com/rust-lang/rust/blob/27143a9094b55a00d5f440b05b0cb4233b300d33/src/ci/docker/scripts/illumos-toolchain.sh#L21
ARG SOLARIS_VERSION=2.10
# https://ftp.gnu.org/gnu/binutils
ARG BINUTILS_VERSION=2.33.1
# https://ftp.gnu.org/gnu/gcc
ARG GCC_VERSION=8.5.0

FROM ghcr.io/taiki-e/downloader as binutils-src
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG BINUTILS_VERSION
RUN mkdir -p /binutils-src
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.gz" \
        | tar xzf - --strip-components 1 -C /binutils-src
FROM ghcr.io/taiki-e/downloader as gcc-src
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG GCC_VERSION
RUN mkdir -p /gcc-src
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.gz" \
        | tar xzf - --strip-components 1 -C /gcc-src

FROM ghcr.io/taiki-e/downloader as sysroot
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG SYSROOT_VERSION
RUN mkdir -p /sysroot
RUN <<EOF
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://github.com/illumos/sysroot/releases/download/${SYSROOT_VERSION}/illumos-sysroot-i386-${SYSROOT_VERSION}.tar.gz" \
    | tar xzf - -C /sysroot
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get -o Acquire::Retries=10 update -qq && apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
    libgmp-dev \
    libmpc-dev \
    libmpfr-dev

ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p "${TOOLCHAIN_DIR}"
ARG SOLARIS_VERSION
RUN <<EOF
cc_target=x86_64-pc-solaris${SOLARIS_VERSION}
echo "${cc_target}" >/CC_TARGET
cd "${TOOLCHAIN_DIR}"
mkdir -p "${cc_target}"
ln -s "${cc_target}" "${RUST_TARGET}"
EOF

COPY --from=binutils-src /binutils-src /tmp/binutils-src
COPY /build-binutils.sh /
RUN CC_TARGET="$(</CC_TARGET)" /build-binutils.sh

COPY --from=sysroot /sysroot/. "${SYSROOT_DIR}"

ARG GCC_VERSION
COPY --from=gcc-src /gcc-src /tmp/gcc-src
RUN mkdir -p /tmp/gcc-build
# https://gcc.gnu.org/install/configure.html
RUN <<EOF
export CFLAGS="-g0 -O2 -fPIC"
export CXXFLAGS="-g0 -O2 -fPIC"
export CFLAGS_FOR_TARGET="-g1 -O2 -fPIC"
export CXXFLAGS_FOR_TARGET="-g1 -O2 -fPIC"
cd /tmp/gcc-build
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
    --disable-multilib \
    --disable-nls \
    --disable-shared \
    --enable-languages=c,c++ \
    --enable-tls \
    &>build.log || (tail <build.log -5000 && exit 1)
make -j"$(nproc)" &>build.log || (tail <build.log -5000 && exit 1)
make -p "${TOOLCHAIN_DIR}" &>build.log || (tail <build.log -5000 && exit 1)
make install &>build.log || (tail <build.log -5000 && exit 1)
EOF

COPY /common.sh /
RUN /common.sh

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"