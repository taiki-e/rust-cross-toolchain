# syntax=docker/dockerfile:1.3-labs

# Refs:
# - https://github.com/richfelker/musl-cross-make
# - https://musl.cc
# - https://github.com/rust-lang/rust/blob/55ccbd090d96ec3bb28dbcb383e65bbfa3c293ff/src/ci/docker/scripts/musl-toolchain.sh

ARG RUST_TARGET
ARG UBUNTU_VERSION=18.04
ARG TOOLCHAIN_TAG=dev

# See tools/build-docker.sh
ARG MUSL_VERSION
ARG GCC_VERSION=9.4.0

FROM ghcr.io/taiki-e/rust-cross-toolchain:"${RUST_TARGET}${MUSL_VERSION}-base${TOOLCHAIN_TAG:+"-${TOOLCHAIN_TAG}"}-amd64" as toolchain

FROM rust:alpine as build-libunwind
SHELL ["/bin/sh", "-eux", "-c"]
COPY /build-libunwind /build-libunwind
WORKDIR /build-libunwind
RUN RUSTFLAGS="-C target-feature=+crt-static -C link-self-contained=yes" \
        cargo build --release --target "$(rustc -Vv | grep host | sed 's/host: //')"
RUN mv target/x86_64-unknown-linux-musl/release/build-libunwind /usr/local/bin/
RUN strip /usr/local/bin/build-libunwind

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
COPY --from=toolchain "${TOOLCHAIN_DIR}" "${TOOLCHAIN_DIR}"

# When updating this, the reminder to update docker/base/linux-musl.Dockerfile.
RUN <<EOF
case "${RUST_TARGET}" in
    aarch64-*) cc_target=aarch64-linux-musl ;;
    arm*hf | thumbv7neon-*) cc_target=arm-linux-musleabihf ;;
    arm*) cc_target=arm-linux-musleabi ;;
    hexagon-*) cc_target=hexagon-unknown-linux-musl ;;
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

# TODO(clang,mips-musl-sf): needed for clang
RUN <<EOF
case "${RUST_TARGET}" in
    mips-*) ldso_arch=mips ;;
    mipsel-*) ldso_arch=mipsel ;;
    *) exit 0 ;;
esac
cd "${SYSROOT_DIR}/lib"
ln -sf libc.so "ld-musl-${ldso_arch}.so.1"
EOF

COPY /clang-cross.sh /
ARG GCC_VERSION
RUN <<EOF
export COMMON_FLAGS="--gcc-toolchain=\"\${toolchain_dir}\""
case "${RUST_TARGET}" in
    hexagon-unknown-linux-musl) ;;
    riscv64gc-unknown-linux-musl)
        COMMON_FLAGS="${COMMON_FLAGS} --ld-path=\"\${toolchain_dir}\"/bin/${RUST_TARGET}-ld -B\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${GCC_VERSION} -L\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${GCC_VERSION}" \
            CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION} -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION}/${RUST_TARGET}" \
            /clang-cross.sh
        ;;
    aarch64-* | mips64-* | mips64el-* | powerpc64-* | powerpc64le-* | s390x-* | x86_64-*)
        /clang-cross.sh
        ;;
    *)
        COMMON_FLAGS="${COMMON_FLAGS} -B\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${GCC_VERSION} -L\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${GCC_VERSION}" \
            CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION} -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION}/${RUST_TARGET}" \
            /clang-cross.sh
        ;;
esac
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
ARG GCC_VERSION
RUN <<EOF
case "${RUST_TARGET}" in
    hexagon-unknown-linux-musl) ;;
    *) /test/test.sh gcc ;;
esac
EOF
RUN /test/test.sh clang
RUN touch /DONE

FROM test-base as test
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ARG GCC_VERSION
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN <<EOF
case "${RUST_TARGET}" in
    hexagon-unknown-linux-musl) ;;
    *) /test/test.sh gcc ;;
esac
EOF
RUN /test/test.sh clang
COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
