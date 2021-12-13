# syntax=docker/dockerfile:1.3-labs

# Refs:
# - https://www.uclibc-ng.org
# - https://github.com/rust-lang/rust/blob/3d71e749a244890cd370d49963e747cf92f4a037/src/doc/rustc/src/platform-support/armv7-unknown-linux-uclibceabihf.md

ARG UBUNTU_VERSION=18.04

# https://toolchains.bootlin.com/releases_armv7-eabihf.html
# GCC 10.2.0, GDB 9.2, Linux headers 5.4.61, uClibc 1.0.34, binutils 2.34
ARG TOOLCHAIN_VERSION=2020.08-1
ARG GCC_VERSION=10.2.0

FROM ghcr.io/taiki-e/downloader as toolchain
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG RUST_TARGET
RUN mkdir -p /toolchain
ARG TOOLCHAIN_VERSION
RUN <<EOF
case "${RUST_TARGET}" in
    armv5te-*) arch=armv5-eabi ;;
    armv7-*hf) arch=armv7-eabihf ;;
    mips-*) arch=mips32 ;;
    mipsel-*) arch=mips32el ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://toolchains.bootlin.com/downloads/releases/toolchains/${arch}/tarballs/${arch}--uclibc--bleeding-edge-${TOOLCHAIN_VERSION}.tar.bz2" \
    | tar xjf - --strip-components 1 -C /toolchain
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
COPY --from=toolchain /toolchain "${TOOLCHAIN_DIR}"

RUN <<EOF
case "${RUST_TARGET}" in
    armv5te-*) cc_target=arm-buildroot-linux-uclibcgnueabi ;;
    armv7-*hf) cc_target=arm-buildroot-linux-uclibcgnueabihf ;;
    mips-*) cc_target=mips-buildroot-linux-uclibc ;;
    mipsel-*) cc_target=mipsel-buildroot-linux-uclibc ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
echo "${cc_target}" >/CC_TARGET
EOF

RUN <<EOF
cd "${TOOLCHAIN_DIR}"
cc_target="$(</CC_TARGET)"
orig_sysroot_dir="${cc_target}/sysroot"
dest_sysroot_dir="${cc_target}"
mkdir -p "${dest_sysroot_dir}"/usr/{include,lib} "${dest_sysroot_dir}"/lib
cp -r "${orig_sysroot_dir}"/usr/include/. "${dest_sysroot_dir}"/usr/include/
cp -r "${orig_sysroot_dir}"/usr/lib/. "${dest_sysroot_dir}"/usr/lib/
cp -r "${orig_sysroot_dir}"/lib/. "${dest_sysroot_dir}"/lib/
EOF

COPY /base/common.sh /
RUN /common.sh

# TODO(clang,uclibc): needed for clang
RUN <<EOF
cd "${SYSROOT_DIR}/lib"
case "${RUST_TARGET}" in
    armv5te-*) ln -s ld-uClibc.so.0 ld-linux.so.3 ;;
    armv7-*hf) ln -s ld-uClibc.so.0 ld-linux-armhf.so.3 ;;
    mips-* | mipsel-*) ln -s ld-uClibc.so.0 ld.so.1 ;;
esac
EOF

COPY /clang-cross.sh /
ARG GCC_VERSION
RUN CC_TARGET="$(</CC_TARGET)" \
    COMMON_FLAGS="-B\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${GCC_VERSION} -L\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${GCC_VERSION}" \
    CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION} -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION}/${RUST_TARGET}" \
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
COPY --from=ghcr.io/taiki-e/qemu-user /usr/bin/qemu-* /usr/bin/

FROM test-base as test-relocated
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh gcc
RUN /test/test.sh clang
RUN touch /DONE

FROM test-base as test
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN /test/test.sh gcc
RUN /test/test.sh clang
COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
