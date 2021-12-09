# syntax=docker/dockerfile:1.3-labs

# Refs:
# - https://github.com/rust-lang/rust/blob/27143a9094b55a00d5f440b05b0cb4233b300d33/src/ci/docker/host-x86_64/dist-x86_64-netbsd/build-netbsd-toolchain.sh

ARG UBUNTU_VERSION=18.04
ARG ALPINE_VERSION=3.15

# https://www.netbsd.org/releases
ARG NETBSD_VERSION=9.2

FROM ghcr.io/taiki-e/downloader as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p "${SYSROOT_DIR}"

ARG NETBSD_VERSION
# https://ftp.netbsd.org/pub/NetBSD
# https://wiki.netbsd.org/ports
RUN <<EOF
case "${RUST_TARGET}" in
    aarch64-*) netbsd_arch=evbarm-aarch64 ;;
    armv6-*) netbsd_arch=evbarm-earmv6hf ;;
    armv7-*) netbsd_arch=evbarm-earmv7hf ;;
    i686-*) netbsd_arch=i386 ;;
    powerpc-*) netbsd_arch=evbppc ;;
    sparc64-*) netbsd_arch=sparc64 ;;
    x86_64-*) netbsd_arch=amd64 ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
case "${RUST_TARGET}" in
    sparc64-* | x86_64-*)
        curl --proto '=https' --tlsv1.2 -fsSL --retry 10 "https://ftp.netbsd.org/pub/NetBSD/NetBSD-${NETBSD_VERSION}/${netbsd_arch}/binary/sets/base.tar.xz" \
            | tar xJf - -C "${SYSROOT_DIR}" ./lib ./usr/include ./usr/lib
        curl --proto '=https' --tlsv1.2 -fsSL --retry 10 "https://ftp.netbsd.org/pub/NetBSD/NetBSD-${NETBSD_VERSION}/${netbsd_arch}/binary/sets/comp.tar.xz" \
            | tar xJf - -C "${SYSROOT_DIR}" ./usr/include ./usr/lib
        ;;
    *)
        curl --proto '=https' --tlsv1.2 -fsSL --retry 10 "https://ftp.netbsd.org/pub/NetBSD/NetBSD-${NETBSD_VERSION}/${netbsd_arch}/binary/sets/base.tgz" \
            | tar xzf - -C "${SYSROOT_DIR}" ./lib ./usr/include ./usr/lib
        curl --proto '=https' --tlsv1.2 -fsSL --retry 10 "https://ftp.netbsd.org/pub/NetBSD/NetBSD-${NETBSD_VERSION}/${netbsd_arch}/binary/sets/comp.tgz" \
            | tar xzf - -C "${SYSROOT_DIR}" ./usr/include ./usr/lib
        ;;
esac
EOF

COPY /clang-cross.sh /
RUN COMMON_FLAGS="-L\"\${toolchain_dir}\"/${RUST_TARGET}/lib -L\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib" \
    CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/usr/include/g++" \
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
ARG NETBSD_VERSION
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh clang
RUN touch /DONE

FROM test-base as test
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG NETBSD_VERSION
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
COPY --from=test /"${RUST_TARGET}-dev" /"${RUST_TARGET}-dev"
ENV PATH="/${RUST_TARGET}/bin:/${RUST_TARGET}-dev/bin:$PATH"
