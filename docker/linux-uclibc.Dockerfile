# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

# Refs:
# - https://www.uclibc-ng.org
# - https://github.com/rust-lang/rust/blob/1.80.0/src/doc/rustc/src/platform-support/armv7-unknown-linux-uclibceabihf.md
# - https://github.com/rust-lang/rust/blob/1.80.0/src/doc/rustc/src/platform-support/armv7-unknown-linux-uclibceabi.md

ARG UBUNTU_VERSION=20.04

# TODO: update to 2021.11-1 or 2022.08-1
# https://toolchains.bootlin.com/toolchains.html
# NB: When updating this, the reminder to update uClibc-ng/GCC version in README.md.
ARG TOOLCHAIN_VERSION=2020.08-1

FROM ghcr.io/taiki-e/downloader AS toolchain
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG RUST_TARGET
RUN mkdir -p /toolchain
ARG TOOLCHAIN_VERSION
# https://toolchains.bootlin.com/toolchains.html
RUN <<EOF
case "${RUST_TARGET}" in
    aarch64-*) arch=aarch64 ;;
    aarch64_be-*) arch=aarch64be ;;
    armv6-*hf) arch=armv6-eabihf ;;
    armv7-*hf) arch=armv7-eabihf ;;
    arm*) arch=armv5-eabi ;;
    mips-*) arch=mips32 ;;
    mipsel-*) arch=mips32el ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://toolchains.bootlin.com/downloads/releases/toolchains/${arch}/tarballs/${arch}--uclibc--bleeding-edge-${TOOLCHAIN_VERSION}.tar.bz2" \
    | tar xjf - --strip-components 1 -C /toolchain
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS builder
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
COPY --from=toolchain /toolchain "${TOOLCHAIN_DIR}"

RUN <<EOF
case "${RUST_TARGET}" in
    aarch64-*) cc_target=aarch64-buildroot-linux-uclibc ;;
    aarch64_be-*) cc_target=aarch64_be-buildroot-linux-uclibc ;;
    arm*hf) cc_target=arm-buildroot-linux-uclibcgnueabihf ;;
    arm*) cc_target=arm-buildroot-linux-uclibcgnueabi ;;
    mips-*) cc_target=mips-buildroot-linux-uclibc ;;
    mipsel-*) cc_target=mipsel-buildroot-linux-uclibc ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
echo "${cc_target}" >/CC_TARGET
EOF

RUN <<EOF
cd "${TOOLCHAIN_DIR}"
cc_target=$(</CC_TARGET)
orig_sysroot_dir="${cc_target}/sysroot"
dest_sysroot_dir="${cc_target}"
mkdir -p "${dest_sysroot_dir}"/usr/{include,lib} "${dest_sysroot_dir}"/lib
cp -r "${orig_sysroot_dir}"/usr/include/. "${dest_sysroot_dir}"/usr/include/
cp -r "${orig_sysroot_dir}"/usr/lib/. "${dest_sysroot_dir}"/usr/lib/
cp -r "${orig_sysroot_dir}"/lib/. "${dest_sysroot_dir}"/lib/
EOF

RUN --mount=type=bind,target=/docker \
    /docker/base/common.sh

RUN --mount=type=bind,target=/docker <<EOF
gcc_version=$("${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-gcc" --version | sed -n '1 s/^.*) //p')
CC_TARGET="$(</CC_TARGET)" \
    COMMON_FLAGS="-B\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${gcc_version} -L\"\${toolchain_dir}\"/lib/gcc/${RUST_TARGET}/${gcc_version}" \
    CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version} -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version}/${RUST_TARGET}" \
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
COPY --from=ghcr.io/taiki-e/qemu-user /usr/bin/qemu-* /usr/bin/

FROM test-base AS test-relocated
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh gcc
RUN /test/test.sh clang
RUN touch /DONE

FROM test-base AS test
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
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
