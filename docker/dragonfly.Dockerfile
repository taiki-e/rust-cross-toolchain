# syntax=docker/dockerfile:1.3-labs

ARG UBUNTU_VERSION=18.04
ARG ALPINE_VERSION=3.15

# https://mirror-master.dragonflybsd.org/iso-images
ARG DRAGONFLY_VERSION=6.0.1

FROM ghcr.io/taiki-e/downloader as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p "${SYSROOT_DIR}"

ARG DRAGONFLY_VERSION
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 "https://mirror-master.dragonflybsd.org/iso-images/dfly-x86_64-${DRAGONFLY_VERSION}_REL.iso.bz2" \
        | bsdtar xjf - -C "${SYSROOT_DIR}" ./lib ./usr/include ./usr/lib

COPY /clang-cross.sh /
ARG GCC_VERSION=8.0
RUN COMMON_FLAGS="-B\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib/gcc${GCC_VERSION/./} -B\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib -L\"\${toolchain_dir}\"/${RUST_TARGET}/lib -L\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib -L\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib/gcc${GCC_VERSION/./}" \
    CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/usr/include/c++/${GCC_VERSION} -I\"\${toolchain_dir}\"/${RUST_TARGET}/usr/include/g++" \
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
ARG DRAGONFLY_VERSION
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh clang
RUN touch /DONE

FROM test-base as test
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG DRAGONFLY_VERSION
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN /test/test.sh clang
COPY --from=test-relocated /DONE /

FROM alpine:"${ALPINE_VERSION}" as final
SHELL ["/bin/sh", "-eux", "-c"]
RUN apk --no-cache add bash
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
