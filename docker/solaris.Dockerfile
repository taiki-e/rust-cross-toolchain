# syntax=docker/dockerfile:1.3-labs

# Refs:
# - https://github.com/rust-lang/rust/blob/27143a9094b55a00d5f440b05b0cb4233b300d33/src/ci/docker/host-x86_64/dist-various-2/build-solaris-toolchain.sh

ARG UBUNTU_VERSION=18.04

ARG SOLARIS_VERSION=2.11
# https://ftp.gnu.org/gnu/binutils
ARG BINUTILS_VERSION=2.33.1
# https://ftp.gnu.org/gnu/gcc
ARG GCC_VERSION=8.5.0

FROM ghcr.io/taiki-e/downloader as binutils-src
ARG BINUTILS_VERSION
RUN mkdir -p /binutils-src
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.gz" \
        | tar xzf - --strip-components 1 -C /binutils-src
FROM ghcr.io/taiki-e/downloader as gcc-src
ARG GCC_VERSION
RUN mkdir -p /gcc-src
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.gz" \
        | tar xzf - --strip-components 1 -C /gcc-src

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
    libgmp-dev \
    libmpc-dev \
    libmpfr-dev \
    software-properties-common

ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p "${TOOLCHAIN_DIR}"

ARG SOLARIS_VERSION
RUN <<EOF
cc_target="${RUST_TARGET}${SOLARIS_VERSION}"
echo "${cc_target}" >/CC_TARGET
EOF
RUN <<EOF
cd "${TOOLCHAIN_DIR}"
mkdir -p "$(</CC_TARGET)"
ln -s "$(</CC_TARGET)" "${RUST_TARGET}"
EOF

ARG BINUTILS_VERSION
COPY --from=binutils-src /binutils-src /tmp/binutils-src
RUN mkdir -p /tmp/binutils-build
RUN <<EOF
export CFLAGS="-g0 -O2 -fPIC"
export CXXFLAGS="-g0 -O2 -fPIC"
cd /tmp/binutils-build
/tmp/binutils-src/configure \
    --prefix="${TOOLCHAIN_DIR}" \
    --target="$(</CC_TARGET)" \
    --with-sysroot="${SYSROOT_DIR}" \
    --with-debug-prefix-map="$(pwd)"= \
    --disable-nls \
    &>build.log || (cat build.log && exit 1)
make -j"$(nproc)" &>build.log || (cat build.log && exit 1)
make -p "${TOOLCHAIN_DIR}" &>build.log || (cat build.log && exit 1)
make install &>build.log || (cat build.log && exit 1)
EOF

RUN mkdir -p /tmp/sysroot
WORKDIR /tmp/sysroot
RUN <<EOF
case "${RUST_TARGET}" in
    x86_64-*) dpkg_arch=solaris-i386 ;;
    sparcv9-*) dpkg_arch=solaris-sparc ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
apt-key adv --batch --yes --keyserver keyserver.ubuntu.com --recv-keys 74DA7924C5513486
add-apt-repository -y 'deb http://apt.dilos.org/dilos dilos2 main'
dpkg --add-architecture "${dpkg_arch}"
apt-get update -qq
apt-get -o Dpkg::Use-Pty=0 download $(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances \
    "libc:${dpkg_arch}" \
    "libm-dev:${dpkg_arch}" \
    "libpthread:${dpkg_arch}" \
    "libresolv:${dpkg_arch}" \
    "librt:${dpkg_arch}" \
    "libsocket:${dpkg_arch}" \
    "system-crt:${dpkg_arch}" \
    "system-header:${dpkg_arch}" \
    | grep '^\w')
for deb in *"${dpkg_arch}.deb"; do
    dpkg -x "${deb}" .
    rm "${deb}"
done
EOF
# The -dev packages are not available from the apt repository we're using.
# However, those packages are just symlinks from *.so to *.so.<version>.
# This makes all those symlinks.
RUN <<EOF
for lib in $(find . -name '*.so.*'); do
    target="${lib%.so.*}.so"
    [[ -e "${target}" ]] || ln -s "${lib##*/}" "${target}"
done
EOF
RUN <<EOF
case "${RUST_TARGET}" in
    x86_64-*) lib_arch=amd64 ;;
    sparcv9-*) lib_arch=sparcv9 ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
mkdir -p "${SYSROOT_DIR}"/usr
mv usr/include "${SYSROOT_DIR}/usr/include"
mv "usr/lib/${lib_arch}"/* "${SYSROOT_DIR}/lib"
mv "lib/${lib_arch}"/* "${SYSROOT_DIR}/lib"
ln -s usr/include "${SYSROOT_DIR}/sys-include"
ln -s usr/include "${SYSROOT_DIR}/include"
EOF
WORKDIR /
RUN rm -rf /tmp/sysroot

ARG GCC_VERSION
COPY --from=gcc-src /gcc-src /tmp/gcc-src
RUN mkdir -p /tmp/gcc-build
# https://gcc.gnu.org/install/configure.html
RUN <<EOF
export CFLAGS="-g0 -O2 -fPIC"
export CXXFLAGS="-g0 -O2 -fPIC"
export CFLAGS_FOR_TARGET="-g1 -O2 -fPIC"
export CXXFLAGS_FOR_TARGET="-g1 -O2 -fPIC"
cd /tmp/gcc-build
/tmp/gcc-src/configure \
    --prefix="${TOOLCHAIN_DIR}" \
    --target="$(</CC_TARGET)" \
    --with-sysroot="${SYSROOT_DIR}" \
    --with-debug-prefix-map="$(pwd)"= \
    --with-gnu-as \
    --with-gnu-ld \
    --disable-bootstrap \
    --disable-libada \
    --disable-libcilkrts \
    --disable-libgomp \
    --disable-libquadmath \
    --disable-libquadmath-support \
    --disable-libsanitizer \
    --disable-libssp \
    --disable-libvtv \
    --disable-multilib \
    --disable-nls \
    --enable-languages=c,c++ \
    &>build.log || (cat build.log && exit 1)
make -j"$(nproc)" &>build.log || (cat build.log | tail -5000 && exit 1)
make -p "${TOOLCHAIN_DIR}" &>build.log || (cat build.log | tail -5000 && exit 1)
make install &>build.log || (cat build.log | tail -5000 && exit 1)
EOF
RUN rm -rf "${TOOLCHAIN_DIR}"/share/{doc,man}

# Some paths still use the target name that passed by --target even if we use
# options such as --program-prefix. So use the target name for C by default,
# and create symbolic links with Rust's target name for convenience.
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

# TODO: unrecognized option '-C' from ld
# COPY /clang-cross.sh /
# RUN COMMON_FLAGS="--gcc-toolchain=\"\${toolchain_dir}\"" \
#     CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION} -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION}/${RUST_TARGET}" \
#     /clang-cross.sh

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as test-base
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
COPY /test-base.sh /
RUN /test-base.sh
ARG RUST_TARGET
COPY /test-base-target.sh /
RUN /test-base-target.sh
COPY /test /test

FROM test-base as test-relocated
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh gcc
# TODO: unrecognized option '-C' from ld
# RUN /test/test.sh clang
RUN touch /DONE

FROM test-base as test
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN /test/test.sh gcc
# TODO: unrecognized option '-C' from ld
# RUN /test/test.sh clang
COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
COPY --from=test /"${RUST_TARGET}-dev" /"${RUST_TARGET}-dev"
ENV PATH="/${RUST_TARGET}/bin:/${RUST_TARGET}-dev/bin:$PATH"
