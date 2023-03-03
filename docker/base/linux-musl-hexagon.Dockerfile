# syntax=docker/dockerfile:1.4

# musl-cross-make doesn't support this target
#
# Refs:
# - https://github.com/qemu/qemu/commit/afbdf0a44eaf6d529ec1e5250178d025f15aa606

ARG UBUNTU_VERSION=18.04

FROM ghcr.io/taiki-e/downloader as llvm-src
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
# https://github.com/llvm/llvm-project/releases/tag/llvmorg-13.0.0
ARG LLVM_REV=d7b669b3a30345cfcdb2fde2af6f48aa4b94845d
RUN mkdir -p /llvm-project
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://github.com/llvm/llvm-project/archive/${LLVM_REV}.tar.gz" \
        | tar xzf - --strip-components 1 -C /llvm-project
FROM ghcr.io/taiki-e/downloader as musl-src
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
# https://github.com/quic/musl/commits/hexagon
# musl 1.2.2: https://github.com/quic/musl/blob/570ed19dab64b413deae61ea895043093de1dddd/VERSION
ARG MUSL_REV=570ed19dab64b413deae61ea895043093de1dddd
RUN mkdir -p /musl
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://github.com/quic/musl/archive/${MUSL_REV}.tar.gz" \
        | tar xzf - --strip-components 1 -C /musl
FROM ghcr.io/taiki-e/downloader as linux-src
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG LINUX_VERSION=5.6.18
RUN mkdir -p /linux
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-${LINUX_VERSION}.tar.xz" \
        | tar xJf - --strip-components 1 -C /linux

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p "${TOOLCHAIN_DIR}"
RUN apt-get -o Acquire::Retries=10 update -qq && apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
    bison \
    flex \
    python3 \
    rsync

ARG BASE=/tmp/build-toolchain
RUN mkdir -p "${BASE}"

COPY --from=llvm-src /llvm-project "${BASE}/llvm-project"
COPY --from=musl-src /musl "${BASE}/musl"
COPY --from=linux-src /linux "${BASE}/linux"

# Build llvm clang
# https://llvm.org/docs/GettingStarted.html#getting-the-source-code-and-building-llvm
# https://llvm.org/docs/CMake.html
RUN mkdir -p "${BASE}/build-llvm"
WORKDIR "${BASE}/build-llvm"
RUN <<EOF
cmake -G Ninja \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DCMAKE_INSTALL_PREFIX="${TOOLCHAIN_DIR}" \
    -DLLVM_ENABLE_LLD=ON \
    -DLLVM_TARGETS_TO_BUILD="Hexagon" \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    "${BASE}/llvm-project/llvm"
EOF
RUN <<EOF
ninja \
    install-clang \
    install-clang-resource-headers \
    install-lld \
    install-llvm-ar \
    install-llvm-as \
    install-llvm-config \
    install-llvm-cxxfilt \
    install-llvm-nm \
    install-llvm-objcopy \
    install-llvm-objdump \
    install-llvm-ranlib \
    install-llvm-readelf \
    install-llvm-size \
    install-llvm-strings \
    install-llvm-strip
EOF
WORKDIR /

RUN <<EOF
cat >"${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-clang" <<EOF2
#!/bin/sh
set -eu
toolchain_dir="\$(cd "\$(dirname "\$0")"/.. && pwd)"
exec "\${toolchain_dir}"/bin/clang --target=${RUST_TARGET} --sysroot="\${toolchain_dir}"/${RUST_TARGET} "\$@"
EOF2
cat >"${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-clang++" <<EOF2
#!/bin/sh
set -eu
toolchain_dir="\$(cd "\$(dirname "\$0")"/.. && pwd)"
exec "\${toolchain_dir}"/bin/clang++ --target=${RUST_TARGET} --sysroot="\${toolchain_dir}"/${RUST_TARGET} "\$@"
EOF2
chmod +x "${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-clang" "${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-clang++"
tail -n +1 "${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-clang" "${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-clang++"
EOF

ARG HEX_TOOLS_TARGET_BASE="${SYSROOT_DIR}/usr"
# Build kernel headers
RUN <<EOF
mkdir -p "${BASE}/build-linux"
cd "${BASE}/linux"
make O=../build-linux ARCH=hexagon \
    KBUILD_CFLAGS_KERNEL="-mlong-calls" \
    CC="${TOOLCHAIN_DIR}/bin/hexagon-unknown-linux-musl-clang" \
    LD="${TOOLCHAIN_DIR}/bin/ld.lld" \
    KBUILD_VERBOSE=1 comet_defconfig
