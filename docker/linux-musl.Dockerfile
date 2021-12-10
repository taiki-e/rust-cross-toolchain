# syntax=docker/dockerfile:1.3-labs

# Refs:
# - https://github.com/richfelker/musl-cross-make
# - https://musl.cc
# - https://github.com/rust-lang/rust/blob/55ccbd090d96ec3bb28dbcb383e65bbfa3c293ff/src/ci/docker/scripts/musl-toolchain.sh

ARG UBUNTU_VERSION=18.04
ARG ALPINE_VERSION=3.15

# Use the version that contains a patch that fixes CVE-2020-28928.
ARG MUSL_CROSS_MAKE_REV=8a2a27ef69b10c526a17281475553be7ca50ab5c
# Available versions: https://github.com/richfelker/musl-cross-make/tree/HEAD/hashes
# Default: https://github.com/richfelker/musl-cross-make/blob/HEAD/Makefile
ARG BINUTILS_VERSION=2.33.1
ARG GCC_VERSION=9.4.0
# https://musl.libc.org/releases.html
ARG MUSL_VERSION_64BIT=1.2.2
# https://github.com/rust-lang/libc/issues/1848
ARG MUSL_VERSION_32BIT=1.1.24
ARG LINUX_VERSION=headers-4.19.88-1

FROM rust:alpine as build-libunwind
SHELL ["/bin/sh", "-eux", "-c"]
COPY /build-libunwind /build-libunwind
WORKDIR /build-libunwind
RUN RUSTFLAGS="-C target-feature=+crt-static -C link-self-contained=yes" \
        cargo build --release --target "$(rustc -Vv | grep host | sed 's/host: //')"
RUN mv target/x86_64-unknown-linux-musl/release/build-libunwind /usr/local/bin/
RUN strip /usr/local/bin/build-libunwind

FROM ghcr.io/taiki-e/build-base:alpine-"${ALPINE_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG MUSL_CROSS_MAKE_REV
RUN mkdir -p /musl-cross-make
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 "https://github.com/richfelker/musl-cross-make/archive/${MUSL_CROSS_MAKE_REV}.tar.gz" \
        | tar xzf - --strip-components 1 -C /musl-cross-make

ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p "${TOOLCHAIN_DIR}"

RUN <<EOF
case "${RUST_TARGET}" in
    aarch64-*) cc_target=aarch64-linux-musl ;;
    arm*hf | thumbv7neon-*) cc_target=arm-linux-musleabihf ;;
    arm*) cc_target=arm-linux-musleabi ;;
    hexagon-*) cc_target=hexagon-linux-musl ;;
    i586-*) cc_target=i586-linux-musl ;;
    i686-*) cc_target=i686-linux-musl ;;
    mips-*) cc_target=mips-linux-muslsf ;;
    mips64-*) cc_target=mips64-linux-muslabi64 ;;
    mips64el-*) cc_target=mips64el-linux-muslabi64 ;;
    mipsel-*) cc_target=mipsel-linux-muslsf ;;
    powerpc-*) cc_target=powerpc-linux-musl ;;
    powerpc64-*) cc_target=powerpc64-linux-musl ;;
    powerpc64le-*) cc_target=powerpc64le-linux-musl ;;
    riscv32gc-*) cc_target=riscv32-linux-musl ;;
    riscv64gc-*) cc_target=riscv64-linux-musl ;;
    s390x-*) cc_target=s390x-linux-musl ;;
    x86_64-*) cc_target=x86_64-linux-musl ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
echo "${cc_target}" >/CC_TARGET
EOF
ARG MUSL_VERSION_64BIT
ARG MUSL_VERSION_32BIT
RUN <<EOF
case "${RUST_TARGET}" in
    aarch64-* | mips64-* | mips64el-* | powerpc64-* | powerpc64le-* | riscv64gc-* | s390x-* | x86_64-*) musl_version="${MUSL_VERSION_64BIT}" ;;
    arm* | hexagon-* | i*86-* | mips-* | mipsel-* | powerpc-* | riscv32gc-* | thumbv7neon-*) musl_version="${MUSL_VERSION_32BIT}" ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
