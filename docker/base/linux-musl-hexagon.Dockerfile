# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

# musl-cross-make doesn't support this target
#
# Refs:
# - https://github.com/rust-lang/rust/blob/1.84.0/src/doc/rustc/src/platform-support/hexagon-unknown-linux-musl.md
# - https://github.com/qemu/qemu/blob/v9.2.0/tests/docker/dockerfiles/debian-hexagon-cross.docker

ARG UBUNTU_VERSION=20.04

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS builder
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR=/toolchain
RUN mkdir -p -- /tmp/toolchain
# https://github.com/quic/toolchain_for_hexagon/releases
ARG LLVM_VERSION=19.1.5
RUN <<EOF
dpkg_arch=$(dpkg --print-architecture)
case "${dpkg_arch##*-}" in
    amd64) host=x86_64-linux-musl ;;
    arm64) host=aarch64-linux-gnu ;;
    *) printf >&2 '%s\n' "unsupported architecture '${dpkg_arch}'" && exit 1 ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://artifacts.codelinaro.org/artifactory/codelinaro-toolchain-for-hexagon/${LLVM_VERSION}/clang+llvm-${LLVM_VERSION}-cross-hexagon-unknown-linux-musl_${host}.tar.zst" \
    | tar xf - --zstd --strip-components 1 -C /tmp/toolchain
mv -- /tmp/toolchain/"${host}" "${TOOLCHAIN_DIR}"
cd -- "${TOOLCHAIN_DIR}"
ln -s -- "target/${RUST_TARGET}" "${RUST_TARGET}"
EOF

RUN --mount=type=bind,source=./common.sh,target=/tmp/common.sh \
    /tmp/common.sh

FROM ubuntu:"${UBUNTU_VERSION}" AS final
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /toolchain /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
