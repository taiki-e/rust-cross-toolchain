#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -CeEuo pipefail
IFS=$'\n\t'
trap -- 's=$?; printf >&2 "%s\n" "${0##*/}:${LINENO}: \`${BASH_COMMAND}\` exit with ${s}"; exit ${s}' ERR

# Refs:
# - https://wiki.debian.org/Multiarch/Tuples
# - https://wiki.debian.org/ArmEabiPort
# - https://wiki.debian.org/ArmHardFloatPort
# - https://wiki.debian.org/Arm64Port
# - https://wiki.debian.org/PowerPCSPEPort
# - https://wiki.debian.org/RISC-V
# - https://wiki.debian.org/RISC-V/32
# - https://wiki.debian.org/Sparc32
# - https://wiki.debian.org/Sparc64

set -x

dpkg_arch=$(dpkg --print-architecture)
case "${RUST_TARGET}" in
  x86_64-unknown-linux-gnu)
    case "${dpkg_arch##*-}" in
      amd64)
        cc_target=x86_64-linux-gnu
        printf '%s\n' "${cc_target}" >/CC_TARGET
        printf '%s\n' "${cc_target}" >/APT_TARGET
        printf 'host\n' >/GCC_VERSION
        exit 0
        ;;
    esac
    ;;
  aarch64-unknown-linux-gnu)
    case "${dpkg_arch##*-}" in
      arm64)
        cc_target=aarch64-linux-gnu
        printf '%s\n' "${cc_target}" >/CC_TARGET
        printf '%s\n' "${cc_target}" >/APT_TARGET
        printf 'host\n' >/GCC_VERSION
        exit 0
        ;;
    esac
    ;;
  aarch64_be-unknown-linux-gnu)
    # Toolchains for aarch64_be-linux-gnu is not available in APT.
    # https://developer.arm.com/downloads/-/gnu-a
    # https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads
    # GCC 10.2.1, Linux header 4.20.13, glibc 2.31, binutils 2.35.1, GDB 10.1
    # Use 10.2-2020.11 instead of 10.3-2021.07 because 10.3-2021.07 requires glibc 2.33.
    arm_gcc_version=10.2-2020.11
    cc_target="${RUST_TARGET/-unknown/-none}"
    gcc_version=10.2.1
    printf '%s\n' "${cc_target}" >/CC_TARGET
    printf '%s\n' "${cc_target}" >/APT_TARGET
    printf '%s\n' "${gcc_version}" >/GCC_VERSION
    curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://developer.arm.com/-/media/Files/downloads/gnu-a/${arm_gcc_version}/binrel/gcc-arm-${arm_gcc_version}-x86_64-${cc_target}.tar.xz" \
      | tar xJf - --strip-components 1 -C "${TOOLCHAIN_DIR}"
    exit 0
    ;;
  armeb-unknown-linux-gnueabi | armeb-unknown-linux-gnueabihf)
    # Toolchains for armeb-linux-gnueabi{,hf} is not available in APT.
    # https://releases.linaro.org/components/toolchain/binaries
    cc_target="${RUST_TARGET/-unknown/}"
    toolchain_date=2019.12
    gcc_version=7.5.0
    printf '%s\n' "${cc_target}" >/CC_TARGET
    printf '%s\n' "${cc_target}" >/APT_TARGET
    printf '%s\n' "${gcc_version}" >/GCC_VERSION
    curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://releases.linaro.org/components/toolchain/binaries/${gcc_version%.*}-${toolchain_date}/${cc_target}/gcc-linaro-${gcc_version}-${toolchain_date}-x86_64_${cc_target}.tar.xz" \
      | tar xJf - --strip-components 1 -C "${TOOLCHAIN_DIR}"
    exit 0
    ;;
  arm-unknown-linux-gnueabihf)
    # Ubuntu's gcc-arm-linux-gnueabihf is v7
    # https://github.com/abhiTronix/raspberry-pi-cross-compilers/wiki/Cross-Compiler:-Installation-Instructions#b-download-binary
    # https://sourceforge.net/projects/raspberry-pi-cross-compilers/files/Raspberry%20Pi%20GCC%20Cross-Compiler%20Toolchains/Buster/
    cc_target=arm-linux-gnueabihf
    gcc_version=10.2.0
    codename=Buster
    printf '%s\n' "${cc_target}" >/CC_TARGET
    printf '%s\n' "${cc_target}" >/APT_TARGET
    printf '%s\n' "${gcc_version}" >/GCC_VERSION
    curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://sourceforge.net/projects/raspberry-pi-cross-compilers/files/Raspberry%20Pi%20GCC%20Cross-Compiler%20Toolchains/${codename}/GCC%20${gcc_version}/Raspberry%20Pi%201%2C%20Zero/cross-gcc-${gcc_version}-pi_0-1.tar.gz/download" \
      | tar xzf - --strip-components 1 -C "${TOOLCHAIN_DIR}"
    exit 0
    ;;
  riscv32gc-unknown-linux-gnu)
    # Toolchains for riscv32-linux-gnu is not available in APT.
    # https://github.com/riscv-collab/riscv-gnu-toolchain/releases
    # GCC 11.1.0, Linux header 5.10.5, glibc 2.33, binutils 2.37
    riscv_toolchain_version=2021.09.21
    cc_target=riscv32-unknown-linux-gnu
    gcc_version=11.1.0
    printf '%s\n' "${cc_target}" >/CC_TARGET
    printf '%s\n' "${cc_target}" >/APT_TARGET
    printf '%s\n' "${gcc_version}" >/GCC_VERSION
    curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/${riscv_toolchain_version}/riscv32-glibc-ubuntu-18.04-nightly-${riscv_toolchain_version}-nightly.tar.gz" \
      | tar xzf - --strip-components 1 -C "${TOOLCHAIN_DIR}"
    exit 0
    ;;
  loongarch64-unknown-linux-gnu)
    # Toolchains for loongarch64-linux-gnu is not available in APT.
    # https://github.com/loongson/build-tools/releases
    toolchain_date=2024.08.08
    cc_target="${RUST_TARGET}"
    binutils_version=2.43
    gcc_version=14.2.0
    glibc_version=2.40
    printf '%s\n' "${cc_target}" >/CC_TARGET
    printf '%s\n' "${cc_target}" >/APT_TARGET
    printf '%s\n' "${gcc_version}" >/GCC_VERSION
    curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://github.com/loongson/build-tools/releases/download/${toolchain_date}/x86_64-cross-tools-loongarch64-binutils_${binutils_version}-gcc_${gcc_version}-glibc_${glibc_version}.tar.xz" \
      | tar xJf - --strip-components 1 -C "${TOOLCHAIN_DIR}"
    (
      cd -- "${TOOLCHAIN_DIR}/${RUST_TARGET}"
      # for compatibility with old toolchain
      ln -s -- lib lib64
    )
    exit 0
    ;;
  csky-unknown-linux-gnuabiv2*)
    # https://github.com/rust-lang/rust/blob/1.84.0/src/doc/rustc/src/platform-support/csky-unknown-linux-gnuabiv2.md
    toolchain_source_id=1356021/1619528643136
    toolchain_date=20210423
    qemu_source_id=1689324918932
    qemu_date=20230714-0202
    cc_target=csky-linux-gnuabiv2
    gcc_version=6.3.0
    echo "${cc_target}" >/CC_TARGET
    echo "${cc_target}" >/APT_TARGET
    echo "${gcc_version}" >/GCC_VERSION
    curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://occ-oss-prod.oss-cn-hangzhou.aliyuncs.com/resource/${toolchain_source_id}/csky-linux-gnuabiv2-tools-x86_64-glibc-linux-4.9.56-${toolchain_date}.tar.gz" \
      | tar xzf - -C "${TOOLCHAIN_DIR}"
    curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://occ-oss-prod.oss-cn-hangzhou.aliyuncs.com/resource//${qemu_source_id}/xuantie-qemu-x86_64-Ubuntu-18.04-${qemu_date}.tar.gz" \
      | tar xzf - -C "${TOOLCHAIN_DIR}"
    exit 0
    ;;
