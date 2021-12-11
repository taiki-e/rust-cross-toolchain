# syntax=docker/dockerfile:1.3-labs

# Refs:
# - https://github.com/rust-lang/rust/blob/27143a9094b55a00d5f440b05b0cb4233b300d33/src/ci/docker/scripts/illumos-toolchain.sh.
# - https://github.com/illumos/sysroot

ARG RUST_TARGET
ARG UBUNTU_VERSION=18.04
ARG TOOLCHAIN_TAG=dev

FROM ghcr.io/taiki-e/rust-cross-toolchain:"${RUST_TARGET}-base${TOOLCHAIN_TAG:+"-${TOOLCHAIN_TAG}"}-amd64" as toolchain

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
COPY --from=toolchain "${TOOLCHAIN_DIR}" "${TOOLCHAIN_DIR}"

ARG GCC_VERSION=8.5.0
COPY /clang-cross.sh /
RUN COMMON_FLAGS="--gcc-toolchain=\"\${toolchain_dir}\"" \
    CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION} -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION}/${RUST_TARGET}" \
    /clang-cross.sh

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
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh gcc
RUN /test/test.sh clang
RUN touch /DONE

FROM test-base as test
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN /test/test.sh gcc
RUN /test/test.sh clang
COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
