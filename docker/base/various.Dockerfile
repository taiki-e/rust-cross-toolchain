# syntax=docker/dockerfile:1

ARG TARGET

FROM ghcr.io/taiki-e/downloader as aarch64-none-elf
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG ARM_GCC_VERSION=10.3-2021.07
RUN mkdir -p /toolchain
# https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain/gnu-a/downloads
# https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads
# GCC 10.3.1, newlib 4.1.0, binutils 2.36.1, GDB 10.2
RUN <<EOF
cc_target=aarch64-none-elf
dpkg_arch="$(dpkg --print-architecture)"
case "${dpkg_arch##*-}" in
    amd64) host_arch=x86_64 ;;
    arm64) host_arch=aarch64 ;;
    *) echo >&2 "unsupported architecture '${dpkg_arch}'" && exit 1 ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://developer.arm.com/-/media/Files/downloads/gnu-a/${ARM_GCC_VERSION}/binrel/gcc-arm-${ARM_GCC_VERSION}-${host_arch}-${cc_target}.tar.xz" \
    | tar xJf - --strip-components 1 -C /toolchain
EOF

FROM ghcr.io/taiki-e/downloader as arm-none-eabi
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG ARM_GCC_VERSION=10.3-2021.10
RUN mkdir -p /toolchain
# https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain/gnu-rm/downloads
# https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads
# The same GCC, newlib, binutils, GDB versions as aarch64-toolchain.
RUN <<EOF
cc_target=arm-none-eabi
dpkg_arch="$(dpkg --print-architecture)"
case "${dpkg_arch##*-}" in
    amd64) host_arch=x86_64 ;;
    arm64) host_arch=aarch64 ;;
    *) echo >&2 "unsupported architecture '${dpkg_arch}'" && exit 1 ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://developer.arm.com/-/media/Files/downloads/gnu-rm/${ARM_GCC_VERSION}/gcc-${cc_target}-${ARM_GCC_VERSION}-${host_arch}-linux.tar.bz2" \
    | tar xjf - --strip-components 1 -C /toolchain
EOF

FROM ghcr.io/taiki-e/downloader as riscv32-unknown-elf
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RISCV_GCC_VERSION=2021.09.21
RUN mkdir -p /toolchain
# https://github.com/riscv-collab/riscv-gnu-toolchain/releases
# GCC 11.1.0, newlib 4.1.0, binutils 2.37, GDB 10.1
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/${RISCV_GCC_VERSION}/riscv32-elf-ubuntu-18.04-nightly-${RISCV_GCC_VERSION}-nightly.tar.gz" \
        | tar xzf - --strip-components 1 -C /toolchain

FROM ghcr.io/taiki-e/downloader as riscv64-unknown-elf
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RISCV_GCC_VERSION=2021.09.21
RUN mkdir -p /toolchain
# https://github.com/riscv-collab/riscv-gnu-toolchain/releases
# The same GCC, newlib, binutils, GDB versions as riscv32-toolchain.
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/${RISCV_GCC_VERSION}/riscv64-elf-ubuntu-18.04-nightly-${RISCV_GCC_VERSION}-nightly.tar.gz" \
        | tar xzf - --strip-components 1 -C /toolchain

FROM "${TARGET}" as toolchain
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
RUN rm -rf /toolchain/share/{doc,i18n,lintian,locale,man}

FROM ubuntu as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG TARGET
COPY --from=toolchain /toolchain /"${TARGET}"
ENV PATH="/${TARGET}/bin:$PATH"
