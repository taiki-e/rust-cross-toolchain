# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

ARG RUST_TARGET
ARG UBUNTU_VERSION=18.04
ARG TOOLCHAIN_TAG=dev
ARG HOST_ARCH=amd64

FROM ghcr.io/taiki-e/rust-cross-toolchain:"aarch64-none-elf-base${TOOLCHAIN_TAG:+"-${TOOLCHAIN_TAG}"}-${HOST_ARCH}" as aarch64-toolchain
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
cc_target=aarch64-none-elf
echo "${cc_target}" >/CC_TARGET
EOF
FROM aarch64-toolchain as aarch64-unknown-none
FROM aarch64-toolchain as aarch64-unknown-none-softfloat

FROM ghcr.io/taiki-e/rust-cross-toolchain:"arm-none-eabi-base${TOOLCHAIN_TAG:+"-${TOOLCHAIN_TAG}"}-${HOST_ARCH}" as arm-toolchain
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
FROM arm-toolchain as armv5te-none-eabi
FROM arm-toolchain as armebv7r-none-eabi
FROM arm-toolchain as armebv7r-none-eabihf
FROM arm-toolchain as armv7a-none-eabi
FROM arm-toolchain as armv7a-none-eabihf
FROM arm-toolchain as armv7r-none-eabi
FROM arm-toolchain as armv7r-none-eabihf
FROM arm-toolchain as thumbv5te-none-eabi
FROM arm-toolchain as thumbv6m-none-eabi
FROM arm-toolchain as thumbv7em-none-eabi
FROM arm-toolchain as thumbv7em-none-eabihf
FROM arm-toolchain as thumbv7m-none-eabi
FROM arm-toolchain as thumbv8m.base-none-eabi
FROM arm-toolchain as thumbv8m.main-none-eabi
FROM arm-toolchain as thumbv8m.main-none-eabihf

FROM ghcr.io/taiki-e/rust-cross-toolchain:"riscv32-unknown-elf-base${TOOLCHAIN_TAG:+"-${TOOLCHAIN_TAG}"}-${HOST_ARCH}" as riscv32-toolchain
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
cc_target=riscv32-unknown-elf
echo "${cc_target}" >/CC_TARGET
EOF
FROM riscv32-toolchain as riscv32i-unknown-none-elf
FROM riscv32-toolchain as riscv32im-unknown-none-elf
FROM riscv32-toolchain as riscv32imc-unknown-none-elf
FROM riscv32-toolchain as riscv32imac-unknown-none-elf
FROM riscv32-toolchain as riscv32gc-unknown-none-elf

FROM ghcr.io/taiki-e/rust-cross-toolchain:"riscv64-unknown-elf-base${TOOLCHAIN_TAG:+"-${TOOLCHAIN_TAG}"}-${HOST_ARCH}" as riscv64-toolchain
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
cc_target=riscv64-unknown-elf
echo "${cc_target}" >/CC_TARGET
EOF
FROM riscv64-toolchain as riscv64i-unknown-none-elf
FROM riscv64-toolchain as riscv64im-unknown-none-elf
FROM riscv64-toolchain as riscv64imc-unknown-none-elf
FROM riscv64-toolchain as riscv64imac-unknown-none-elf
FROM riscv64-toolchain as riscv64gc-unknown-none-elf

FROM "${RUST_TARGET}" as toolchain
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
RUN mv "/$(</CC_TARGET)" "/${RUST_TARGET}"

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
COPY --from=toolchain "${TOOLCHAIN_DIR}" "${TOOLCHAIN_DIR}"
COPY --from=toolchain /CC_TARGET /

RUN --mount=type=bind,target=/docker \
    /docker/base/common.sh

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as test-base
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
# https://launchpad.net/~canonical-server/+archive/ubuntu/server-backports/+packages
RUN <<EOF
apt-key adv --batch --yes --keyserver keyserver.ubuntu.com --recv-keys 94E187AD53A59D1847E4880F8A295C4FB8B190B7
codename=$(grep '^VERSION_CODENAME=' /etc/os-release | sed 's/^VERSION_CODENAME=//')
echo "deb http://ppa.launchpad.net/canonical-server/server-backports/ubuntu ${codename} main" >/etc/apt/sources.list.d/server-backports.list
apt-get -o Acquire::Retries=10 -qq update
# libpython2.7 is needed for GDB
apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
    libpython2.7 \
    qemu-system-arm \
    qemu-system-misc
# APT's qemu package doesn't provide firmware for riscv32: https://packages.ubuntu.com/en/jammy/all/qemu-system-data/filelist
OPENSBI_VERSION=1.3.1 # https://github.com/riscv-software-src/opensbi/releases
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://github.com/riscv-software-src/opensbi/releases/download/v${OPENSBI_VERSION}/opensbi-${OPENSBI_VERSION}-rv-bin.tar.xz" \
| tar xJf -
mv "opensbi-${OPENSBI_VERSION}-rv-bin/share/opensbi/ilp32/generic/firmware/fw_dynamic.bin" /usr/share/qemu/opensbi-riscv32-generic-fw_dynamic.bin
mv "opensbi-${OPENSBI_VERSION}-rv-bin/share/opensbi/ilp32/generic/firmware/fw_dynamic.elf" /usr/share/qemu/opensbi-riscv32-generic-fw_dynamic.elf
rm -rf "opensbi-${OPENSBI_VERSION}-rv-bin"
EOF
COPY /test-base.sh /
RUN /test-base.sh none
ARG RUST_TARGET
COPY /test-base /test-base
RUN /test-base/target.sh
COPY /test /test
# TODO: "qemu-armeb: Error mapping file: Operation not permitted" error in 8.2
COPY --from=ghcr.io/taiki-e/qemu-user:8.1 /usr/bin/qemu-* /usr/bin/

FROM test-base as test-relocated
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh gcc
RUN touch /DONE

FROM test-base as test
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN /test/test.sh gcc
# COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
