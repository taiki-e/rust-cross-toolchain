# syntax=docker/dockerfile:1.3-labs

ARG UBUNTU_VERSION=18.04

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG UBUNTU_VERSION
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
RUN mkdir -p "${TOOLCHAIN_DIR}"

COPY /linux-gnu.sh /
RUN /linux-gnu.sh
# fd -t d '\b(doc|lintian|locale|i18n|man)\b'
RUN <<EOF
cc_target="$(</CC_TARGET)"
rm -rf "${TOOLCHAIN_DIR}"/share/{doc,lintian,locale,man}
case "${RUST_TARGET}" in
    aarch64_be-* | arm-*hf)
        rm -rf "${TOOLCHAIN_DIR}/${cc_target}"/libc/usr/share/{i18n,locale}
        ;;
    riscv32gc-*)
        rm -rf "${TOOLCHAIN_DIR}"/sysroot/usr/share/{i18n,locale}
        ;;
esac
case "${RUST_TARGET}" in
    # There are {include,lib,libexec} for both gcc 9.4.0 and 6.3.0
    arm-*hf) rm -rf $(find "${TOOLCHAIN_DIR}" -name '6.3.0') $(find "${TOOLCHAIN_DIR}" -name '*gcc-6.3.0') ;;
    # libc6-dev-armhf-cross (g++-arm-linux-gnueabihf) contains /usr/arm-linux-gnueabi/{lib/hf,libhf}
    arm*hf | thumbv7neon-*) rm -rf "${TOOLCHAIN_DIR}/arm-linux-gnueabi" ;;
    # libc6-dev-armel-cross (g++-arm-linux-gnueabi) contains /usr/arm-linux-gnueabihf/{lib/sf,libsf}
    arm*) rm -rf "${TOOLCHAIN_DIR}/arm-linux-gnueabihf" ;;
esac
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
gcc_version="$(</GCC_VERSION)"
case "${RUST_TARGET}" in
    aarch64_be-* | arm-*hf)
        COMMON_FLAGS="--gcc-toolchain=\"\${toolchain_dir}\"" \
            CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version} -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version}/${RUST_TARGET}" \
            SYSROOT="\"\${toolchain_dir}\"/${RUST_TARGET}/libc" \
            /clang-cross.sh
        ;;
    riscv32gc-*)
        COMMON_FLAGS="--gcc-toolchain=\"\${toolchain_dir}\" --ld-path=\"\${toolchain_dir}\"/bin/${RUST_TARGET}-ld -I\"\${toolchain_dir}\"/sysroot/usr/include" \
            CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version} -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version}/${RUST_TARGET}" \
            SYSROOT="\"\${toolchain_dir}\"/sysroot" \
            /clang-cross.sh
        ;;
    *)
        COMMON_FLAGS="--gcc-toolchain=\"\${toolchain_dir}\" -B\"\${toolchain_dir}\"/${RUST_TARGET}/bin -L\"\${toolchain_dir}\"/${RUST_TARGET}/lib -L${TOOLCHAIN_DIR}/lib/gcc-cross/${RUST_TARGET}/${gcc_version%%.*}" \
            CFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include" \
            CXXFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${gcc_version%%.*}/${RUST_TARGET}" \
            SYSROOT=none \
            /clang-cross.sh
        ;;
esac
EOF

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as test-base
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
COPY /test-base.sh /
RUN /test-base.sh
ARG RUST_TARGET
COPY /test-base-target.sh /
RUN /test-base-target.sh
COPY /test /test
COPY --from=ghcr.io/taiki-e/qemu-user /usr/bin/qemu-* /usr/bin/

FROM test-base as test-relocated
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
# NOTE: currently works only on this location
COPY --from=builder /"${RUST_TARGET}"/. /usr/
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
# TODO
RUN NO_RUN=1 /test/test.sh gcc
RUN NO_RUN=1 /test/test.sh clang
COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
