#!/bin/bash
set -euxo pipefail
IFS=$'\n\t'

case "${RUST_TARGET}" in
    aarch64_be-unknown-linux-gnu)
        # Toolchains for aarch64_be-linux-gnu is not available in APT.
        # https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain/gnu-a/downloads
        # GCC 10.2.1, Linux header 4.20.13, glibc 2.31, binutils 2.35.1
        # Use 10.2-2020.11 instead of the latest 10.3-2021.07 because 10.3-2021.07 requires glibc 2.33.
        arm_gcc_version=10.2-2020.11
        cc_target=aarch64_be-none-linux-gnu
        gcc_version=10.2.1
        echo "${cc_target}" >/CC_TARGET
        echo "${gcc_version}" >/GCC_VERSION
        curl --proto '=https' --tlsv1.2 -fsSL --retry 10 "https://developer.arm.com/-/media/Files/downloads/gnu-a/${arm_gcc_version}/binrel/gcc-arm-${arm_gcc_version}-x86_64-${cc_target}.tar.xz" \
            | tar xJf - --strip-components 1 -C "${TOOLCHAIN_DIR}"
        exit 0
        ;;
    arm-unknown-linux-gnueabihf)
        # Ubuntu's gcc-arm-linux-gnueabihf enables armv7 by default
        # https://github.com/abhiTronix/raspberry-pi-cross-compilers/wiki/Cross-Compiler:-Installation-Instructions#b-download-binary
        # https://sourceforge.net/projects/raspberry-pi-cross-compilers/files/Raspberry%20Pi%20GCC%20Cross-Compiler%20Toolchains/Stretch/
        cc_target=arm-linux-gnueabihf
        gcc_version=9.4.0
        codename=Stretch
        echo "${cc_target}" >/CC_TARGET
        echo "${gcc_version}" >/GCC_VERSION
        curl --proto '=https' --tlsv1.2 -fsSL --retry 10 "https://sourceforge.net/projects/raspberry-pi-cross-compilers/files/Raspberry%20Pi%20GCC%20Cross-Compiler%20Toolchains/${codename}/GCC%20${gcc_version}/Raspberry%20Pi%201%2C%20Zero/cross-gcc-${gcc_version}-pi_0-1.tar.gz/download" \
            | tar xzf - --strip-components 1 -C "${TOOLCHAIN_DIR}"
        exit 0
        ;;
    riscv32gc-unknown-linux-gnu)
        # Toolchains for aarch64_be-linux-gnu is not available in APT.
        # https://github.com/riscv-collab/riscv-gnu-toolchain/releases
        # GCC 11.1.0, Linux header 5.10.5, glibc 2.33, binutils 2.37
        riscv_gcc_version=2021.09.21
        cc_target=riscv32-unknown-linux-gnu
        gcc_version=11.1.0
        echo "${cc_target}" >/CC_TARGET
        echo "${gcc_version}" >/GCC_VERSION
        curl --proto '=https' --tlsv1.2 -fsSL --retry 10 "https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/${riscv_gcc_version}/riscv32-glibc-ubuntu-${UBUNTU_VERSION}-nightly-${riscv_gcc_version}-nightly.tar.gz" \
            | tar xzf - --strip-components 1 -C "${TOOLCHAIN_DIR}"
        exit 0
        ;;
esac

case "${RUST_TARGET}" in
    arm*hf | thumbv7neon-*) cc_target=arm-linux-gnueabihf ;;
    arm*) cc_target=arm-linux-gnueabi ;;
    riscv32gc-* | riscv64gc-*) cc_target="${RUST_TARGET/gc-unknown/}" ;;
    *) cc_target="${RUST_TARGET/-unknown/}" ;;
esac
lib_arch="${RUST_TARGET%-unknown*}"
case "${RUST_TARGET}" in
    aarch64-*) lib_arch=arm64 ;;
    arm*hf | thumbv7neon-*) lib_arch=armhf ;;
    arm*) lib_arch=armel ;;
    i*86-*) lib_arch=i386 ;;
    mipsisa32r6*) lib_arch="${lib_arch/isa32/}" ;;
    mipsisa64r6*) lib_arch="${lib_arch/isa64/64}" ;;
    powerpc-*spe) lib_arch=powerpcspe ;;
    powerpc-*) lib_arch=powerpc ;;
    powerpc64-*) lib_arch=ppc64 ;;
    powerpc64le-*) lib_arch=ppc64el ;;
    riscv64gc-*) lib_arch="${RUST_TARGET%gc-unknown*}" ;;
    x86_64-*x32) lib_arch=x32 ;;
    x86_64-*) lib_arch=amd64 ;;
esac
apt_target="${cc_target/i586/i686}"
echo "${apt_target}" >/CC_TARGET

gcc_version="${GCC_VERSION:-"$(gcc --version | sed -n '1 s/^.*) //p')"}"
echo "${gcc_version}" >/GCC_VERSION
mkdir -p /tmp/toolchain
cd /tmp/toolchain
if [[ -n "${lib_arch}" ]]; then
    apt-get update -qq
    # shellcheck disable=SC2046
    apt-get -o Dpkg::Use-Pty=0 download $(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances \
        "g++-${gcc_version%%.*}-${apt_target/_/-}" \
        | grep '^\w' \
        | grep -E "${apt_target/_/-}|${lib_arch}-cross")
    for deb in *.deb; do
        dpkg -x "${deb}" .
        rm "${deb}"
    done
    mv usr/* "${TOOLCHAIN_DIR}"
else
    exit 1
fi

# Create symlinks: $tool-$gcc_version -> $tool
set +x
cd "${TOOLCHAIN_DIR}/bin"
for tool in *-"${gcc_version%%.*}"; do
    link="${tool%"-${gcc_version%%.*}"}"
    [[ -e "${link}" ]] || ln -s "${tool}" "${link}"
done
set -x
