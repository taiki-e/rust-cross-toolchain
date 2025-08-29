# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

ARG DISTRO=ubuntu
ARG DISTRO_VERSION=18.04

FROM ghcr.io/taiki-e/build-base:"${DISTRO}-${DISTRO_VERSION}" AS builder
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p -- "${TOOLCHAIN_DIR}" "${TOOLCHAIN_DIR}-deb"

RUN --mount=type=bind,target=/docker \
    /docker/linux-gnu.sh
RUN <<EOF
apt_target=$(</APT_TARGET)
for dir in "${TOOLCHAIN_DIR}" "${TOOLCHAIN_DIR}/${apt_target}"/libc/usr "${TOOLCHAIN_DIR}"/sysroot/usr "${TOOLCHAIN_DIR}"/target/usr; do
    if [[ -d "${dir}"/share ]]; then
        # https://wiki.ubuntu.com/ReducingDiskFootprint#Documentation
        find "${dir}"/share/doc -depth -type f ! -name '*copyright*' ! -name '*Copyright*' ! -name '*COPYRIGHT*' -exec rm -- {} + || true
        find "${dir}"/share/doc -empty -exec rmdir -- {} + || true
        rm -rf -- "${dir}"/share/{groff,i18n,info,linda,lintian,locale,man}
    fi
done
# shellcheck disable=SC2046
case "${RUST_TARGET}" in
    # There are {include,lib,libexec} for both GCC 9.4.0 and 6.3.0
    arm-*hf) rm -rf -- $(find "${TOOLCHAIN_DIR}" -name '6.3.0') $(find "${TOOLCHAIN_DIR}" -name '*gcc-6.3.0') ;;
    # libc6-dev-armhf-cross (g++-arm-linux-gnueabihf) contains /usr/arm-linux-gnueabi/{lib/hf,libhf}
    arm*hf | thumb*hf) rm -rf -- "${TOOLCHAIN_DIR}/arm-linux-gnueabi" ;;
    # libc6-dev-armel-cross (g++-arm-linux-gnueabi) contains /usr/arm-linux-gnueabihf/{lib/sf,libsf}
    arm* | thumb*) rm -rf -- "${TOOLCHAIN_DIR}/arm-linux-gnueabihf" ;;
esac
EOF

RUN <<EOF
apt_target=$(</APT_TARGET)
gcc_version=$(</GCC_VERSION)
if [[ "${gcc_version}" == "host" ]]; then
    exit 0
fi
case "${RUST_TARGET}" in
    sparc-*)
        # The interpreter for sparc-linux-gnu is /lib/ld-linux.so.2,
        # so lib/ld-linux.so.2 must be target sparc-linux-gnu to run binaries on qemu-user.
        rm -rf -- "${TOOLCHAIN_DIR:?}/${apt_target}/lib"
        rm -rf -- "${TOOLCHAIN_DIR:?}/${apt_target}/lib64"
        ln -s -- lib32 "${TOOLCHAIN_DIR}/${apt_target}/lib"
        common_flags="-m32 -mv8plus -L\"\${toolchain_dir}\"/${RUST_TARGET}/lib32 -L\"\${toolchain_dir}\"/${RUST_TARGET}/lib/gcc-cross/${RUST_TARGET}/${gcc_version}/32"
        ;;
    *) exit 0 ;;
esac
cat >"${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-gcc" <<EOF2
#!/bin/sh
set -eu
toolchain_dir="\$(cd -- "\$(dirname -- "\$0")"/.. && pwd)"
exec "\${toolchain_dir}"/bin/${apt_target}-gcc ${common_flags} "\$@"
EOF2
cat >"${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-g++" <<EOF2
#!/bin/sh
set -eu
toolchain_dir="\$(cd -- "\$(dirname -- "\$0")"/.. && pwd)"
exec "\${toolchain_dir}"/bin/${apt_target}-g++ ${common_flags} "\$@"
EOF2
chmod +x "${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-gcc" "${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-g++"
EOF

