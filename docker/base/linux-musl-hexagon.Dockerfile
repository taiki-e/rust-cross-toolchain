# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

# musl-cross-make doesn't support this target
#
# Refs:
# - https://codelinaro.jfrog.io/ui/native/codelinaro-toolchain-for-hexagon
# - https://github.com/qemu/qemu/blob/v9.0.0/tests/docker/dockerfiles/debian-hexagon-cross.docker

FROM ghcr.io/taiki-e/build-base:alpine AS builder
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG RUST_TARGET
ARG TOOLCHAIN_DIR=/toolchain/x86_64-linux-gnu
RUN mkdir -p -- /toolchain
# https://codelinaro.jfrog.io/ui/native/codelinaro-toolchain-for-hexagon
ARG LLVM_VERSION=17.0.0-rc3
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://codelinaro.jfrog.io/artifactory/codelinaro-toolchain-for-hexagon/${LLVM_VERSION}/clang+llvm-${LLVM_VERSION}-cross-hexagon-unknown-linux-musl.tar.xz" \
        | tar xJf - --strip-components 1 -C /toolchain

RUN <<EOF
cd -- "${TOOLCHAIN_DIR}"
ln -s -- "target/${RUST_TARGET}" "${RUST_TARGET}"
EOF

RUN --mount=type=bind,target=/base \
    /base/common.sh

FROM ubuntu AS final
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /toolchain/x86_64-linux-gnu /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
