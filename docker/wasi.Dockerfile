# syntax=docker/dockerfile:1

# Refs:
# - https://github.com/WebAssembly/wasi-sdk

ARG UBUNTU_VERSION=20.04

# https://github.com/WebAssembly/wasi-sdk/releases
ARG WASI_SDK_VERSION=16.0
# https://github.com/bytecodealliance/wasmtime/releases
ARG WASMTIME_VERSION=6.0.1

FROM ghcr.io/taiki-e/downloader as wasi-sdk
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG RUST_TARGET
RUN mkdir -p /wasi-sdk
ARG WASI_SDK_VERSION
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK_VERSION%%.*}/wasi-sdk-${WASI_SDK_VERSION}-linux.tar.gz" \
        | tar xzf - --strip-components 1 -C /wasi-sdk
RUN <<EOF
cd /wasi-sdk
ln -s share/wasi-sysroot "${RUST_TARGET}"
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
COPY --from=wasi-sdk /wasi-sdk "${TOOLCHAIN_DIR}"

RUN --mount=type=bind,target=/docker \
    /docker/base/common.sh

# Do not use prefixed clang: https://github.com/taiki-e/setup-cross-toolchain-action/commit/fd352f3ffabd00daf2759ab4a3276729e52eeb10
# RUN --mount=type=bind,target=/docker \
#     COMMON_FLAGS="-L\"\${toolchain_dir}\"/lib -L\"\${toolchain_dir}\"/${RUST_TARGET}/lib/${RUST_TARGET}" \
#     /docker/clang-cross.sh

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as test-base
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
COPY /test-base.sh /
RUN /test-base.sh
ARG WASMTIME_VERSION
RUN <<EOF
dpkg_arch="$(dpkg --print-architecture)"
case "${dpkg_arch##*-}" in
    amd64) wasmtime_arch=x86_64 ;;
    arm64) wasmtime_arch=aarch64 ;;
    *) echo >&2 "unsupported architecture '${dpkg_arch}'" && exit 1 ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://github.com/bytecodealliance/wasmtime/releases/download/v${WASMTIME_VERSION}/wasmtime-v${WASMTIME_VERSION}-${wasmtime_arch}-linux.tar.xz" \
    | tar xJf - --strip-components 1 -C /usr/local/bin "wasmtime-v${WASMTIME_VERSION}-x86_64-linux/wasmtime"
EOF
ARG RUST_TARGET
COPY /test-base /test-base
RUN /test-base/target.sh
COPY /test /test

FROM test-base as test-relocated
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh clang
RUN touch /DONE

FROM test-base as test
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN /test/test.sh clang
# COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
