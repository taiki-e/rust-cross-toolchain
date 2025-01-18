# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

ARG RUST_TARGET
# NB: When updating this, the reminder to update GCC/Mingw version in README.md.
ARG UBUNTU_VERSION=22.04
ARG TOOLCHAIN_TAG=dev
ARG HOST_ARCH=amd64

FROM ghcr.io/taiki-e/rust-cross-toolchain:"${RUST_TARGET}-base${TOOLCHAIN_TAG:+"-${TOOLCHAIN_TAG}"}-${HOST_ARCH}" AS toolchain

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS builder
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
COPY --from=toolchain "${TOOLCHAIN_DIR}" "${TOOLCHAIN_DIR}"

RUN <<EOF
cc_target="${RUST_TARGET%%-*}-w64-mingw32"
printf '%s\n' "${cc_target}" >/CC_TARGET
EOF
RUN <<EOF
set +x
cd -- "${TOOLCHAIN_DIR}/bin"
for tool in "${RUST_TARGET}"-*-posix "$(</CC_TARGET)"-*-posix; do
    link="${tool%-posix}"
    [[ -e "${link}" ]] || ln -s -- "${tool}" "${link}"
done
EOF

# TODO cannot find -lgcc: No such file or directory
# RUN --mount=type=bind,target=/docker <<EOF
# gcc_version=$(gcc --version | sed -En '1 s/^.*\) //p')
# COMMON_FLAGS="--gcc-toolchain=\"\${toolchain_dir}\" -B\"\${toolchain_dir}\"/${RUST_TARGET}/bin -L\"\${toolchain_dir}\"/${RUST_TARGET}/lib -L${TOOLCHAIN_DIR}/lib/gcc-cross/${RUST_TARGET}/${gcc_version%%.*}" \
#     CFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include" \
#     CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version%%.*}/${RUST_TARGET}" \
#     SYSROOT=none \
#     /docker/clang-cross.sh
# EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" AS test-base
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ENV HOME=/tmp/home
ARG REAL_HOST_ARCH
COPY /test-base.sh /
RUN /test-base.sh
RUN <<EOF
dpkg_arch=$(dpkg --print-architecture)
case "${dpkg_arch##*-}" in
    amd64)
        dpkg --add-architecture i386
        # Install the latest wine: https://wiki.winehq.org/Ubuntu
        codename=$(grep -E '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2)
        # shellcheck disable=SC2174
        mkdir -pm755 -- /etc/apt/keyrings
        curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused https://dl.winehq.org/wine-builds/winehq.key \
            | tee -- /etc/apt/keyrings/winehq-archive.key >/dev/null
        curl --proto '=https' --tlsv1.2 -fsSLR --retry 10 --retry-connrefused "https://dl.winehq.org/wine-builds/ubuntu/dists/${codename}/winehq-${codename}.sources" \
            | tee -- "/etc/apt/sources.list.d/winehq-${codename}.sources" >/dev/null
        apt-get -o Acquire::Retries=10 -qq update && apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
            winehq-stable
        ;;
    arm64)
        dpkg --add-architecture armhf
        apt-get -o Acquire::Retries=10 -qq update && apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
            wine \
            wine32 \
            wine64
        ;;
    *) printf >&2 '%s\n' "unsupported architecture '${dpkg_arch}'" && exit 1 ;;
esac
wine --version
EOF
ARG RUST_TARGET
COPY /test-base /test-base
RUN /test-base/target.sh
COPY /test /test

FROM test-base AS test-relocated
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh gcc
# TODO cannot find -lgcc: No such file or directory
# RUN /test/test.sh clang
RUN touch -- /DONE

FROM test-base AS test
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
# TODO: test both thread=posix and thread=win32
RUN /test/test.sh gcc
# TODO cannot find -lgcc: No such file or directory
# RUN /test/test.sh clang
# COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" AS final
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
COPY --from=toolchain /"${RUST_TARGET}-deb" /"${RUST_TARGET}-deb"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