make mrproper
cd "${BASE}/build-linux"
make \
    ARCH=hexagon \
    CC="${TOOLCHAIN_DIR}/bin/clang" \
    INSTALL_HDR_PATH="${HEX_TOOLS_TARGET_BASE}" \
    V=1 \
    headers_install
EOF

# Build musl headers
RUN <<EOF
cd "${BASE}/musl"
make clean
CC="${TOOLCHAIN_DIR}/bin/hexagon-unknown-linux-musl-clang" \
    CROSS_COMPILE=hexagon-unknown-linux-musl \
    LIBCC="${HEX_TOOLS_TARGET_BASE}/lib/libclang_rt.builtins-hexagon.a" \
    CROSS_CFLAGS="-G0 -O0 -mv65 -fno-builtin -fno-rounding-math --target=hexagon-unknown-linux-musl" \
    ./configure --target=hexagon --prefix="${HEX_TOOLS_TARGET_BASE}"
PATH="${TOOLCHAIN_DIR}/bin:$PATH" make CROSS_COMPILE= install-headers
EOF

# Build clang_rt
RUN <<EOF
mkdir -p "${BASE}/build-clang_rt"
cd "${BASE}/build-clang_rt"
cmake -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DLLVM_CONFIG_PATH="${BASE}/build-llvm/bin/llvm-config" \
    -DCMAKE_ASM_FLAGS="-G0 -mlong-calls -fno-pic --target=hexagon-unknown-linux-musl " \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_C_COMPILER="${TOOLCHAIN_DIR}/bin/hexagon-unknown-linux-musl-clang" \
    -DCMAKE_ASM_COMPILER="${TOOLCHAIN_DIR}/bin/hexagon-unknown-linux-musl-clang" \
    -DCMAKE_INSTALL_PREFIX="${HEX_TOOLS_TARGET_BASE}" \
    -DCMAKE_CROSSCOMPILING=ON \
    -DCMAKE_C_COMPILER_FORCED=ON \
    -DCMAKE_CXX_COMPILER_FORCED=ON \
    -DCOMPILER_RT_BUILD_BUILTINS=ON \
    -DCOMPILER_RT_BUILTINS_ENABLE_PIC=OFF \
    -DCOMPILER_RT_BUILD_XRAY=OFF \
    -DCOMPILER_RT_INCLUDE_TESTS=OFF \
    -DCMAKE_SIZEOF_VOID_P=4 \
    -DCOMPILER_RT_OS_DIR= \
    -DCAN_TARGET_hexagon=1 \
    -DCAN_TARGET_x86_64=0 \
    -DCOMPILER_RT_SUPPORTED_ARCH=hexagon \
    -DLLVM_ENABLE_PROJECTS="compiler-rt" \
    "${BASE}/llvm-project/compiler-rt"
ninja install-compiler-rt
EOF

# Build musl
RUN <<EOF
cd "${BASE}/musl"
make clean
CROSS_COMPILE=hexagon-unknown-linux-musl- \
    AR=llvm-ar \
    RANLIB=llvm-ranlib \
    STRIP=llvm-strip \
    CC=clang \
    LIBCC="${HEX_TOOLS_TARGET_BASE}"/lib/libclang_rt.builtins-hexagon.a \
    CFLAGS="-G0 -O0 -mv65 -fno-builtin -fno-rounding-math --target=hexagon-unknown-linux-musl" \
    ./configure --target=hexagon --prefix="${HEX_TOOLS_TARGET_BASE}"
PATH="${TOOLCHAIN_DIR}/bin/:$PATH" make CROSS_COMPILE= install
EOF
RUN <<EOF
cd "${HEX_TOOLS_TARGET_BASE}"/lib
ls | grep '\.so'
ln -sf libc.so ld-musl-hexagon.so.1
mkdir -p "${SYSROOT_DIR}/lib"
cd "${SYSROOT_DIR}/lib"
ln -sf ../usr/lib/ld-musl-hexagon.so.1
EOF

COPY /common.sh /
RUN /common.sh

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
