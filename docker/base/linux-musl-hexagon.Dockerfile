# syntax=docker/dockerfile:1

# musl-cross-make doesn't support this target
#
# Refs:
# - https://codelinaro.jfrog.io/ui/native/codelinaro-toolchain-for-hexagon
# - https://github.com/qemu/qemu/blob/v8.0.0/tests/docker/dockerfiles/debian-hexagon-cross.docker

ARG UBUNTU_VERSION=20.04
ARG ALPINE_VERSION=3.15

FROM ghcr.io/taiki-e/build-base:alpine-"${ALPINE_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG RUST_TARGET
ARG TOOLCHAIN_DIR=/toolchain/x86_64-linux-gnu
RUN mkdir -p /toolchain
# https://codelinaro.jfrog.io/ui/native/codelinaro-toolchain-for-hexagon
ARG LLVM_VERSION=16.0.5
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://codelinaro.jfrog.io/artifactory/codelinaro-toolchain-for-hexagon/v${LLVM_VERSION}/clang+llvm-${LLVM_VERSION}-cross-hexagon-unknown-linux-musl.tar.xz" \
        | tar xJf - --strip-components 1 -C /toolchain

RUN <<EOF
cd "${TOOLCHAIN_DIR}"
ln -s "target/${RUST_TARGET}" "${RUST_TARGET}"
EOF

RUN --mount=type=bind,target=/base \
    /base/common.sh

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /toolchain/x86_64-linux-gnu /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
