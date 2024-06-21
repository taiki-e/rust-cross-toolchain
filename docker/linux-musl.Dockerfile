# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

# Refs:
# - https://github.com/richfelker/musl-cross-make
# - https://musl.cc
# - https://github.com/rust-lang/rust/blob/1.70.0/src/ci/docker/scripts/musl-toolchain.sh

ARG RUST_TARGET
ARG UBUNTU_VERSION=20.04
ARG TOOLCHAIN_TAG=dev
ARG HOST_ARCH=amd64

# See tools/build-docker.sh
ARG MUSL_VERSION
ARG GCC_VERSION=9.4.0

FROM ghcr.io/taiki-e/rust-cross-toolchain:"${RUST_TARGET}${MUSL_VERSION}-base${TOOLCHAIN_TAG:+"-${TOOLCHAIN_TAG}"}-${HOST_ARCH}" as toolchain

FROM rust:alpine as build-libunwind
SHELL ["/bin/sh", "-eux", "-c"]
COPY /build-libunwind /build-libunwind
WORKDIR /build-libunwind
ARG CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1
ARG CARGO_PROFILE_RELEASE_DEBUG=1
ARG CARGO_PROFILE_RELEASE_LTO=true
ARG RUSTFLAGS='-C target-feature=+crt-static -C link-self-contained=yes'
RUN cargo build --release --target "$(rustc -vV | grep '^host:' | cut -d' ' -f2)"
RUN mv target/"$(rustc -vV | grep '^host:' | cut -d' ' -f2)"/release/build-libunwind /usr/local/bin/
WORKDIR /

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
COPY --from=toolchain "${TOOLCHAIN_DIR}" "${TOOLCHAIN_DIR}"

# NB: When updating this, the reminder to update docker/base/linux-musl.Dockerfile.
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

ARG GCC_VERSION
RUN --mount=type=bind,target=/docker <<EOF
export COMMON_FLAGS="--gcc-toolchain=\"\${toolchain_dir}\""
case "${RUST_TARGET}" in
    hexagon-*) rm -f "${TOOLCHAIN_DIR}"/bin/qemu-* ;; # TODO: rm
    riscv64*)
        COMMON_FLAGS="${COMMON_FLAGS} --ld-path=\"\${toolchain_dir}\"/bin/${RUST_TARGET}-ld -B\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${GCC_VERSION} -L\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${GCC_VERSION}" \
            CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION} -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION}/${RUST_TARGET}" \
            /docker/clang-cross.sh
        ;;
    aarch64-* | mips64-* | mips64el-* | powerpc64-* | powerpc64le-* | s390x-* | x86_64*)
        /docker/clang-cross.sh
        ;;
    *)
        COMMON_FLAGS="${COMMON_FLAGS} -B\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${GCC_VERSION} -L\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${GCC_VERSION}" \
            CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION} -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION}/${RUST_TARGET}" \
            /docker/clang-cross.sh
        ;;
esac
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as test-base
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
COPY /test-base.sh /
RUN /test-base.sh
ARG RUST_TARGET
COPY /test-base /test-base
RUN /test-base/target.sh
COPY /test /test
COPY --from=ghcr.io/taiki-e/qemu-user /usr/bin/qemu-* /usr/bin/
COPY --from=build-libunwind /usr/local/bin/build-libunwind /usr/local/bin/

FROM test-base as test-relocated
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
ARG GCC_VERSION
RUN <<EOF
case "${RUST_TARGET}" in
    hexagon-*) ;;
    *) /test/test.sh gcc ;;
esac
EOF
RUN /test/test.sh clang
RUN touch /DONE

FROM test-base as test
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ARG GCC_VERSION
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN <<EOF
case "${RUST_TARGET}" in
    hexagon-*) ;;
    *) /test/test.sh gcc ;;
esac
EOF
RUN /test/test.sh clang
# COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
