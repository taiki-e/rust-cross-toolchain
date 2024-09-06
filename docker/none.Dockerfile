# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

ARG RUST_TARGET
ARG UBUNTU_VERSION=18.04
ARG TOOLCHAIN_TAG=dev
ARG HOST_ARCH=amd64

FROM ghcr.io/taiki-e/rust-cross-toolchain:"aarch64-none-elf-base${TOOLCHAIN_TAG:+"-${TOOLCHAIN_TAG}"}-${HOST_ARCH}" AS aarch64-toolchain
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
cc_target=aarch64-none-elf
echo "${cc_target}" >/CC_TARGET
EOF
FROM aarch64-toolchain AS aarch64-unknown-none
FROM aarch64-toolchain AS aarch64-unknown-none-softfloat

FROM ghcr.io/taiki-e/rust-cross-toolchain:"arm-none-eabi-base${TOOLCHAIN_TAG:+"-${TOOLCHAIN_TAG}"}-${HOST_ARCH}" AS arm-toolchain
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
cc_target=arm-none-eabi
gcc_version=10.3.1
echo "${cc_target}" >/CC_TARGET
echo "${gcc_version}" >/GCC_VERSION
EOF
ARG RUST_TARGET
# $ fd -t d 'v5te|v6|v7|v8'
RUN <<EOF
cc_target=$(</CC_TARGET)
gcc_version=$(</GCC_VERSION)
cd "/${cc_target}"
case "${RUST_TARGET}" in
    *v5te*) ;;
    *)
        rm -rf \
            arm-none-eabi/include/c++/"${gcc_version}"/arm-none-eabi/arm/v5te \
            arm-none-eabi/lib/arm/v5te \
            lib/gcc/arm-none-eabi/"${gcc_version}"/arm/v5te
        ;;
esac
case "${RUST_TARGET}" in
    *v6m*) ;;
    *)
        rm -rf \
            arm-none-eabi/include/c++/"${gcc_version}"/arm-none-eabi/thumb/v6-m \
            arm-none-eabi/lib/thumb/v6-m \
            lib/gcc/arm-none-eabi/"${gcc_version}"/thumb/v6-m
        ;;
esac
case "${RUST_TARGET}" in
    *v7*) ;;
    *)
        rm -rf \
            arm-none-eabi/include/c++/"${gcc_version}"/arm-none-eabi/thumb/v7* \
            arm-none-eabi/lib/thumb/v7* \
            lib/gcc/arm-none-eabi/"${gcc_version}"/thumb/v7*
        ;;
esac
case "${RUST_TARGET}" in
    *v8*) ;;
    *)
        rm -rf \
            arm-none-eabi/include/c++/"${gcc_version}"/arm-none-eabi/thumb/v8* \
            arm-none-eabi/lib/thumb/v8* \
            lib/gcc/arm-none-eabi/"${gcc_version}"/thumb/v8*
        ;;
esac
EOF
FROM arm-toolchain AS armv5te-none-eabi
FROM arm-toolchain AS armebv7r-none-eabi
FROM arm-toolchain AS armebv7r-none-eabihf
FROM arm-toolchain AS armv7a-none-eabi
FROM arm-toolchain AS armv7a-none-eabihf
FROM arm-toolchain AS armv7r-none-eabi
FROM arm-toolchain AS armv7r-none-eabihf
FROM arm-toolchain as armv8r-none-eabihf
FROM arm-toolchain AS thumbv5te-none-eabi
FROM arm-toolchain AS thumbv6m-none-eabi
FROM arm-toolchain AS thumbv7em-none-eabi
FROM arm-toolchain AS thumbv7em-none-eabihf
FROM arm-toolchain AS thumbv7m-none-eabi
FROM arm-toolchain AS thumbv8m.base-none-eabi
FROM arm-toolchain AS thumbv8m.main-none-eabi
FROM arm-toolchain AS thumbv8m.main-none-eabihf

