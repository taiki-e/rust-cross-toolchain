# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

# Refs:
# - https://github.com/richfelker/musl-cross-make
# - https://musl.cc
# - https://github.com/rust-lang/rust/blob/1.70.0/src/ci/docker/scripts/musl-toolchain.sh

# TODO: enable debuginfo https://github.com/rust-lang/rust/pull/90733

# Use the fork that contains a patch to fix CVE-2020-28928 for musl 1.1 and add binutils 2.36.1 hash for riscv.
# https://github.com/taiki-e/musl-cross-make/tree/dev
ARG MUSL_CROSS_MAKE_REV=09328999fa03502bb460951d6841d009eddcb081
# Available versions: https://github.com/richfelker/musl-cross-make/tree/HEAD/hashes
# Default: https://github.com/richfelker/musl-cross-make/blob/HEAD/Makefile
ARG BINUTILS_VERSION=2.33.1
ARG GCC_VERSION=9.4.0
ARG MUSL_VERSION
ARG LINUX_VERSION=headers-4.19.88-1

FROM ghcr.io/taiki-e/build-base:alpine as builder
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG MUSL_CROSS_MAKE_REV
RUN mkdir -p /musl-cross-make
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://github.com/richfelker/musl-cross-make/archive/${MUSL_CROSS_MAKE_REV}.tar.gz" \
        | tar xzf - --strip-components 1 -C /musl-cross-make

ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p "${TOOLCHAIN_DIR}"

# NB: When updating this, the reminder to update docker/linux-musl.Dockerfile.
RUN <<EOF
case "${RUST_TARGET}" in
    arm*hf | thumbv7neon-*) cc_target=arm-linux-musleabihf ;;
    arm*) cc_target=arm-linux-musleabi ;;
    hexagon-*) cc_target="${RUST_TARGET}" ;;
    # https://github.com/rust-lang/rust/blob/1.70.0/compiler/rustc_target/src/spec/mips_unknown_linux_musl.rs#L7
    # https://github.com/rust-lang/rust/blob/1.70.0/compiler/rustc_target/src/spec/mipsel_unknown_linux_musl.rs#L6
    mips-*) cc_target=mips-linux-muslsf ;;
    mipsel-*) cc_target=mipsel-linux-muslsf ;;
    riscv32gc-* | riscv64gc-*) cc_target="${RUST_TARGET/gc-unknown/}" ;;
    *) cc_target="${RUST_TARGET/-unknown/}" ;;
esac
echo "${cc_target}" >/CC_TARGET
EOF

ARG BINUTILS_VERSION
ARG GCC_VERSION
ARG MUSL_VERSION
ARG LINUX_VERSION
# https://gcc.gnu.org/install/configure.html
# https://github.com/richfelker/musl-cross-make/blob/0f22991b8d47837ef8dd60a0c43cf40fcf76217a/config.mak.dist
# https://conf.musl.cc/plain_20210301_10-2-1.txt
# See also cc-rs for target flags: https://github.com/rust-lang/cc-rs/blob/1.0.73/src/lib.rs#L1649
# Use binutils 2.36.1 for riscv because linker error "unsupported ISA subset 'z'" since nightly-2023-08-09 (LLVM 17)
RUN <<EOF
cc_target=$(</CC_TARGET)
case "${RUST_TARGET}" in
    riscv*) BINUTILS_VERSION=2.36.1 ;;
