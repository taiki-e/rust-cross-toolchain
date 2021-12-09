# syntax=docker/dockerfile:1.3-labs

# Refs:
# - https://github.com/rust-lang/rust/blob/27143a9094b55a00d5f440b05b0cb4233b300d33/src/ci/docker/scripts/freebsd-toolchain.sh.

ARG UBUNTU_VERSION=18.04
ARG ALPINE_VERSION=3.15

# See tools/build-docker.sh
ARG FREEBSD_VERSION

FROM ghcr.io/taiki-e/downloader as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p "${SYSROOT_DIR}"

ARG FREEBSD_VERSION
# Download FreeBSD libraries and header files.
# https://download.freebsd.org/ftp/releases
# - As of 13.0, base.txz for arm* targets it is not distributed.
# - Use bsdtar to avoid "unknown extended header keyword" warning.
RUN <<EOF
arch="${RUST_TARGET%-unknown-freebsd*}"
case "${arch}" in
    aarch64) freebsd_arch=arm64/aarch64 ;;
    arm*) freebsd_arch="arm/${arch}" ;;
    i686) freebsd_arch=i386/i386 ;;
    powerpc*) freebsd_arch="powerpc/${arch}" ;;
    riscv64gc) freebsd_arch="riscv/riscv64" ;;
    x86_64) freebsd_arch=amd64/amd64 ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 "https://download.freebsd.org/ftp/releases/${freebsd_arch}/${FREEBSD_VERSION}-RELEASE/base.txz" \
    | bsdtar xJf - -C "${SYSROOT_DIR}" ./lib ./usr/include ./usr/lib ./bin/freebsd-version
EOF
# libc refers freebsd-version command: https://github.com/rust-lang/libc/pull/2581
RUN mv "${SYSROOT_DIR}/bin" "${TOOLCHAIN_DIR}/bin"

COPY /clang-cross.sh /
RUN /clang-cross.sh

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as test-base
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
COPY /test-base.sh /
RUN /test-base.sh
ARG RUST_TARGET
COPY /test-base-target.sh /
RUN /test-base-target.sh
COPY /test /test

FROM test-base as test-relocated
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG FREEBSD_VERSION
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh clang
RUN touch /DONE

FROM test-base as test
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG FREEBSD_VERSION
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN /test/test.sh clang
RUN freebsd-version
COPY --from=test-relocated /DONE /

FROM alpine:"${ALPINE_VERSION}" as final
SHELL ["/bin/sh", "-eux", "-c"]
RUN apk --no-cache add bash
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
COPY --from=test /"${RUST_TARGET}-dev" /"${RUST_TARGET}-dev"
ENV PATH="/${RUST_TARGET}/bin:/${RUST_TARGET}-dev/bin:$PATH"
