# syntax=docker/dockerfile:1.3-labs

ARG UBUNTU_VERSION=18.04

# See tools/build-docker.sh
ARG DRAGONFLY_VERSION

FROM ghcr.io/taiki-e/downloader as sysroot
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DRAGONFLY_VERSION
RUN mkdir -p /sysroot
# https://mirror-master.dragonflybsd.org/iso-images
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://mirror-master.dragonflybsd.org/iso-images/dfly-x86_64-${DRAGONFLY_VERSION}_REL.iso.bz2" \
        | bsdtar xjf - -C /sysroot ./lib ./usr/include ./usr/lib

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p "${SYSROOT_DIR}"
COPY --from=sysroot /sysroot/. "${SYSROOT_DIR}"

COPY /clang-cross.sh /
ARG GCC_VERSION=8.0
RUN COMMON_FLAGS="-fuse-ld=lld -B\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib/gcc${GCC_VERSION/./} -B\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib -L\"\${toolchain_dir}\"/${RUST_TARGET}/lib -L\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib -L\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib/gcc${GCC_VERSION/./}" \
    CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/usr/include/c++/${GCC_VERSION} -I\"\${toolchain_dir}\"/${RUST_TARGET}/usr/include/g++" \
    /clang-cross.sh

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as test-base
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
COPY /test-base.sh /
RUN /test-base.sh
ARG RUST_TARGET
COPY /test-base /test-base
RUN /test-base/target.sh
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
# COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
