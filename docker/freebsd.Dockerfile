# syntax=docker/dockerfile:1.3-labs

# Refs:
# - https://github.com/rust-lang/rust/blob/27143a9094b55a00d5f440b05b0cb4233b300d33/src/ci/docker/scripts/freebsd-toolchain.sh.

ARG UBUNTU_VERSION=18.04

# See tools/build-docker.sh
ARG FREEBSD_VERSION
# https://ftp.gnu.org/gnu/binutils
ARG BINUTILS_VERSION=2.37

FROM ghcr.io/taiki-e/downloader as binutils-src
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG BINUTILS_VERSION
RUN mkdir -p /binutils-src
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.gz" \
        | tar xzf - --strip-components 1 -C /binutils-src

FROM ghcr.io/taiki-e/downloader as sysroot
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG RUST_TARGET
ARG FREEBSD_VERSION
RUN mkdir -p /sysroot
# Download FreeBSD libraries and header files.
# https://download.freebsd.org/ftp/releases
# - As of 13.0, base.txz for arm* targets it is not distributed.
# - Use bsdtar to avoid "unknown extended header keyword" warning.
RUN <<EOF
case "${RUST_TARGET}" in
    aarch64-*) freebsd_arch=arm64/aarch64 ;;
    arm*) freebsd_arch="arm/${RUST_TARGET%%-*}" ;;
    i686-*) freebsd_arch=i386/i386 ;;
    powerpc*) freebsd_arch="powerpc/${RUST_TARGET%%-*}" ;;
    riscv64gc-*) freebsd_arch="riscv/riscv64" ;;
    x86_64-*) freebsd_arch=amd64/amd64 ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://download.freebsd.org/ftp/releases/${freebsd_arch}/${FREEBSD_VERSION}-RELEASE/base.txz" \
    | bsdtar xJf - -C /sysroot ./lib ./usr/include ./usr/lib ./bin/freebsd-version
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p "${TOOLCHAIN_DIR}"
ARG FREEBSD_VERSION
RUN <<EOF
cc_target="${RUST_TARGET/riscv64gc/riscv64}${FREEBSD_VERSION%%.*}"
echo "${cc_target}" >/CC_TARGET
cd "${TOOLCHAIN_DIR}"
mkdir -p "${cc_target}"
ln -s "${cc_target}" "${RUST_TARGET}"
EOF

# riscv64gc: ld.lld: error: hello.c:(.text+0x0): relocation R_RISCV_ALIGN requires unimplemented linker relaxation; recompile with -mno-relax
COPY --from=binutils-src /binutils-src /tmp/binutils-src
COPY /base/build-binutils.sh /
RUN <<EOF
case "${RUST_TARGET}" in
    riscv64gc-*) CC_TARGET="$(</CC_TARGET)" /build-binutils.sh ;;
esac
EOF

COPY --from=sysroot /sysroot/. "${SYSROOT_DIR}"
# libc refers freebsd-version command.
# This is currently only enabled for their test, but may change in the future.
# https://github.com/rust-lang/libc/blob/720652a95b9b5b9ee0f12563c55badf50bd0bdab/build.rs#L134
# https://github.com/rust-lang/libc/issues/2061
# https://github.com/rust-lang/libc/issues/570
# https://github.com/rust-lang/libc/pull/2581
RUN mv "${SYSROOT_DIR}/bin" "${TOOLCHAIN_DIR}/bin"

COPY /clang-cross.sh /
RUN <<EOF
case "${RUST_TARGET}" in
    riscv64gc-*)
        COMMON_FLAGS="--ld-path=\"\${toolchain_dir}\"/bin/$(</CC_TARGET)-ld" \
            /clang-cross.sh
        ;;
    *) /clang-cross.sh ;;
esac
EOF

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
ARG FREEBSD_VERSION
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh clang
RUN touch /DONE

FROM test-base as test
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG FREEBSD_VERSION
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN /test/test.sh clang
COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