echo "${musl_version}" >/MUSL_VERSION
EOF

ARG BINUTILS_VERSION
ARG GCC_VERSION
ARG LINUX_VERSION
# https://gcc.gnu.org/install/configure.html
# https://github.com/richfelker/musl-cross-make/blob/HEAD/config.mak.dist
# https://conf.musl.cc/plain_20210301_10-2-1.txt
# See also cc-rs for target flags: https://github.com/alexcrichton/cc-rs/blob/b2f6b146b75299c444e05bbde50d03705c7c4b6e/src/lib.rs#L1606.
RUN <<EOF
cc_target="$(</CC_TARGET)"
musl_version="$(</MUSL_VERSION)"
cd musl-cross-make
cat >./config.mak <<EOF2
OUTPUT = ${TOOLCHAIN_DIR}
TARGET = ${cc_target}
BINUTILS_VER = ${BINUTILS_VERSION}
GCC_VER = ${GCC_VERSION}
MUSL_VER = ${musl_version}
LINUX_VER = ${LINUX_VERSION}
DL_CMD = curl -fsSL --retry 10 -C - -o
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
    # https://github.com/buildroot/buildroot/blob/51682c03a8b99d42c1b4e253da80c127d9146c9f/package/gcc/gcc.mk#L228-L230
    powerpc-*) common_config="--without-long-double-128 --enable-secureplt" ;;
    # https://github.com/buildroot/buildroot/blob/51682c03a8b99d42c1b4e253da80c127d9146c9f/package/gcc/gcc.mk#L235-L238
    # https://github.com/void-linux/void-packages/blob/7a0bd8af2d95bcfcd2f95ad71f53ed52ef9048e6/srcpkgs/cross-powerpc64-linux-musl/template
    powerpc64-*) common_config="--with-abi=elfv2 --without-long-double-128 --enable-secureplt" ;;
    powerpc64le-*) common_config="--with-abi=elfv2 --without-long-double-128 --enable-secureplt" ;;
    riscv32gc-*) common_config="--with-arch=rv32gc --with-abi=ilp32d --with-cmodel=medany" ;;
    riscv64gc-*) common_config="--with-arch=rv64gc --with-abi=lp64d --with-cmodel=medany" ;;
    thumbv7neon-*) common_config="--with-arch=armv7-a --with-fpu=neon-vfpv4 --with-float=hard --with-mode=thumb" ;;
esac
echo "${common_config:+"COMMON_CONFIG += ${common_config}"}" >>./config.mak
cat ./config.mak
make install -j"$(nproc)" &>build.log || (cat build.log && exit 1)
EOF
RUN rm -rf "${TOOLCHAIN_DIR}"/share/{doc,man}

# Some paths still use the target name that passed by --target even if we use
# options such as --program-prefix. So use the target name for C by default,
# and create symbolic links with Rust's target name for convenience.
RUN <<EOF
set +x
cc_target="$(</CC_TARGET)"
while IFS= read -r -d '' path; do
    pushd "$(dirname "${path}")" >/dev/null
    original="$(basename "${path}")"
    link="${original/"${cc_target}"/"${RUST_TARGET}"}"
    [[ -e "${link}" ]] || ln -s "${original}" "${link}"
    popd >/dev/null
done < <(find "${TOOLCHAIN_DIR}" -name "${cc_target}*" -print0)
EOF

