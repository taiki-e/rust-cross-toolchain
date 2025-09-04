# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

# Refs:
# - https://forums.windriver.com/t/vxworks-software-development-kit-sdk/43

# TODO:
# - https://github.com/search?q=%2Fd13321s3lxgewa.cloudfront.net%2F&type=code
# - SDK license about re-distribute

ARG UBUNTU_VERSION=22.04

FROM ghcr.io/taiki-e/downloader AS toolchain
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG RUST_TARGET
RUN mkdir -p -- /toolchain
# Download SDK.
# https://forums.windriver.com/t/vxworks-software-development-kit-sdk/43
RUN <<EOF
case "${RUST_TARGET}" in
    aarch64* | arm*)
        sdk_arch=raspberrypi4b
        sdk_version=1.7 # VxWorks 25.03
        ;;
    i?86-* | x86_64*)
        sdk_arch=qemu
        sdk_version=1.15 # VxWorks 25.03
        ;;
    riscv*)
        sdk_arch=sifive-hifive
        sdk_version=1.4 # VxWorks 24.03
        ;;
    *) printf >&2 '%s\n' "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://d13321s3lxgewa.cloudfront.net/wrsdk-vxworks7-${sdk_arch}-${sdk_version}.tar.bz2" \
    | tar xjf - --strip-components 1 -C /toolchain
EOF

# TODO: compiler is at toolchain/wrsdk-vxworks7-raspberrypi4b/vxsdk/host/x86_64-linux/bin/wr-cc

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS builder
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
COPY --from=toolchain /toolchain "${TOOLCHAIN_DIR}"

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS test-base
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=bind,source=./test-base.sh,target=/tmp/test-base.sh \
    /tmp/test-base.sh
ARG RUST_TARGET
RUN --mount=type=bind,source=./test-base,target=/test-base \
    /test-base/target.sh
COPY /test /test

FROM test-base AS test-relocated
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh wr-cc
RUN touch -- /DONE

FROM test-base AS test
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN /test/test.sh wr-cc
# COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" AS final
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
