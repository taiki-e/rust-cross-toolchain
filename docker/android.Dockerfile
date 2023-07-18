# syntax=docker/dockerfile:1

# Refs:
# - https://developer.android.com/ndk
# - https://android.googlesource.com/platform/ndk/+/refs/heads/ndk-r15-release/docs/user/standalone_toolchain.md
# - https://android.googlesource.com/platform/ndk/+/master/docs/BuildSystemMaintainers.md
# - https://github.com/rust-lang/rust/blob/1.70.0/src/ci/docker/host-x86_64/dist-android/Dockerfile
# - https://github.com/rust-lang/rust/blob/1.70.0/src/ci/docker/scripts/android-ndk.sh

ARG RUST_TARGET
ARG UBUNTU_VERSION=20.04
ARG TOOLCHAIN_TAG=dev
ARG HOST_ARCH=amd64

ARG NDK_VERSION

FROM ghcr.io/taiki-e/downloader as ndk
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG NDK_VERSION
RUN mkdir -p /ndk
RUN <<EOF
cd /ndk
ndk_file="android-ndk-${NDK_VERSION}-linux.zip"
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused -O "https://dl.google.com/android/repository/${ndk_file}"
unzip -q "${ndk_file}"
rm "${ndk_file}"
mv android-ndk-* ndk
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive

ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
COPY --from=ndk /ndk/ndk/toolchains/llvm/prebuilt/linux-x86_64 "${TOOLCHAIN_DIR}"

RUN <<EOF
case "${RUST_TARGET}" in
    arm* | thumb*) cc_target=armv7a-linux-androideabi ;;
    *) cc_target="${RUST_TARGET}" ;;
esac
# Lowest API level
api_level=19
case "${RUST_TARGET}" in
    x86_64* | aarch64*) api_level=21 ;;
esac
echo "${cc_target}${api_level}" >/CC_TARGET
EOF

RUN --mount=type=bind,target=/docker \
    /docker/base/common.sh

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as test-base
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
COPY /test-base.sh /
RUN /test-base.sh
RUN apt-get -o Acquire::Retries=10 update -qq && apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
    e2tools
ARG RUST_TARGET
COPY --from=ndk /ndk/ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot /ndk-sysroot
# https://dl.google.com/android/repository/sys-img/android/sys-img.xml
RUN <<EOF
mkdir -p /system/{bin,lib,lib64}
# TODO: use 21 instead of 24 for 32-bit targets: libc: error getting old personality value: Operation not permitted
case "${RUST_TARGET}" in
    aarch64*)
        lib_target=aarch64-linux-android
        arch=arm64-v8a
        img_api_level=24
        revision=r07
        ;;
    arm* | thumb*)
        lib_target=arm-linux-androideabi
        arch=armeabi-v7a
        img_api_level=21
        revision=r04
        ;;
    i686-*)
        lib_target=i686-linux-android
        arch=x86
        img_api_level=21
        revision=r05
        ;;
    x86_64*)
        lib_target=x86_64-linux-android
        arch=x86_64
        img_api_level=24
        revision=r08
        ;;
    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
esac
file="${arch}-${img_api_level}_${revision}.zip"
prefix=''
case "${RUST_TARGET}" in
    x86_64* | aarch64*) prefix='64' ;;
esac
curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused -O "https://dl.google.com/android/repository/sys-img/android/${file}"
unzip -q "${file}" "${arch}/system.img"
e2cp -p "${arch}/system.img:/bin/linker${prefix}" "/system/bin/"
for lib in "ndk-sysroot/usr/lib/${lib_target}/${img_api_level}"/*.so; do
    lib=$(basename "${lib}")
    # TODO: error with img_api_level < 24: Attempt to read block from filesystem resulted in short readError copying file /lib/libGLESv3.so to /system/lib//libGLESv3.so
    e2cp -p "${arch}/system.img:/lib${prefix}/${lib}" "/system/lib${prefix}/" || true
done
cp "ndk-sysroot/usr/lib/${lib_target}/libc++_shared.so" "/system/lib${prefix}/"
rm "${file}"
rm -rf "${arch}"
EOF
ENV ANDROID_DNS_MODE=local
ENV ANDROID_ROOT=/system
ENV TMPDIR=/tmp/
COPY /test-base /test-base
RUN /test-base/target.sh
COPY /test /test
COPY --from=ghcr.io/taiki-e/qemu-user /usr/bin/qemu-* /usr/bin/

FROM test-base as test-relocated
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh clang
RUN touch /DONE

FROM test-base as test
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN /test/test.sh clang
# COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