esac
cd musl-cross-make
cat >./config.mak <<EOF2
OUTPUT = ${TOOLCHAIN_DIR}
TARGET = ${cc_target}
BINUTILS_VER = ${BINUTILS_VERSION}
GCC_VER = ${GCC_VERSION}
MUSL_VER = ${MUSL_VERSION}
LINUX_VER = ${LINUX_VERSION}
DL_CMD = curl -fsSL --retry 10 --retry-connrefused -C - -o
COMMON_CONFIG += CC="gcc -static --static" CXX="g++ -static --static"
# Use -g1: https://github.com/rust-lang/rust/pull/90733
COMMON_CONFIG += CFLAGS="-g1 -O2" CXXFLAGS="-g1 -O2" LDFLAGS="-s -static --static"
COMMON_CONFIG += --disable-nls
COMMON_CONFIG += --with-debug-prefix-map=\$(CURDIR)=
GCC_CONFIG += --enable-default-pie --enable-static-pie
GCC_CONFIG += --enable-languages=c,c++
GCC_CONFIG += --disable-libquadmath --disable-libquadmath-support --disable-decimal-float
GCC_CONFIG += --disable-multilib
EOF2
case "${RUST_TARGET}" in
    arm-*hf) common_config="--with-arch=armv6 --with-fpu=vfp --with-float=hard --with-mode=arm" ;;
    arm-*) common_config="--with-arch=armv6 --with-float=soft --with-mode=arm" ;;
    armv5te-*) common_config="--with-arch=armv5te --with-float=soft --with-mode=arm" ;;
    armv7-*hf) common_config="--with-arch=armv7-a --with-fpu=vfpv3-d16 --with-float=hard --with-mode=thumb" ;;
    armv7-*) common_config="--with-arch=armv7-a --with-float=softfp --with-mode=thumb" ;;
    mips-*) common_config="--with-arch=mips32r2" ;;
    mips64-*) common_config="--with-arch=mips64r2" ;;
    mips64el-*) common_config="--with-arch=mips64r2" ;;
    mipsel-*) common_config="--with-arch=mips32r2" ;;
    # https://github.com/buildroot/buildroot/blob/2022.02/package/gcc/gcc.mk#L229-L234
    powerpc-*) common_config="--without-long-double-128 --enable-secureplt" ;;
    # https://github.com/buildroot/buildroot/blob/2022.02/package/gcc/gcc.mk#L229-L244
    powerpc64-*) common_config="--with-abi=elfv2 --without-long-double-128 --enable-secureplt" ;;
    powerpc64le-*) common_config="--with-abi=elfv2 --without-long-double-128 --enable-secureplt" ;;
    riscv32*) common_config="--with-arch=rv32gc --with-abi=ilp32d --with-cmodel=medany" ;;
    riscv64*) common_config="--with-arch=rv64gc --with-abi=lp64d --with-cmodel=medany" ;;
    thumbv7neon-*) common_config="--with-arch=armv7-a --with-fpu=neon-vfpv4 --with-float=hard --with-mode=thumb" ;;
esac
echo "${common_config:+"COMMON_CONFIG += ${common_config}"}" >>./config.mak
cat ./config.mak
make install -j"$(nproc)" &>build.log || (tail <build.log -5000 && exit 1)
EOF

RUN --mount=type=bind,target=/base \
    /base/common.sh

# Default ld-musl-*.so.1 is broken symbolic link to /lib/libc.so.
RUN <<EOF
case "${RUST_TARGET}" in
    aarch64-*) ldso_arch=aarch64 ;;
    arm*hf | thumbv7neon-*) ldso_arch=armhf ;;
    arm*) ldso_arch=arm ;;
    hexagon-*) ldso_arch=hexagon ;;
    i?86-*) ldso_arch=i386 ;;
    mips-*) ldso_arch=mips-sf ;;
    mips64-*) ldso_arch=mips64 ;;
    mips64el-*) ldso_arch=mips64el ;;
    mipsel-*) ldso_arch=mipsel-sf ;;
    powerpc-*) ldso_arch=powerpc ;;
    powerpc64-*) ldso_arch=powerpc64 ;;
    powerpc64le-*) ldso_arch=powerpc64le ;;
    riscv32*) ldso_arch=riscv32 ;;
    riscv64*) ldso_arch=riscv64 ;;
    s390x-*) ldso_arch=s390x ;;
    x86_64*) ldso_arch=x86_64 ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
cd "${SYSROOT_DIR}/lib"
ls | grep '\.so'
ln -sf libc.so "ld-musl-${ldso_arch}.so.1"
EOF

FROM ubuntu as final
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