# Default ld-musl-*.so.1 is broken symbolic link to /lib/libc.so.
RUN <<EOF
cd "${SYSROOT_DIR}/lib"
case "${RUST_TARGET}" in
    aarch64-*) ldso_arch=aarch64 ;;
    arm*hf | thumbv7neon-*) ldso_arch=armhf ;;
    arm*) ldso_arch=arm ;;
    hexagon-*) ldso_arch=hexagon ;;
    i*86-*) ldso_arch=i386 ;;
    mips-*) ldso_arch=mips-sf ;;
    mips64-*) ldso_arch=mips64 ;;
    mips64el-*) ldso_arch=mips64el ;;
    mipsel-*) ldso_arch=mipsel-sf ;;
    powerpc-*) ldso_arch=powerpc ;;
    powerpc64-*) ldso_arch=powerpc64 ;;
    powerpc64le-*) ldso_arch=powerpc64le ;;
    riscv32gc-*) ldso_arch=riscv32 ;;
    riscv64gc-*) ldso_arch=riscv64 ;;
    s390x-*) ldso_arch=s390x ;;
    x86_64-*) ldso_arch=x86_64 ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
ln -sf libc.so "ld-musl-${ldso_arch}.so.1"
echo "${ldso_arch}" >/LDSO_ARCH
EOF
# TODO: needed for clang
RUN <<EOF
cd "${SYSROOT_DIR}/lib"
ldso_arch="$(</LDSO_ARCH)"
case "${RUST_TARGET}" in
    mips-*-musl | mipsel-*-musl) ldso_arch="${ldso_arch/-sf/}" ;;
esac
if [[ "${ldso_arch}" != "$(</LDSO_ARCH)" ]]; then
    ln -sf libc.so "ld-musl-${ldso_arch}.so.1"
fi
echo "${ldso_arch}" >/LDSO_ARCH_CLANG
EOF

COPY /clang-cross.sh /
RUN <<EOF
musl_version="$(</MUSL_VERSION)"
if [[ "${musl_version}" == "${MUSL_VERSION_64BIT}" ]]; then
    case "${RUST_TARGET}" in
        riscv64gc-unknown-linux-musl)
            CC_TARGET="$(</CC_TARGET)" \
                COMMON_FLAGS="--gcc-toolchain=\"\${toolchain_dir}\" --ld-path=\"\${toolchain_dir}\"/bin/${RUST_TARGET}-ld -B\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${GCC_VERSION} -L\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${GCC_VERSION}" \
                CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION} -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION}/${RUST_TARGET}" \
                /clang-cross.sh
            ;;
        *)
            CC_TARGET="$(</CC_TARGET)" \
                COMMON_FLAGS="--gcc-toolchain=\"\${toolchain_dir}\"" \
                /clang-cross.sh
            ;;
    esac
else
    CC_TARGET="$(</CC_TARGET)" \
        COMMON_FLAGS="--gcc-toolchain=\"\${toolchain_dir}\" -B\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${GCC_VERSION} -L\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${GCC_VERSION}" \
        CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION} -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION}/${RUST_TARGET}" \
        /clang-cross.sh
fi
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as test-base
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
COPY /test-base.sh /
RUN /test-base.sh
ARG RUST_TARGET
COPY /test-base-target.sh /
RUN /test-base-target.sh
COPY /test /test
COPY --from=ghcr.io/taiki-e/qemu-user /usr/bin/qemu-* /usr/bin/
COPY --from=build-libunwind /usr/local/bin/build-libunwind /usr/local/bin/

FROM test-base as test-relocated
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
COPY --from=builder /LDSO_ARCH /LDSO_ARCH_CLANG /
ARG GCC_VERSION
RUN /test/test.sh gcc
RUN /test/test.sh clang
RUN touch /DONE

FROM test-base as test
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
COPY --from=builder /LDSO_ARCH /LDSO_ARCH_CLANG /
ARG GCC_VERSION
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN /test/test.sh gcc
RUN /test/test.sh clang
COPY --from=test-relocated /DONE /

FROM alpine:"${ALPINE_VERSION}" as final
SHELL ["/bin/sh", "-eux", "-c"]
RUN apk --no-cache add bash
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
