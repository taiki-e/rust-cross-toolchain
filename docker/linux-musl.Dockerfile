# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

# Refs:
# - https://github.com/richfelker/musl-cross-make
# - https://musl.cc
# - https://github.com/rust-lang/rust/blob/1.84.0/src/ci/docker/scripts/musl-toolchain.sh

ARG RUST_TARGET
ARG UBUNTU_VERSION=20.04
ARG TOOLCHAIN_TAG=dev
ARG HOST_ARCH=amd64

# See tools/build-docker.sh
ARG MUSL_VERSION

FROM ghcr.io/taiki-e/rust-cross-toolchain:"${RUST_TARGET}${MUSL_VERSION}-base${TOOLCHAIN_TAG:+"-${TOOLCHAIN_TAG}"}-${HOST_ARCH}" AS toolchain

FROM rust:alpine AS build-libunwind
SHELL ["/bin/sh", "-CeEuxo", "pipefail", "-c"]
COPY /build-libunwind /build-libunwind
WORKDIR /build-libunwind
ARG CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1
ARG CARGO_PROFILE_RELEASE_DEBUG=1
ARG CARGO_PROFILE_RELEASE_LTO=true
ARG RUSTFLAGS='-C target-feature=+crt-static -C link-self-contained=yes'
RUN cargo build --release --target "$(rustc -vV | grep -E '^host:' | cut -d' ' -f2)"
RUN mv -- target/"$(rustc -vV | grep -E '^host:' | cut -d' ' -f2)"/release/build-libunwind /usr/local/bin/
WORKDIR /

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS builder
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
COPY --from=toolchain "${TOOLCHAIN_DIR}" "${TOOLCHAIN_DIR}"

# NB: When updating this, the reminder to update docker/base/linux-musl.Dockerfile.
RUN <<EOF
case "${RUST_TARGET}" in
    arm*hf | thumb*hf) cc_target=arm-linux-musleabihf ;;
    arm* | thumb*) cc_target=arm-linux-musleabi ;;
    hexagon-*) cc_target="${RUST_TARGET}" ;;
    # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/mips_unknown_linux_musl.rs#L7
    # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/mipsel_unknown_linux_musl.rs#L6
    mips-*) cc_target=mips-linux-muslsf ;;
    mipsel-*) cc_target=mipsel-linux-muslsf ;;
    riscv??gc-*) cc_target="${RUST_TARGET/gc-unknown/}" ;;
    *) cc_target="${RUST_TARGET/-unknown/}" ;;
esac
printf '%s\n' "${cc_target}" >/CC_TARGET
EOF

RUN --mount=type=bind,source=./clang-cross.sh,target=/tmp/clang-cross.sh <<EOF
case "${RUST_TARGET}" in
    hexagon-*)
        rm -f -- "${TOOLCHAIN_DIR}"/bin/qemu-* # TODO: rm
        exit 0
        ;;
esac
gcc_version=$("${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-gcc" --version | sed -n '1 s/^.*) //p')
export COMMON_FLAGS="--gcc-toolchain=\"\${toolchain_dir}\""
case "${RUST_TARGET}" in
    riscv*)
        COMMON_FLAGS="${COMMON_FLAGS} --ld-path=\"\${toolchain_dir}\"/bin/${RUST_TARGET}-ld -B\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${gcc_version} -L\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${gcc_version}" \
            CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version} -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version}/${RUST_TARGET}" \
            /tmp/clang-cross.sh
        ;;
    aarch64-* | mips64-* | mips64el-* | powerpc64-* | powerpc64le-* | s390x-* | x86_64*)
        /tmp/clang-cross.sh
        ;;
    *)
        COMMON_FLAGS="${COMMON_FLAGS} -B\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${gcc_version} -L\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${gcc_version}" \
            CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version} -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version}/${RUST_TARGET}" \
            /tmp/clang-cross.sh
        ;;
esac
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS test-base
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=bind,source=./test-base.sh,target=/tmp/test-base.sh \
    /tmp/test-base.sh
ARG RUST_TARGET
RUN --mount=type=bind,source=./test-base,target=/test-base \
    /test-base/target.sh
COPY /test /test
COPY --from=ghcr.io/taiki-e/qemu-user /usr/bin/qemu-* /usr/bin/
COPY --from=build-libunwind /usr/local/bin/build-libunwind /usr/local/bin/

FROM test-base AS test-relocated
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN <<EOF
case "${RUST_TARGET}" in
    hexagon-*) ;;
    *) /test/test.sh gcc ;;
esac
EOF
RUN /test/test.sh clang
RUN touch -- /DONE

FROM test-base AS test
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN <<EOF
case "${RUST_TARGET}" in
    hexagon-*) ;;
    *) /test/test.sh gcc ;;
esac
EOF
# TODO(powerpc-unknown-linux-muslspe): qemu-ppc: Could not open '/lib/ld-musl-powerpc.so.1': No such file or directory
RUN <<EOF
case "${RUST_TARGET}" in
    powerpc-*spe) ;;
    *) /test/test.sh clang ;;
esac
EOF
# COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" AS final
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
