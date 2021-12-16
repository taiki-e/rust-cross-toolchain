# syntax=docker/dockerfile:1.3-labs

ARG RUST_TARGET
ARG UBUNTU_VERSION=20.04
ARG TOOLCHAIN_TAG=dev
ARG HOST_ARCH=amd64

FROM ghcr.io/taiki-e/rust-cross-toolchain:"${RUST_TARGET}-base${TOOLCHAIN_TAG:+"-${TOOLCHAIN_TAG}"}-${HOST_ARCH}" as toolchain

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG UBUNTU_VERSION
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

COPY /clang-cross.sh /
RUN <<EOF
gcc_version="${GCC_VERSION:-"$(gcc --version | sed -n '1 s/^.*) //p')"}"
COMMON_FLAGS="--gcc-toolchain=\"\${toolchain_dir}\" -B\"\${toolchain_dir}\"/${RUST_TARGET}/bin -L\"\${toolchain_dir}\"/${RUST_TARGET}/lib -L${TOOLCHAIN_DIR}/lib/gcc-cross/${RUST_TARGET}/${gcc_version%%.*}" \
    CFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include" \
    CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version%%.*}/${RUST_TARGET}" \
    SYSROOT=none \
    /clang-cross.sh
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as test-base
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ENV HOME=/tmp/home
COPY /test-base.sh /
RUN /test-base.sh
RUN <<EOF
dpkg_arch="$(dpkg --print-architecture)"
case "${dpkg_arch##*-}" in
    amd64) dpkg --add-architecture i386 ;;
    arm64) dpkg --add-architecture armhf ;;
    *) echo >&2 "unsupported architecture '${dpkg_arch}'" && exit 1 ;;
esac
EOF
RUN apt-get -o Acquire::Retries=10 update -qq && apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
    wine-stable \
    wine32 \
    wine64
# To install the latest wine: https://wiki.winehq.org/Ubuntu
# RUN <<EOF
# curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused https://dl.winehq.org/wine-builds/winehq.key | apt-key add -
# codename="$(grep </etc/os-release '^VERSION_CODENAME=' | sed 's/^VERSION_CODENAME=//')"
# echo "deb https://dl.winehq.org/wine-builds/ubuntu/ ${codename} main" >/etc/apt/sources.list.d/winehq.list
# EOF
# # Use winehq-devel instead of winehq-stable (6.0.2), because mio needs wine 6.11+.
# # https://dl.winehq.org/wine-builds/ubuntu/dists/focal/main/binary-amd64
# # https://wiki.winehq.org/Wine_User%27s_Guide#Wine_from_WineHQ
# # https://github.com/tokio-rs/mio/issues/1444
# RUN apt-get -o Acquire::Retries=10 update -qq && apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
#     winehq-devel
RUN wine --version
ARG RUST_TARGET
COPY /test-base /test-base
RUN /test-base/target.sh
COPY /test /test

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
# TODO: test both thread=posix and thread=win32
RUN /test/test.sh gcc
RUN /test/test.sh clang
# COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
COPY --from=toolchain /"${RUST_TARGET}-deb" /"${RUST_TARGET}-deb"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
