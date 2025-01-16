# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

# Refs:
# - https://github.com/rust-lang/rust/blob/1.80.0/src/ci/docker/host-x86_64/dist-x86_64-netbsd/build-netbsd-toolchain.sh

# When using clang:
# - aarch64, i686, and x86_64 work without gnu binutils.
# - sparc64 works with only gnu binutils.
# - others don't work without binutils built by build.sh (unrecognized emulation mode error).

ARG UBUNTU_VERSION=18.04

# See tools/build-docker.sh
ARG NETBSD_VERSION

# TODO(fortran)

FROM ghcr.io/taiki-e/downloader AS build-src
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG NETBSD_VERSION
RUN mkdir -p -- /build-src
WORKDIR /build-src
RUN <<EOF
case "${NETBSD_VERSION}" in
    [1-8].*) base_url=https://archive.netbsd.org/pub/NetBSD-archive ;;
    *) base_url=https://ftp.netbsd.org/pub/NetBSD ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${base_url}/NetBSD-${NETBSD_VERSION}/source/sets/src.tgz" | tar xzf -
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${base_url}/NetBSD-${NETBSD_VERSION}/source/sets/gnusrc.tgz" | tar xzf -
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${base_url}/NetBSD-${NETBSD_VERSION}/source/sets/sharesrc.tgz" | tar xzf -
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${base_url}/NetBSD-${NETBSD_VERSION}/source/sets/syssrc.tgz" | tar xzf -
EOF
WORKDIR /

FROM ghcr.io/taiki-e/downloader AS sysroot
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG RUST_TARGET
ARG NETBSD_VERSION
RUN mkdir -p -- /sysroot
# https://ftp.netbsd.org/pub/NetBSD
# https://wiki.netbsd.org/ports
RUN <<EOF
case "${RUST_TARGET}" in
    aarch64-*) netbsd_arch=evbarm-aarch64 ;;
    aarch64_be-*) netbsd_arch=evbarm-aarch64eb ;;
    armv6-*) netbsd_arch=evbarm-earmv6hf ;;
    armv7-*) netbsd_arch=evbarm-earmv7hf ;;
    i?86-*) netbsd_arch=i386 ;;
    mipsel-*) netbsd_arch=evbmips-mipsel ;;
    powerpc-*) netbsd_arch=evbppc ;;
    riscv32*) netbsd_arch=riscv-riscv32 ;;
    riscv64*) netbsd_arch=riscv-riscv64 ;;
    sparc-*) netbsd_arch=sparc ;;
    sparc64-*) netbsd_arch=sparc64 ;;
    x86_64*) netbsd_arch=amd64 ;;
    *) printf >&2 '%s\n' "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
ext=tar.xz
case "${RUST_TARGET}" in
    sparc64-* | x86_64*)
        case "${NETBSD_VERSION}" in
            [1-8].*) ext=tgz ;;
        esac
        ;;
    aarch64-* | aarch64_be-*)
        case "${NETBSD_VERSION}" in
            [1-9].*) ext=tgz ;;
        esac
        ;;
    *) ext=tgz ;;
esac
case "${ext}" in
    tar.xz) cmd=xJf ;;
    *) cmd=xzf ;;
esac
case "${NETBSD_VERSION}" in
    [1-8].*) base_url=https://archive.netbsd.org/pub/NetBSD-archive ;;
    *) base_url=https://ftp.netbsd.org/pub/NetBSD ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${base_url}/NetBSD-${NETBSD_VERSION}/${netbsd_arch}/binary/sets/base.${ext}" \
    | tar "${cmd}" - -C /sysroot ./lib ./usr/include ./usr/lib
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${base_url}/NetBSD-${NETBSD_VERSION}/${netbsd_arch}/binary/sets/comp.${ext}" \
    | tar "${cmd}" - -C /sysroot ./usr/include ./usr/lib
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS builder
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get -o Acquire::Retries=10 -qq update && apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
    zlib1g-dev

ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p -- "${TOOLCHAIN_DIR}"

