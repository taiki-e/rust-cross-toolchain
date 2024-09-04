# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

ARG UBUNTU_VERSION=20.04

# https://github.com/rust-lang/rust/blob/1.80.0/src/ci/docker/scripts/emscripten.sh
# NB: When updating this, the reminder to update emscripten version in README.md.
ARG EMSCRIPTEN_VERSION=2.0.5
ARG NODE_VERSION=12.18.1

FROM emscripten/emsdk:"${EMSCRIPTEN_VERSION}" AS emsdk

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS builder
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
COPY --from=emsdk /emsdk "${TOOLCHAIN_DIR}"

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS test-base
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG REAL_HOST_ARCH
COPY /test-base.sh /
RUN /test-base.sh
RUN apt-get -o Acquire::Retries=10 -qq update && apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
    libxml2 \
    python3
ARG RUST_TARGET
COPY /test-base /test-base
RUN /test-base/target.sh
COPY /test /test

FROM test-base AS test-relocated
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG NODE_VERSION
ENV EMSDK="/usr/local/${RUST_TARGET}"
ENV EM_CACHE="${EMSDK}/upstream/emscripten/cache"
ENV EMSDK_NODE="${EMSDK}/node/${NODE_VERSION}_64bit/bin/node"
ENV PATH="${EMSDK}:${EMSDK}/upstream/emscripten:${EMSDK}/node/${NODE_VERSION}_64bit/bin:$PATH"
# Note: `/"${RUST_TARGET}"/. /usr/local/` doesn't work
COPY --from=builder /"${RUST_TARGET}" /usr/local/"${RUST_TARGET}"
RUN /test/test.sh emcc
RUN touch /DONE

FROM test-base AS test
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG NODE_VERSION
ENV EMSDK="/${RUST_TARGET}"
ENV EM_CACHE="${EMSDK}/upstream/emscripten/cache"
ENV EMSDK_NODE="${EMSDK}/node/${NODE_VERSION}_64bit/bin/node"
ENV PATH="${EMSDK}:${EMSDK}/upstream/emscripten:${EMSDK}/node/${NODE_VERSION}_64bit/bin:$PATH"
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
RUN /test/check.sh
RUN /test/test.sh emcc
RUN node --version
# COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" AS final
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ARG NODE_VERSION
ENV EMSDK="/${RUST_TARGET}"
ENV EM_CACHE="${EMSDK}/upstream/emscripten/cache"
ENV EMSDK_NODE="${EMSDK}/node/${NODE_VERSION}_64bit/bin/node"
ENV PATH="${EMSDK}:${EMSDK}/upstream/emscripten:${EMSDK}/node/${NODE_VERSION}_64bit/bin:$PATH"
