# syntax=docker/dockerfile:1.4

# Refs:
# - https://developer.android.com/ndk
# - https://android.googlesource.com/platform/ndk/+/refs/heads/ndk-r15-release/docs/user/standalone_toolchain.md
# - https://android.googlesource.com/platform/ndk/+/master/docs/BuildSystemMaintainers.md
# - https://github.com/rust-lang/rust/blob/1.67.0/src/ci/docker/host-x86_64/dist-android/Dockerfile
# - https://github.com/rust-lang/rust/blob/1.67.0/src/ci/docker/scripts/android-ndk.sh

ARG RUST_TARGET
ARG UBUNTU_VERSION=18.04
ARG TOOLCHAIN_TAG=dev
ARG HOST_ARCH=amd64

ARG NDK_VERSION

FROM ghcr.io/taiki-e/downloader as ndk
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
RUN mkdir -p /ndk
RUN <<EOF
cd /ndk
ndk_file=android-ndk-r15c-linux-x86_64.zip
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused -O "https://dl.google.com/android/repository/${ndk_file}"
unzip -q "${ndk_file}"
rm "${ndk_file}"
mv android-ndk-* ndk
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get -o Acquire::Retries=10 update -qq && apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
    python3

COPY --from=ndk /ndk/ndk /ndk
ARG RUST_TARGET
ARG NDK_VERSION
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
RUN <<EOF
case "${RUST_TARGET}" in
    aarch64-*) android_arch=arm64 ;;
    arm* | thumb*) android_arch=arm ;;
    i686-*) android_arch=x86 ;;
    x86_64*) android_arch=x86_64 ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
# See https://developer.android.com/ndk/guides/standalone_toolchain
python3 /ndk/build/tools/make_standalone_toolchain.py \
    --install-dir "${TOOLCHAIN_DIR}" \
    --arch "${android_arch}" \
    --api "${NDK_VERSION}"
EOF

RUN <<EOF
case "${RUST_TARGET}" in
    arm* | thumb*) cc_target=arm-linux-androideabi ;;
    *) cc_target="${RUST_TARGET}" ;;
esac
echo "${cc_target}" >/CC_TARGET
EOF

RUN --mount=type=bind,target=/docker \
    /docker/base/common.sh

# TODO: libc++_shared.so is not installed by make_standalone_toolchain.py
# RUN <<EOF
# mkdir -p "${TOOLCHAIN_DIR}"/{lib,lib64}
# case "${RUST_TARGET}" in
#     aarch64-*) cp /ndk/sources/cxx-stl/llvm-libc++/libs/arm64-v8a/* "${TOOLCHAIN_DIR}"/sysroot/usr/lib/ ;;
#     arm-*) cp /ndk/sources/cxx-stl/llvm-libc++/libs/armeabi/* "${TOOLCHAIN_DIR}"/sysroot/usr/lib/ ;;
#     armv7-* | thumbv7*) cp /ndk/sources/cxx-stl/llvm-libc++/libs/armeabi-v7a/* "${TOOLCHAIN_DIR}"/sysroot/usr/lib/ ;;
#     i686-*) cp /ndk/sources/cxx-stl/llvm-libc++/libs/x86/* "${TOOLCHAIN_DIR}"/sysroot/usr/lib/ ;;
#     x86_64*) cp /ndk/sources/cxx-stl/llvm-libc++/libs/x86_64/* "${TOOLCHAIN_DIR}"/sysroot/usr/lib/ ;;
#     *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
# esac
# EOF

# RUN --mount=type=bind,target=/docker <<EOF
# case "${RUST_TARGET}" in
#     arm-*)
#         COMMON_FLAGS="-march=armv5te -mthumb -mfloat-abi=soft -D__ANDROID_API__=${NDK_VERSION} -D__ARM_ARCH_5TE__" \
#             CLANG="\$(dirname \$0)/clang50"
#             SYSROOT="\"\${toolchain_dir}\"/sysroot" \
#             /docker/clang-cross.sh
#         ;;
# esac
# EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as test-base
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
COPY /test-base.sh /
RUN /test-base.sh
ARG RUST_TARGET
COPY /test-base /test-base
RUN /test-base/target.sh
COPY /test /test
COPY --from=ghcr.io/taiki-e/qemu-user /usr/bin/qemu-* /usr/bin/

FROM test-base as test-relocated
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG NDK_VERSION
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh gcc
# TODO(arm-linux-androideabi): By default, arm-linux-androideabi-clang targets armv7a.
RUN <<EOF
case "${RUST_TARGET}" in
    arm-*) ;;
    *) /test/test.sh clang ;;
esac
EOF
RUN touch /DONE

FROM test-base as test
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG NDK_VERSION
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN /test/test.sh gcc
# TODO(arm-linux-androideabi): By default, arm-linux-androideabi-clang targets armv7a.
RUN <<EOF
case "${RUST_TARGET}" in
    arm-*) ;;
    *) /test/test.sh clang ;;
esac
EOF
# COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
