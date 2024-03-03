# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

ARG RUST_TARGET
ARG UBUNTU_VERSION=22.04
ARG TOOLCHAIN_TAG=dev
ARG HOST_ARCH=amd64

FROM ghcr.io/taiki-e/rust-cross-toolchain:"${RUST_TARGET}-base${TOOLCHAIN_TAG:+"-${TOOLCHAIN_TAG}"}-${HOST_ARCH}" as toolchain

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
COPY --from=toolchain "${TOOLCHAIN_DIR}" "${TOOLCHAIN_DIR}"

RUN <<EOF
cc_target="${RUST_TARGET%%-*}-w64-mingw32"
echo "${cc_target}" >/CC_TARGET
EOF
RUN <<EOF
set +x
cd "${TOOLCHAIN_DIR}/bin"
for tool in "${RUST_TARGET}"-*-posix "$(</CC_TARGET)"-*-posix; do
    link="${tool%-posix}"
    [[ -e "${link}" ]] || ln -s "${tool}" "${link}"
done
EOF

# TODO cannot find -lgcc: No such file or directory
# RUN --mount=type=bind,target=/docker <<EOF
# gcc_version="${GCC_VERSION:-"$(gcc --version | sed -n '1 s/^.*) //p')"}"
# COMMON_FLAGS="--gcc-toolchain=\"\${toolchain_dir}\" -B\"\${toolchain_dir}\"/${RUST_TARGET}/bin -L\"\${toolchain_dir}\"/${RUST_TARGET}/lib -L${TOOLCHAIN_DIR}/lib/gcc-cross/${RUST_TARGET}/${gcc_version%%.*}" \
#     CFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include" \
#     CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version%%.*}/${RUST_TARGET}" \
#     SYSROOT=none \
#     /docker/clang-cross.sh
# EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as test-base
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ENV HOME=/tmp/home
COPY /test-base.sh /
RUN /test-base.sh
RUN <<EOF
dpkg_arch=$(dpkg --print-architecture)
case "${dpkg_arch##*-}" in
    amd64) dpkg --add-architecture i386 ;;
    arm64)
        dpkg --add-architecture armhf
        # TODO: do not skip if actual host is arm64
        exit 0
        ;;
    *) echo >&2 "unsupported architecture '${dpkg_arch}'" && exit 1 ;;
esac
# Install the latest wine: https://wiki.winehq.org/Ubuntu
codename=$(grep '^VERSION_CODENAME=' /etc/os-release | sed 's/^VERSION_CODENAME=//')
mkdir -pm755 /etc/apt/keyrings
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused https://dl.winehq.org/wine-builds/winehq.key \
    | tee /etc/apt/keyrings/winehq-archive.key >/dev/null
curl --proto '=https' --tlsv1.2 -fsSLR --retry 10 --retry-connrefused "https://dl.winehq.org/wine-builds/ubuntu/dists/${codename}/winehq-${codename}.sources" \
    | tee "/etc/apt/sources.list.d/winehq-${codename}.sources" >/dev/null
apt-get -o Acquire::Retries=10 -qq update && apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
    winehq-stable \
# apt-get -o Acquire::Retries=10 -qq update && apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
#     wine-stable \
#     wine32 \
#     wine64
wine --version
EOF
ARG RUST_TARGET
COPY /test-base /test-base
RUN /test-base/target.sh
COPY /test /test

FROM test-base as test-relocated
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh gcc
# TODO cannot find -lgcc: No such file or directory
# RUN /test/test.sh clang
RUN touch /DONE

FROM test-base as test
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
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

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
COPY --from=toolchain /"${RUST_TARGET}-deb" /"${RUST_TARGET}-deb"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
