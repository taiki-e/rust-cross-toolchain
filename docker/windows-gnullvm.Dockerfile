# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

# Refs:
# - https://github.com/mstorsjo/llvm-mingw
# - https://github.com/rust-lang/rust/blob/1.84.0/src/doc/rustc/src/platform-support/pc-windows-gnullvm.md

ARG RUST_TARGET
ARG UBUNTU_VERSION=22.04
ARG TOOLCHAIN_TAG=dev

# https://github.com/mstorsjo/llvm-mingw/releases
# NB: When updating this, the reminder to update Clang/Mingw version in README.md.
ARG TOOLCHAIN_VERSION=20240619

FROM ghcr.io/taiki-e/downloader AS toolchain
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
RUN mkdir -p -- /toolchain
ARG TOOLCHAIN_VERSION
RUN <<EOF
dpkg_arch=$(dpkg --print-architecture)
case "${dpkg_arch##*-}" in
    amd64) arch=x86_64 ;;
    arm64) arch=aarch64 ;;
    *) printf >&2 '%s\n' "unsupported architecture '${dpkg_arch}'" && exit 1 ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://github.com/mstorsjo/llvm-mingw/releases/download/${TOOLCHAIN_VERSION}/llvm-mingw-${TOOLCHAIN_VERSION}-ucrt-ubuntu-20.04-${arch}.tar.xz" \
    | tar xJf - --strip-components 1 -C /toolchain
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS builder
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
COPY --from=toolchain /toolchain "${TOOLCHAIN_DIR}"

RUN <<EOF
cc_target="${RUST_TARGET%%-*}-w64-mingw32"
printf '%s\n' "${cc_target}" >/CC_TARGET
[[ "${RUST_TARGET}" == "aarch64"* ]] || rm -rf -- "${TOOLCHAIN_DIR}"/aarch64-w64-mingw32
[[ "${RUST_TARGET}" == "x86_64"* ]] || rm -rf -- "${TOOLCHAIN_DIR}"/x86_64-w64-mingw32
[[ "${RUST_TARGET}" == "i686"* ]] || rm -rf -- "${TOOLCHAIN_DIR}"/i686-w64-mingw32
{ [[ "${RUST_TARGET}" == "thumb"* ]] || [[ "${RUST_TARGET}" == "arm"* ]]; } || rm -rf -- "${TOOLCHAIN_DIR}"/armv7-w64-mingw32
EOF

RUN --mount=type=bind,source=./base/common.sh,target=/tmp/common.sh \
    /tmp/common.sh

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS test-base
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ENV HOME=/tmp/home
RUN --mount=type=bind,source=./test-base.sh,target=/tmp/test-base.sh \
    /tmp/test-base.sh
ARG RUST_TARGET
RUN <<EOF
case "${RUST_TARGET}" in
    aarch64* | arm64*) exit 0 ;;
esac
dpkg_arch=$(dpkg --print-architecture)
case "${dpkg_arch##*-}" in
    amd64) dpkg --add-architecture i386 ;;
    arm64)
        # dpkg --add-architecture armhf
        # TODO: do not skip if actual host is arm64
        exit 0
        ;;
    *) printf >&2 '%s\n' "unsupported architecture '${dpkg_arch}'" && exit 1 ;;
esac
# Install the latest wine: https://wiki.winehq.org/Ubuntu
codename=$(grep -E '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2)
# shellcheck disable=SC2174
mkdir -pm755 -- /etc/apt/keyrings
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused https://dl.winehq.org/wine-builds/winehq.key \
    | tee -- /etc/apt/keyrings/winehq-archive.key >/dev/null
curl --proto '=https' --tlsv1.2 -fsSLR --retry 10 --retry-connrefused "https://dl.winehq.org/wine-builds/ubuntu/dists/${codename}/winehq-${codename}.sources" \
    | tee -- "/etc/apt/sources.list.d/winehq-${codename}.sources" >/dev/null
apt-get -o Acquire::Retries=10 -qq update && apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
    winehq-stable
# apt-get -o Acquire::Retries=10 -qq update && apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
#     wine \
#     wine32 \
#     wine64
wine --version
EOF
COPY --from=ghcr.io/taiki-e/qemu-user /usr/bin/qemu-aarch64 /usr/bin/
# https://www.linaro.org/blog/emulate-windows-on-arm
COPY --from=linaro/wine-arm64 /opt/wine-arm64 /opt/wine-arm64
RUN <<EOF
case "${RUST_TARGET}" in
    aarch64* | arm64*) rm -rf -- /opt/wine-arm64/wine-prefix ;;
    *)
        rm -rf -- /opt/wine-arm64
        mkdir -p -- /opt/wine-arm64
        ;;
esac
EOF
RUN --mount=type=bind,source=./test-base,target=/test-base \
    /test-base/target.sh
COPY /test /test

FROM test-base AS test-relocated
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh clang
RUN touch -- /DONE

FROM test-base AS test
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
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
COPY --from=test /opt/wine-arm64 /opt/wine-arm64
ENV PATH="/${RUST_TARGET}/bin:$PATH"