esac

case "${RUST_TARGET}" in
  arm*hf | thumb*hf) cc_target=arm-linux-gnueabihf ;;
  arm* | thumb*) cc_target=arm-linux-gnueabi ;;
  riscv??gc-*) cc_target="${RUST_TARGET/gc-unknown/}" ;;
  sparc-*)
    cc_target=sparc-linux-gnu
    apt_target=sparc64-linux-gnu
    multilib=1
    ;;
  *) cc_target="${RUST_TARGET/-unknown/}" ;;
esac
lib_arch="${RUST_TARGET%-unknown*}"
case "${RUST_TARGET}" in
  aarch64-*) lib_arch=arm64 ;;
  arm*hf | thumb*hf) lib_arch=armhf ;;
  arm* | thumb*) lib_arch=armel ;;
  i?86-*) lib_arch=i386 ;;
  mipsisa32r6*) lib_arch="${lib_arch/isa32/}" ;;
  mipsisa64r6*) lib_arch="${lib_arch/isa64/64}" ;;
  powerpc-*spe) lib_arch=powerpcspe ;;
  powerpc-*) lib_arch=powerpc ;;
  powerpc64-*) lib_arch=ppc64 ;;
  powerpc64le-*) lib_arch=ppc64el ;;
  riscv??gc-*) lib_arch="${RUST_TARGET%gc-unknown*}" ;;
  sparc-*) lib_arch=sparc64 ;;
  x86_64*x32) lib_arch=x32 ;;
  x86_64*) lib_arch=amd64 ;;
esac
apt_target="${apt_target:-"${cc_target/i586/i686}"}"
printf '%s\n' "${cc_target}" >/CC_TARGET
printf '%s\n' "${apt_target}" >/APT_TARGET

gcc_version=$(gcc --version | sed -n '1 s/^.*) //p')
printf '%s\n' "${gcc_version}" >/GCC_VERSION
mkdir -p -- /tmp/toolchain
cd -- /tmp/toolchain
apt-get -o Acquire::Retries=10 -qq update
packages=("g++-${multilib:+multilib-}${apt_target/_/-}")
if [[ -z "${multilib:-}" ]]; then
  # TODO(fortran)
  packages+=("gfortran-${apt_target/_/-}")
fi
# shellcheck disable=SC2046
apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 download $(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances \
  "${packages[@]}" \
  | grep -E '^\w' \
  | grep -E "${apt_target/_/-}|${lib_arch}-cross")
set +x
for deb in *.deb; do
  dpkg -x "${deb}" .
  mv -- "${deb}" "${TOOLCHAIN_DIR}-deb"
done
set -x
mv -- usr/* "${TOOLCHAIN_DIR}"