# NB: When updating this, the reminder to update docker/netbsd.Dockerfile.
ARG NETBSD_VERSION
RUN <<EOF
case "${RUST_TARGET}" in
    armv6-*) cc_target=armv6--netbsdelf-eabihf ;;
    armv7-*) cc_target=armv7--netbsdelf-eabihf ;;
    i?86-*) cc_target=i486--netbsdelf ;;
    riscv??gc-*) cc_target="${RUST_TARGET/gc-unknown-/--}" ;;
    *) cc_target="${RUST_TARGET/-unknown-/--}" ;;
esac
printf '%s\n' "${cc_target}" >/CC_TARGET
cd -- "${TOOLCHAIN_DIR}"
mkdir -p -- "${cc_target}"
ln -s -- "${cc_target}" "${RUST_TARGET}"
EOF

COPY --from=build-src /build-src /tmp/build-src
COPY --from=sysroot /sysroot/. "${SYSROOT_DIR}"
WORKDIR /tmp/build-src/usr/src
# https://www.netbsd.org/docs/guide/en/chap-build.html
RUN ./build.sh list-arch
RUN <<EOF
case "${RUST_TARGET}" in
    aarch64-*) args=(-m evbarm -a aarch64) ;;
    aarch64_be-*) args=(-m evbarm -a aarch64eb) ;;
    armv6-*) args=(-m evbarm -a earmv6hf) ;;
    armv7-*) args=(-m evbarm -a earmv7hf) ;;
    i?86-*) args=(-m i386) ;;
    mipsel-*) args=(-m evbmips -a mipsel) ;;
    powerpc-*) args=(-m evbppc) ;;
    riscv32*) args=(-m riscv -a riscv32) ;;
    riscv64*) args=(-m riscv -a riscv64) ;;
    sparc-*) args=(-m sparc) ;;
    sparc64-*) args=(-m sparc64) ;;
    x86_64*) args=(-m amd64) ;;
    *) printf >&2 '%s\n' "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
MKUNPRIVED=yes TOOLDIR="${TOOLCHAIN_DIR}" \
    MKSHARE=no MKDOC=no MKHTML=no MKINFO=no MKKMOD=no MKLINT=no MKMAN=no MKNLS=no MKPROFILE=no \
    ./build.sh -j"$(nproc)" "${args[@]}" tools &>build.log || (tail <build.log -5000 && exit 1)
EOF
RUN rm -rf -- "${TOOLCHAIN_DIR}"/man
WORKDIR /

RUN <<EOF
case "${RUST_TARGET}" in
    armv7-*) common_flags=" -march=armv7-a -mthumb -mfpu=vfpv3-d16 -mfloat-abi=hard" ;;
    mips-* | mipsel-*) common_flags=" -march=mips32r2" ;;
esac
cc_target=$(</CC_TARGET)
cat >"${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-gcc" <<EOF2
#!/bin/sh
set -eu
toolchain_dir="\$(cd -- "\$(dirname -- "\$0")"/.. && pwd)"
exec "\${toolchain_dir}"/bin/${cc_target}-gcc${common_flags:-} --sysroot="\${toolchain_dir}"/${RUST_TARGET} "\$@"
EOF2
cat >"${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-g++" <<EOF2
#!/bin/sh
set -eu
toolchain_dir="\$(cd -- "\$(dirname -- "\$0")"/.. && pwd)"
exec "\${toolchain_dir}"/bin/${cc_target}-g++${common_flags:-} --sysroot="\${toolchain_dir}"/${RUST_TARGET} "\$@"
EOF2
chmod +x "${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-gcc" "${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-g++"
EOF

RUN --mount=type=bind,target=/base \
    /base/common.sh

FROM ubuntu:"${UBUNTU_VERSION}" AS final
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
