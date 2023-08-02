# syntax=docker/dockerfile:1

# Refs:
# - https://github.com/mstorsjo/llvm-mingw
# - https://github.com/rust-lang/rust/blob/1.70.0/src/doc/rustc/src/platform-support/pc-windows-gnullvm.md

ARG RUST_TARGET
ARG UBUNTU_VERSION=20.04
ARG TOOLCHAIN_TAG=dev

ARG TOOLCHAIN_VERSION=20230614

FROM ghcr.io/taiki-e/downloader as toolchain
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
RUN mkdir -p /toolchain
ARG TOOLCHAIN_VERSION
# https://github.com/mstorsjo/llvm-mingw/releases
RUN <<EOF
dpkg_arch="$(dpkg --print-architecture)"
case "${dpkg_arch##*-}" in
    amd64) arch=x86_64 ;;
    arm64) arch=aarch64 ;;
    *) echo >&2 "unsupported architecture '${dpkg_arch}'" && exit 1 ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://github.com/mstorsjo/llvm-mingw/releases/download/${TOOLCHAIN_VERSION}/llvm-mingw-${TOOLCHAIN_VERSION}-ucrt-ubuntu-20.04-${arch}.tar.xz" \
    | tar xJf - --strip-components 1 -C /toolchain
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
COPY --from=toolchain /toolchain "${TOOLCHAIN_DIR}"

RUN <<EOF
cc_target="${RUST_TARGET%%-*}-w64-mingw32"
echo "${cc_target}" >/CC_TARGET
[[ "${RUST_TARGET}" == "aarch64"* ]] || rm -rf "${TOOLCHAIN_DIR}"/aarch64-w64-mingw32
[[ "${RUST_TARGET}" == "x86_64"* ]] || rm -rf "${TOOLCHAIN_DIR}"/x86_64-w64-mingw32
[[ "${RUST_TARGET}" == "i686"* ]] || rm -rf "${TOOLCHAIN_DIR}"/i686-w64-mingw32
{ [[ "${RUST_TARGET}" == "thumb"* ]] || [[ "${RUST_TARGET}" == "arm"* ]]; } || rm -rf "${TOOLCHAIN_DIR}"/armv7-w64-mingw32
EOF

RUN --mount=type=bind,target=/docker \
    /docker/base/common.sh

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as test-base
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ENV HOME=/tmp/home
COPY /test-base.sh /
RUN /test-base.sh
ARG RUST_TARGET
RUN <<EOF
dpkg_arch="$(dpkg --print-architecture)"
case "${dpkg_arch##*-}" in
    amd64) dpkg --add-architecture i386 ;;
    arm64)
        dpkg --add-architecture armhf
        # TODO: do not skip if actual host is arm64
        exit 0
        ;;
    *) echo >&2 "unsupported architecture '${dpkg_arch}'" && exit 1 ;;
esac
case "${RUST_TARGET}" in
    aarch64*) ;;
    *)
        # See https://wiki.winehq.org/Ubuntu when install the latest wine.
        apt-get -o Acquire::Retries=10 update -qq && apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
            wine-stable \
            wine32 \
            wine64
        wine --version
        ;;
esac
EOF
COPY --from=ghcr.io/taiki-e/qemu-user /usr/bin/qemu-aarch64 /usr/bin/
COPY --from=linaro/wine-arm64 /opt/wine-arm64 /opt/wine-arm64
RUN <<EOF
case "${RUST_TARGET}" in
    aarch64*) rm -rf /opt/wine-arm64/wine-prefix ;;
    *)
        rm -rf /opt/wine-arm64
        mkdir -p /opt/wine-arm64
        ;;
esac
EOF
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
COPY --from=test /opt/wine-arm64 /opt/wine-arm64
ENV PATH="/${RUST_TARGET}/bin:$PATH"
