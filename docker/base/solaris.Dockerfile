# syntax=docker/dockerfile:1.3-labs

# Refs:
# - https://github.com/rust-lang/rust/blob/1.67.0/src/ci/docker/host-x86_64/dist-various-2/build-solaris-toolchain.sh

ARG UBUNTU_VERSION=18.04

ARG SOLARIS_VERSION=2.11
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

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as sysroot
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
RUN mkdir -p /tmp/sysroot
WORKDIR /tmp/sysroot
RUN <<EOF
case "${RUST_TARGET}" in
    x86_64-*) dpkg_arch=solaris-i386 ;;
    sparcv9-*) dpkg_arch=solaris-sparc ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
apt-key adv --batch --yes --keyserver keyserver.ubuntu.com --recv-keys 74DA7924C5513486
echo "deb https://apt.dilos.org/dilos dilos2 main" >/etc/apt/sources.list.d/dilos.list
dpkg --add-architecture "${dpkg_arch}"
apt-get -o Acquire::Retries=10 update -qq
apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 download $(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances \
    "libc:${dpkg_arch}" \
    "liblgrp-dev:${dpkg_arch}" \
    "liblgrp:${dpkg_arch}" \
    "libm-dev:${dpkg_arch}" \
    "libpthread:${dpkg_arch}" \
    "libresolv:${dpkg_arch}" \
    "librt:${dpkg_arch}" \
    "libsendfile-dev:${dpkg_arch}" \
    "libsendfile:${dpkg_arch}" \
    "libsocket:${dpkg_arch}" \
    "system-crt:${dpkg_arch}" \
    "system-header:${dpkg_arch}" \
    | grep '^\w')
ls
set +x
for deb in *"${dpkg_arch}.deb"; do
    dpkg -x "${deb}" .
    rm "${deb}"
done
EOF
# The -dev packages are not available from the apt repository we're using.
# However, those packages are just symlinks from *.so to *.so.<version>.
# This makes all those symlinks.
RUN <<EOF
set +x
for lib in $(find . -name '*.so.*'); do
    target="${lib%.so.*}.so"
    [[ -e "${target}" ]] || ln -s "${lib##*/}" "${target}"
done
EOF
RUN <<EOF
case "${RUST_TARGET}" in
    x86_64-*) lib_arch=amd64 ;;
    sparcv9-*) lib_arch=sparcv9 ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
mkdir -p /sysroot/{usr,lib}
mv usr/include /sysroot/usr/include
mv usr/lib/"${lib_arch}"/* /sysroot/lib
mv lib/"${lib_arch}"/* /sysroot/lib
ln -s usr/include /sysroot/sys-include
ln -s usr/include /sysroot/include
EOF
WORKDIR /

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
cc_target="${RUST_TARGET}${SOLARIS_VERSION}"
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
    --enable-languages=c,c++ \
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
