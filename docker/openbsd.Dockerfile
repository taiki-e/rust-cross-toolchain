# syntax=docker/dockerfile:1.3-labs

ARG UBUNTU_VERSION=18.04

# OpenBSD does not have binary compatibility with previous releases.
# For now, we select the latest version of OpenBSD.
# https://github.com/rust-lang/libc/issues/570
# https://github.com/golang/go/issues/15227
# https://github.com/golang/go/wiki/OpenBSD
# https://github.com/golang/go/wiki/MinimumRequirements#openbsd
ARG OPENBSD_VERSION=7.0

FROM ghcr.io/taiki-e/downloader as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p "${TOOLCHAIN_DIR}"

ARG OPENBSD_VERSION
RUN <<EOF
cc_target="${RUST_TARGET}${OPENBSD_VERSION}"
echo "${cc_target}" >/CC_TARGET
cd "${TOOLCHAIN_DIR}"
mkdir -p "${cc_target}"
ln -s "${cc_target}" "${RUST_TARGET}"
EOF

# Download OpenBSD libraries and header files.
# https://cdn.openbsd.org/pub/OpenBSD
RUN <<EOF
case "${RUST_TARGET}" in
    aarch64-*) openbsd_arch=arm64 ;;
    i686-*) openbsd_arch=i386 ;;
    powerpc-*) openbsd_arch=macppc ;;
    sparc64-*) openbsd_arch=sparc64 ;;
    x86_64-*) openbsd_arch=amd64 ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 "https://cdn.openbsd.org/pub/OpenBSD/${OPENBSD_VERSION}/${openbsd_arch}/base${OPENBSD_VERSION/./}.tgz" \
    | tar xzf - -C "${SYSROOT_DIR}" ./usr/include ./usr/lib
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 "https://cdn.openbsd.org/pub/OpenBSD/${OPENBSD_VERSION}/${openbsd_arch}/comp${OPENBSD_VERSION/./}.tgz" \
    | tar xzf - -C "${SYSROOT_DIR}" ./usr/include ./usr/lib
EOF

COPY /clang-cross.sh /
# TODO(sparc64-unknown-openbsd):
#   sparc64-unknown-openbsd uses libstdc++ and libgcc (https://github.com/rust-lang/rust/pull/63595),
#   so it seems difficult to compile with clang and lld.
#       GCC_VERSION=4.2.1
#       common_flags="-L\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib/gcc-lib/${RUST_TARGET}${OPENBSD_VERSION}/${GCC_VERSION} -B\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib/gcc-lib/${RUST_TARGET}${OPENBSD_VERSION}/${GCC_VERSION}"
#       export CFLAGS_LAST="-stdlib=libstdc++"
#       export CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/usr/include/g++ -I\"\${toolchain_dir}\"/${RUST_TARGET}/usr/include/g++/${RUST_TARGET}${OPENBSD_VERSION}"
#       export CXXFLAGS_LAST="-stdlib=libstdc++ -lstdc++ -lgcc"
#   $ sparc64-unknown-openbsd-clang -o c.out hello.c # Ok
#   $ sparc64-unknown-openbsd-clang++ -o cpp.out hello.cpp
#      ld.lld: error: undefined symbol: main
#   $ cargo build -Z build-std --offline --target sparc64-unknown-openbsd
#      ld.lld: error: relocation R_SPARC_64 cannot be used against local symbol; recompile with -fPIC
#   https://bugs.llvm.org/show_bug.cgi?id=42446
RUN COMMON_FLAGS="-L\"\${toolchain_dir}\"/${RUST_TARGET}/usr/lib" \
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
COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