FROM ghcr.io/taiki-e/rust-cross-toolchain:"riscv32-unknown-elf-base${TOOLCHAIN_TAG:+"-${TOOLCHAIN_TAG}"}-${HOST_ARCH}" AS riscv32-toolchain
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
cc_target=riscv32-unknown-elf
echo "${cc_target}" >/CC_TARGET
EOF
FROM riscv32-toolchain AS riscv32i-unknown-none-elf
FROM riscv32-toolchain AS riscv32im-unknown-none-elf
FROM riscv32-toolchain AS riscv32imc-unknown-none-elf
FROM riscv32-toolchain AS riscv32imac-unknown-none-elf
FROM riscv32-toolchain AS riscv32gc-unknown-none-elf

FROM ghcr.io/taiki-e/rust-cross-toolchain:"riscv64-unknown-elf-base${TOOLCHAIN_TAG:+"-${TOOLCHAIN_TAG}"}-${HOST_ARCH}" AS riscv64-toolchain
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
cc_target=riscv64-unknown-elf
echo "${cc_target}" >/CC_TARGET
EOF
FROM riscv64-toolchain AS riscv64i-unknown-none-elf
FROM riscv64-toolchain AS riscv64im-unknown-none-elf
FROM riscv64-toolchain AS riscv64imc-unknown-none-elf
FROM riscv64-toolchain AS riscv64imac-unknown-none-elf
FROM riscv64-toolchain AS riscv64gc-unknown-none-elf

FROM "${RUST_TARGET}" AS toolchain
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
RUN mv "/$(</CC_TARGET)" "/${RUST_TARGET}"

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS builder
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
COPY --from=toolchain "${TOOLCHAIN_DIR}" "${TOOLCHAIN_DIR}"
COPY --from=toolchain /CC_TARGET /

RUN --mount=type=bind,target=/docker \
    /docker/base/common.sh

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS test-base
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
# https://launchpad.net/~canonical-server/+archive/ubuntu/server-backports/+packages
RUN <<EOF
apt-key adv --batch --yes --keyserver keyserver.ubuntu.com --recv-keys 94E187AD53A59D1847E4880F8A295C4FB8B190B7
codename=$(grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2)
echo "deb http://ppa.launchpad.net/canonical-server/server-backports/ubuntu ${codename} main" >/etc/apt/sources.list.d/server-backports.list
apt-get -o Acquire::Retries=10 -qq update
apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
    qemu-system-arm \
    qemu-system-misc
# APT's qemu package doesn't provide firmware for riscv32: https://packages.ubuntu.com/en/jammy/all/qemu-system-data/filelist
OPENSBI_VERSION=1.5.1 # https://github.com/riscv-software-src/opensbi/releases
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://github.com/riscv-software-src/opensbi/releases/download/v${OPENSBI_VERSION}/opensbi-${OPENSBI_VERSION}-rv-bin.tar.xz" \
| tar xJf -
mv "opensbi-${OPENSBI_VERSION}-rv-bin/share/opensbi/ilp32/generic/firmware/fw_dynamic.bin" /usr/share/qemu/opensbi-riscv32-generic-fw_dynamic.bin
mv "opensbi-${OPENSBI_VERSION}-rv-bin/share/opensbi/ilp32/generic/firmware/fw_dynamic.elf" /usr/share/qemu/opensbi-riscv32-generic-fw_dynamic.elf
rm -rf "opensbi-${OPENSBI_VERSION}-rv-bin"
EOF
ARG REAL_HOST_ARCH
COPY /test-base.sh /
RUN /test-base.sh none
ARG RUST_TARGET
COPY /test-base /test-base
RUN /test-base/target.sh
COPY /test /test
# TODO: "qemu-armeb: Error mapping file: Operation not permitted" error in 8.2
COPY --from=ghcr.io/taiki-e/qemu-user:8.1 /usr/bin/qemu-* /usr/bin/

FROM test-base AS test-relocated
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh gcc
RUN touch /DONE

FROM test-base AS test
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN /test/test.sh gcc
# COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" AS final
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
