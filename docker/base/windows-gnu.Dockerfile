# syntax=docker/dockerfile:1

ARG UBUNTU_VERSION=20.04

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
sed -i 's/# deb-src/deb-src/g' /etc/apt/sources.list
apt-get -o Acquire::Retries=10 update -qq
apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
    dpkg-dev
EOF

ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p "${TOOLCHAIN_DIR}" "${TOOLCHAIN_DIR}-deb"
RUN mkdir -p /tmp/toolchain
WORKDIR /tmp/toolchain
RUN <<EOF
arch="${RUST_TARGET%%-*}"
apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 download $(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances \
    "g++-mingw-w64-${arch/_/-}" \
    | grep '^\w' \
    | grep 'mingw')
EOF
# Adapted from https://github.com/cross-rs/cross/blob/16a64e7028d90a3fdf285cfd642cdde9443c0645/docker/mingw.sh
# Ubuntu mingw packages for i686 uses sjlj exceptions, but rust target
# i686-pc-windows-gnu uses dwarf exceptions. So we build mingw packages
# that are compatible with rust.
RUN --mount=type=bind,target=/base <<EOF
case "${RUST_TARGET}" in
    x86_64*) exit 0 ;;
    i686-*) ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
mkdir -p /tmp/gcc-mingw-src
cd /tmp/gcc-mingw-src
apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 source gcc-mingw-w64-i686
apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 build-dep -y gcc-mingw-w64-i686
cd gcc-mingw-w64-*
# Use dwarf2 exceptions instead of sjlj exceptions.
sed -i -e 's/libgcc_s_sjlj-1/libgcc_s_dw2-1/g' debian/gcc-mingw-w64-i686.install*
# Apply a patch to disable x86_64 packages, languages other than c/c++,
# sjlj exceptions, and enable dwarf2 exceptions.
patch -p1 </base/windows-gnu-gcc-mingw-i686.diff
dpkg-buildpackage -B -us -uc -nc -j"$(nproc)" &>build.log || (tail <build.log -5000 && exit 1)
ls ../
rm /tmp/toolchain/g*-mingw-w64-i686*.deb /tmp/toolchain/gcc-mingw-w64-base*.deb
mv ../g*-mingw-w64-i686*.deb ../gcc-mingw-w64-base*.deb /tmp/toolchain
EOF
RUN <<EOF
for deb in *.deb; do
    dpkg -x "${deb}" .
    mv "${deb}" "${TOOLCHAIN_DIR}-deb"
done
mv usr/* "${TOOLCHAIN_DIR}"
EOF
WORKDIR /

RUN <<EOF
cc_target="${RUST_TARGET%%-*}-w64-mingw32"
echo "${cc_target}" >/CC_TARGET
EOF

RUN --mount=type=bind,target=/base \
    /base/common.sh

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
COPY --from=builder /"${RUST_TARGET}-deb" /"${RUST_TARGET}-deb"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
