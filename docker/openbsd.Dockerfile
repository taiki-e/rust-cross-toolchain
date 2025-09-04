# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

# Refs:
# - https://github.com/rust-lang/rust/blob/1.84.0/src/doc/rustc/src/platform-support/openbsd.md

ARG UBUNTU_VERSION=20.04

# See tools/build-docker.sh
ARG OPENBSD_VERSION
# https://ftp.gnu.org/gnu/binutils
ARG BINUTILS_VERSION=2.37

FROM ghcr.io/taiki-e/downloader AS binutils-src
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG BINUTILS_VERSION
RUN mkdir -p -- /binutils-src
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz" \
        | tar xJf - --strip-components 1 -C /binutils-src

FROM ghcr.io/taiki-e/downloader AS sysroot
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG RUST_TARGET
ARG OPENBSD_VERSION
RUN mkdir -p -- /sysroot
# Download OpenBSD libraries and header files.
# https://cdn.openbsd.org/pub/OpenBSD
# https://www.openbsd.org/plat.html
RUN <<EOF
case "${RUST_TARGET}" in
    aarch64-*) openbsd_arch=arm64 ;;
    armv7-*) openbsd_arch=armv7 ;;
    i?86-*) openbsd_arch=i386 ;;
    mips64-*) openbsd_arch=octeon ;;
    powerpc-*) openbsd_arch=macppc ;;
    powerpc64-*) openbsd_arch=powerpc64 ;;
    riscv64*) openbsd_arch=riscv64 ;;
    sparc64-*) openbsd_arch=sparc64 ;;
    x86_64*) openbsd_arch=amd64 ;;
    *) printf >&2 '%s\n' "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://cdn.openbsd.org/pub/OpenBSD/${OPENBSD_VERSION}/${openbsd_arch}/base${OPENBSD_VERSION/./}.tgz" \
    | tar xzf - -C /sysroot ./usr/include ./usr/lib
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://cdn.openbsd.org/pub/OpenBSD/${OPENBSD_VERSION}/${openbsd_arch}/comp${OPENBSD_VERSION/./}.tgz" \
    | tar xzf - -C /sysroot ./usr/include ./usr/lib
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS builder
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p -- "${TOOLCHAIN_DIR}"
ARG OPENBSD_VERSION
RUN <<EOF
case "${RUST_TARGET}" in
    riscv??gc-*) cc_target="${RUST_TARGET/gc/}${OPENBSD_VERSION}" ;;
    *) cc_target="${RUST_TARGET}${OPENBSD_VERSION}" ;;
esac
printf '%s\n' "${cc_target}" >/CC_TARGET
cd -- "${TOOLCHAIN_DIR}"
mkdir -p -- "${cc_target}"
ln -s -- "${cc_target}" "${RUST_TARGET}"
EOF

# sparc64: ld.lld: error: relocation R_SPARC_64 cannot be used against local symbol; recompile with -fPIC
#          maybe https://bugs.llvm.org/show_bug.cgi?id=42446
RUN --mount=type=bind,from=binutils-src,source=/binutils-src,target=/tmp/binutils-src \
    --mount=type=bind,source=./base/build-binutils.sh,target=/tmp/build-binutils.sh <<EOF
case "${RUST_TARGET}" in
    sparc64-*) CC_TARGET="$(</CC_TARGET)" /tmp/build-binutils.sh ;;
esac
EOF

COPY --from=sysroot /sysroot/. "${SYSROOT_DIR}"

RUN --mount=type=bind,source=./clang-cross.sh,target=/tmp/clang-cross.sh <<EOF
case "${RUST_TARGET}" in
    sparc64-*)
        # sparc64-unknown-openbsd uses libstdc++ and libgcc (https://github.com/rust-lang/rust/pull/63595)
        gcc_version=4.2.1
        # export CFLAGS_LAST="-stdlib=libstdc++"
        # export CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/usr/include/g++ -I\"\${toolchain_dir}\"/${RUST_TARGET}/usr/include/g++/${RUST_TARGET}${OPENBSD_VERSION}"
        # export CXXFLAGS_LAST="-stdlib=libstdc++ -lstdc++ -lgcc"
        COMMON_FLAGS="--ld-path=\"\${toolchain_dir}\"/bin/$(</CC_TARGET)-ld -L\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib -L\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib/gcc-lib/${RUST_TARGET}${OPENBSD_VERSION}/${gcc_version} -B\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib/gcc-lib/${RUST_TARGET}${OPENBSD_VERSION}/${gcc_version}" \
            /tmp/clang-cross.sh
        ;;
    *)
        COMMON_FLAGS="-fuse-ld=lld -L\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib" \
            /tmp/clang-cross.sh
        ;;
esac
EOF

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
ENV PATH="/${RUST_TARGET}/bin:$PATH"
