# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

# Refs:
# - https://github.com/rust-lang/rust/blob/1.80.0/src/ci/docker/scripts/freebsd-toolchain.sh

ARG UBUNTU_VERSION=20.04

# See tools/build-docker.sh
ARG FREEBSD_VERSION
# https://ftp.gnu.org/gnu/binutils
ARG BINUTILS_VERSION=2.40

# TODO(fortran)

FROM ghcr.io/taiki-e/downloader AS binutils-src
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG BINUTILS_VERSION
RUN mkdir -p -- /binutils-src
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.gz" \
        | tar xzf - --strip-components 1 -C /binutils-src

FROM ghcr.io/taiki-e/downloader AS sysroot
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG RUST_TARGET
ARG FREEBSD_VERSION
RUN mkdir -p -- /sysroot
# Download FreeBSD libraries and header files.
# https://download.freebsd.org/ftp/releases
# - As of 14.1, base.txz for armv{6,7} is not distributed.
RUN <<EOF
case "${RUST_TARGET}" in
    aarch64-*) freebsd_arch=arm64/aarch64 ;;
    arm*) freebsd_arch=arm/"${RUST_TARGET%%-*}" ;;
    i?86-*) freebsd_arch=i386/i386 ;;
    powerpc*) freebsd_arch=powerpc/"${RUST_TARGET%%-*}" ;;
    riscv64*) freebsd_arch=riscv/riscv64 ;;
    x86_64*) freebsd_arch=amd64/amd64 ;;
    *) printf >&2 '%s\n' "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://download.freebsd.org/ftp/releases/${freebsd_arch}/${FREEBSD_VERSION}-RELEASE/base.txz" \
    | tar xJf - -C /sysroot ./lib ./usr/include ./usr/lib ./bin/freebsd-version
EOF

FROM ghcr.io/taiki-e/build-base:alpine AS builder
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p -- "${TOOLCHAIN_DIR}"
ARG FREEBSD_VERSION
RUN <<EOF
cc_target="${RUST_TARGET/riscv64gc/riscv64}${FREEBSD_VERSION%%.*}"
printf '%s\n' "${cc_target}" >/CC_TARGET
cd -- "${TOOLCHAIN_DIR}"
mkdir -p -- "${cc_target}"
ln -s -- "${cc_target}" "${RUST_TARGET}"
EOF

# riscv64: ld.lld: error: hello.c:(.text+0x0): relocation R_RISCV_ALIGN requires unimplemented linker relaxation; recompile with -mno-relax
COPY --from=binutils-src /binutils-src /tmp/binutils-src
RUN --mount=type=bind,target=/docker <<EOF
case "${RUST_TARGET}" in
    riscv64*) CC_TARGET="$(</CC_TARGET)" /docker/base/build-binutils.sh ;;
esac
EOF

COPY --from=sysroot /sysroot/. "${SYSROOT_DIR}"
# libc refers freebsd-version command.
# This is currently only enabled for their test, but may change in the future.
# https://github.com/rust-lang/libc/blob/0.2.158/build.rs#L252
# https://github.com/rust-lang/libc/issues/2061
# https://github.com/rust-lang/libc/issues/570
# https://github.com/rust-lang/libc/pull/2581
RUN mv -- "${SYSROOT_DIR}/bin" "${TOOLCHAIN_DIR}/bin"

RUN --mount=type=bind,target=/docker <<EOF
case "${RUST_TARGET}" in
    riscv64*)
        COMMON_FLAGS="--ld-path=\"\${toolchain_dir}\"/bin/$(</CC_TARGET)-ld" \
            /docker/clang-cross.sh
        ;;
    *)
        COMMON_FLAGS="-fuse-ld=lld" \
            /docker/clang-cross.sh
        ;;
esac
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS test-base
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
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
ARG FREEBSD_VERSION
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh clang
RUN touch -- /DONE

FROM test-base AS test
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG FREEBSD_VERSION
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