RUN --mount=type=bind,target=/docker \
    /docker/base/common.sh

# TODO(sparc-unknown-linux-gnu,clang): clang: error: unknown argument: '-mv8plus'
# TODO(loongarch64):
RUN --mount=type=bind,target=/docker <<EOF
gcc_version=$(</GCC_VERSION)
if [[ "${gcc_version}" == "host" ]]; then
    exit 0
fi
case "${RUST_TARGET}" in
    aarch64_be-* | armeb-* | arm-*hf | csky-*)
        COMMON_FLAGS="--gcc-toolchain=\"\${toolchain_dir}\"" \
            CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version} -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version}/${RUST_TARGET}" \
            SYSROOT="\"\${toolchain_dir}\"/${RUST_TARGET}/libc" \
            /docker/clang-cross.sh
        ;;
    riscv32*)
        COMMON_FLAGS="--gcc-toolchain=\"\${toolchain_dir}\" --ld-path=\"\${toolchain_dir}\"/bin/${RUST_TARGET}-ld -I\"\${toolchain_dir}\"/sysroot/usr/include" \
            CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version} -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version}/${RUST_TARGET}" \
            SYSROOT="\"\${toolchain_dir}\"/sysroot" \
            /docker/clang-cross.sh
        ;;
    sparc-* | loongarch64-*) ;;
    *)
        COMMON_FLAGS="--gcc-toolchain=\"\${toolchain_dir}\" -B\"\${toolchain_dir}\"/${RUST_TARGET}/bin -L\"\${toolchain_dir}\"/${RUST_TARGET}/lib -L${TOOLCHAIN_DIR}/lib/gcc-cross/${RUST_TARGET}/${gcc_version%%.*}" \
            CFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include" \
            CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version%%.*}/${RUST_TARGET}" \
            SYSROOT=none \
            /docker/clang-cross.sh
        ;;
esac
EOF

FROM ghcr.io/taiki-e/build-base:"${DISTRO}-${DISTRO_VERSION}" AS test-base
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
COPY /test-base.sh /
RUN /test-base.sh
ARG DISTRO_VERSION
ARG RUST_TARGET
COPY /test-base /test-base
RUN /test-base/target.sh
COPY /test /test
COPY --from=ghcr.io/taiki-e/qemu-user /usr/bin/qemu-* /usr/bin/

FROM test-base AS test-relocated
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
# Note: currently works only on this location
COPY --from=builder /"${RUST_TARGET}"/. /usr/
RUN /test/test.sh gcc
# TODO(csky): error: unable to create target: 'No available targets are compatible with triple "csky-unknown-linux-gnuabiv2"'
# TODO(loongarch64):
# TODO(sparc-unknown-linux-gnu,clang): clang: error: unknown argument: '-mv8plus'
RUN <<EOF
case "${RUST_TARGET}" in
    csky-* | loongarch64-* | sparc-*) ;;
    *) /test/test.sh clang ;;
esac
EOF
RUN touch -- /DONE

FROM test-base AS test
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN <<EOF
/test/entrypoint.sh gcc
/test/entrypoint.sh clang
EOF
# # TODO(linux-gnu)
# RUN <<EOF
# case "${RUST_TARGET}" in
#     aarch64_be-* | arm-*hf | riscv32*) /test/test.sh gcc ;;
#     *) NO_RUN=1 /test/test.sh gcc ;;
# esac
# EOF
# RUN <<EOF
# case "${RUST_TARGET}" in
#     aarch64_be-* | arm-*hf | riscv32*) /test/test.sh clang ;;
#     *) NO_RUN=1 /test/test.sh clang ;;
# esac
# EOF
COPY --from=test-relocated /DONE /

FROM "${DISTRO}":"${DISTRO_VERSION}" AS final
SHELL ["/bin/bash", "-CeEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
COPY --from=builder /"${RUST_TARGET}-deb" /"${RUST_TARGET}-deb"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
