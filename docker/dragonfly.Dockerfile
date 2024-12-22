# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

ARG UBUNTU_VERSION=20.04

# See tools/build-docker.sh
ARG DRAGONFLY_VERSION

# TODO(fortran)

FROM ghcr.io/taiki-e/downloader AS sysroot
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DRAGONFLY_VERSION
RUN mkdir -p -- /sysroot
# https://mirror-master.dragonflybsd.org/iso-images's certificate has expired...
# https://cdimage.debian.org/mirror/dragonflybsd.org/iso-images
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://cdimage.debian.org/mirror/dragonflybsd.org/iso-images/dfly-x86_64-${DRAGONFLY_VERSION}_REL.iso.bz2" \
        | bsdtar xjf - -C /sysroot ./lib ./usr/include ./usr/lib

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS builder
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p -- "${SYSROOT_DIR}"
COPY --from=sysroot /sysroot/. "${SYSROOT_DIR}"

RUN --mount=type=bind,target=/docker <<EOF
gcc_version=8.0
COMMON_FLAGS="-fuse-ld=lld -B\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib/gcc${gcc_version/./} -B\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib -L\"\${toolchain_dir}\"/${RUST_TARGET}/lib -L\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib -L\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib/gcc${gcc_version/./}" \
    CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/usr/include/c++/${gcc_version} -I\"\${toolchain_dir}\"/${RUST_TARGET}/usr/include/g++" \
    /docker/clang-cross.sh
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS test-base
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG REAL_HOST_ARCH
COPY /test-base.sh /
RUN /test-base.sh
ARG RUST_TARGET
COPY /test-base /test-base
RUN /test-base/target.sh
COPY /test /test

FROM test-base AS test-relocated
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG DRAGONFLY_VERSION
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh clang
RUN touch -- /DONE

FROM test-base AS test
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG DRAGONFLY_VERSION
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN /test/test.sh clang
# COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" AS final
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
