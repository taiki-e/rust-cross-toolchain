# syntax=docker/dockerfile:1.3-labs

ARG UBUNTU_VERSION=20.04

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG UBUNTU_VERSION
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p "${TOOLCHAIN_DIR}"

RUN sed -i 's/# deb-src/deb-src/g' /etc/apt/sources.list
RUN apt-get -o Acquire::Retries=10 update -qq
RUN apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
    dpkg-dev
RUN mkdir -p /tmp/toolchain
RUN <<EOF
cd /tmp/toolchain
arch="${RUST_TARGET%%-*}"
apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 download $(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances \
    "g++-mingw-w64-${arch/_/-}" \
    | grep '^\w' \
    | grep 'mingw')
EOF
COPY /windows-gnu.sh /
RUN /windows-gnu.sh
RUN <<EOF
cd /tmp/toolchain
for deb in *.deb; do
    dpkg -x "${deb}" .
    rm "${deb}"
done
mv usr/* "${TOOLCHAIN_DIR}"
EOF
RUN rm -rf "${TOOLCHAIN_DIR}"/share/{doc,lintian,man}

RUN <<EOF
cc_target="${RUST_TARGET%%-*}-w64-mingw32"
echo "${cc_target}" >/CC_TARGET
EOF

RUN <<EOF
set +x
cc_target="$(</CC_TARGET)"
cd "${TOOLCHAIN_DIR}/bin"
for tool in "${cc_target}"-*-posix; do
    link="${tool%-posix}"
    [[ -e "${link}" ]] || ln -s "${tool}" "${link}"
done
EOF

# Create symlinks with Rust's target name for convenience.
RUN <<EOF
set +x
cc_target="$(</CC_TARGET)"
while IFS= read -r -d '' path; do
    pushd "$(dirname "${path}")" >/dev/null
    original="$(basename "${path}")"
    link="${original/"${cc_target}"/"${RUST_TARGET}"}"
    [[ -e "${link}" ]] || ln -s "${original}" "${link}"
    popd >/dev/null
done < <(find "${TOOLCHAIN_DIR}" -name "${cc_target}*" -print0)
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
# Install the latest wine from winehq: https://wiki.winehq.org/Ubuntu
# To install Ubuntu's default wine, run the following:
#   RUN dpkg --add-architecture i386 && apt-get -o Acquire::Retries=10 update -qq && apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
#       wine-stable \
#       wine32 \
#       wine64
RUN dpkg --add-architecture i386
RUN apt-get -o Acquire::Retries=10 update -qq && apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
    software-properties-common
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 https://dl.winehq.org/wine-builds/winehq.key | apt-key add -
RUN <<EOF
codename="$(grep </etc/os-release '^VERSION_CODENAME=' | sed 's/^VERSION_CODENAME=//')"
add-apt-repository "deb https://dl.winehq.org/wine-builds/ubuntu/ ${codename} main"
EOF
# Use winehq-devel instead of winehq-stable (6.0.2), because mio needs wine 6.11+.
# https://dl.winehq.org/wine-builds/ubuntu/dists/focal/main/binary-amd64
# https://wiki.winehq.org/Wine_User%27s_Guide#Wine_from_WineHQ
# https://github.com/tokio-rs/mio/issues/1444
RUN apt-get -o Acquire::Retries=10 update -qq && apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
    winehq-devel
RUN wine --version
ARG RUST_TARGET
COPY /test-base-target.sh /
RUN /test-base-target.sh
COPY /test /test
COPY --from=ghcr.io/taiki-e/qemu-user /usr/bin/qemu-* /usr/bin/

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
RUN /test/test.sh gcc
RUN /test/test.sh clang
COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
