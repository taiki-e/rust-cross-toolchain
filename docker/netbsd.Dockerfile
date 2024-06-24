# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

# Refs:
# - https://github.com/rust-lang/rust/blob/c4f112af6e503c2b3e908af7dddd1b8ea99ed60c/src/doc/rustc/src/platform-support/netbsd.md
# - https://github.com/rust-lang/rust/blob/1.66.0/src/ci/docker/host-x86_64/dist-x86_64-netbsd/build-netbsd-toolchain.sh

# When using clang:
# - aarch64, i686, and x86_64 work without gnu binutils.
# - sparc64 works with only gnu binutils.
# - others don't work without binutils built by build.sh (unrecognized emulation mode error).

ARG RUST_TARGET
ARG UBUNTU_VERSION=20.04
ARG TOOLCHAIN_TAG=dev
ARG HOST_ARCH=amd64

# See tools/build-docker.sh
ARG NETBSD_VERSION

FROM ghcr.io/taiki-e/rust-cross-toolchain:"${RUST_TARGET}${NETBSD_VERSION}-base${TOOLCHAIN_TAG:+"-${TOOLCHAIN_TAG}"}-${HOST_ARCH}" AS toolchain

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS builder
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
COPY --from=toolchain "${TOOLCHAIN_DIR}" "${TOOLCHAIN_DIR}"

# NB: When updating this, the reminder to update docker/base/netbsd.Dockerfile.
RUN <<EOF
case "${RUST_TARGET}" in
    aarch64-*) cc_target=aarch64--netbsd ;;
    aarch64_be-*) cc_target=aarch64_be--netbsd ;;
    armv6-*) cc_target=armv6--netbsdelf-eabihf ;;
    armv7-*) cc_target=armv7--netbsdelf-eabihf ;;
    i?86-*) cc_target=i486--netbsdelf ;;
    mipsel-*) cc_target=mipsel--netbsd ;;
    powerpc-*) cc_target=powerpc--netbsd ;;
    riscv32*) cc_target=riscv32--netbsd ;;
    riscv64*) cc_target=riscv64--netbsd ;;
    sparc-*) cc_target=sparc--netbsd ;;
    sparc64-*) cc_target=sparc64--netbsd ;;
    x86_64*) cc_target=x86_64--netbsd ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
echo "${cc_target}" >/CC_TARGET
EOF

ARG NETBSD_VERSION
RUN --mount=type=bind,target=/docker <<EOF
export CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/usr/include/g++"
if [[ "${NETBSD_VERSION}" == "8"* ]]; then
    export CXXFLAGS="-std=c++14 ${CXXFLAGS}"
fi
export COMMON_FLAGS="-L\"\${toolchain_dir}\"/${RUST_TARGET}/lib -L\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib"
/docker/clang-cross.sh
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS test-base
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG REAL_HOST_ARCH
COPY /test-base.sh /
RUN /test-base.sh
ARG RUST_TARGET
COPY /test-base /test-base
RUN /test-base/target.sh
COPY /test /test

FROM test-base AS test-relocated
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG NETBSD_VERSION
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh gcc
RUN /test/test.sh clang
RUN touch /DONE

FROM test-base AS test
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG NETBSD_VERSION
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN /test/test.sh gcc
RUN /test/test.sh clang
# COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" AS final
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
