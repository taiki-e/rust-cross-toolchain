#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -euo pipefail
IFS=$'\n\t'

# shellcheck disable=SC2154
trap 's=$?; echo >&2 "$0: error on line "${LINENO}": ${BASH_COMMAND}"; exit ${s}' ERR

# Refs:
# - https://clang.llvm.org/docs/CrossCompilation.html
# - https://mcilloni.ovh/2021/02/09/cxx-cross-clang

set -x

case "${RUST_TARGET}" in
    *-linux-musl* | *-linux-gnu* | *-freebsd* | *-netbsd* | *-openbsd*) cc_target="${CC_TARGET:-"$(</CC_TARGET)"}" ;;
    *) cc_target="${CC_TARGET:-"${RUST_TARGET}"}" ;;
esac
common_flags=""
common_flags_last=""
case "${RUST_TARGET}" in
    # The --target option is last because the cross-build of LLVM uses
    # --target without an OS version.
    # https://github.com/rust-lang/rust/blob/1.67.0/src/ci/docker/scripts/freebsd-toolchain.sh#L70-L75
    *-freebsd* | *-openbsd*) common_flags_last+=" --target=${cc_target}" ;;
    *) common_flags+=" --target=${cc_target}" ;;
esac

case "${RUST_TARGET}" in
    *-unknown-linux-*)
        case "${RUST_TARGET}" in
            arm-*hf) common_flags+=" -march=armv6 -marm -mfpu=vfp -mfloat-abi=hard" ;;
            arm-*) common_flags+=" -march=armv6 -marm -mfloat-abi=soft" ;;
            armv4t-*) common_flags+=" -march=armv4t -marm -mfloat-abi=soft" ;;
            armv5te-*) common_flags+=" -march=armv5te -marm -mfloat-abi=soft" ;;
            armv7-*hf) common_flags+=" -march=armv7-a -mthumb -mfpu=vfpv3-d16 -mfloat-abi=hard" ;;
            armv7-*) common_flags+=" -march=armv7-a -mthumb -mfloat-abi=softfp" ;;
            mips-* | mipsel-*)
                common_flags+=" -march=mips32r2"
                case "${RUST_TARGET}" in
                    *-linux-musl*) common_flags+=" -mfloat-abi=soft" ;;
                esac
                ;;
            thumbv7neon-*) common_flags+=" -march=armv7-a -mthumb -mfpu=neon-vfpv4 -mfloat-abi=hard" ;;
        esac
        ;;
    powerpc64-unknown-freebsd) common_flags+=" -mabi=elfv2" ;;
esac
case "${SYSROOT:-}" in
    none) ;;
    "") common_flags+=" --sysroot=\"\${toolchain_dir}\"/${RUST_TARGET}" ;;
    *) common_flags+=" --sysroot=${SYSROOT}" ;;
esac
common_flags+="${COMMON_FLAGS:+" ${COMMON_FLAGS}"}"
common_flags_last+="${COMMON_FLAGS_LAST:+" ${COMMON_FLAGS_LAST}"}"

cflags="${common_flags}${CFLAGS:+" ${CFLAGS}"}"
cflags_last="${common_flags_last}${CFLAGS_LAST:+" ${CFLAGS_LAST}"}"
cxxflags="${common_flags}${CXXFLAGS:+" ${CXXFLAGS}"}"
cxxflags_last="${common_flags_last}${CXXFLAGS_LAST:+" ${CXXFLAGS_LAST}"}"
case "${RUST_TARGET}" in
    *-linux-gnu* | *-netbsd* | *-dragonfly* | *-redox* | *-windows-gnu*)
        cxxflags=" -stdlib=libstdc++ ${cxxflags}"
        ;;
    *-freebsd* | *-openbsd*)
        cxxflags=" -stdlib=libc++ ${cxxflags}"
        ;;
esac

# -Wno-unused-command-line-argument is needed to silence
# "argument unused during compilation" warning.
case "${cflags}${cflags_last}" in
    *" -fuse-ld"* | *" --ld-path"* | *" --gcc-toolchain"* | *" -L"* | *" -dynamic-linker"*)
        cflags=" -Wno-unused-command-line-argument${cflags}"
        ;;
esac
case "${cxxflags}${cxxflags_last}" in
    *" -fuse-ld"* | *" --ld-path"* | *" --gcc-toolchain"* | *" -L"* | *" -dynamic-linker"*)
        cxxflags=" -Wno-unused-command-line-argument${cxxflags}"
        ;;
esac

# Get the directory of the toolchain dynamically so that it does not depend on
# the installation location of the toolchain.
if [[ "${cflags}${cflags_last}" == *"{toolchain_dir}"* ]] || [[ "${cxxflags}${cxxflags_last}" == *"{toolchain_dir}"* ]]; then
    get_toolchain_dir="toolchain_dir=\"\$(cd \"\$(dirname \"\$0\")\"/.. && pwd)\"
"
fi

mkdir -p "${TOOLCHAIN_DIR}/bin"
cat >"${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-clang" <<EOF
#!/bin/sh
set -eu
${get_toolchain_dir:-}exec ${CLANG:-clang}${cflags} "\$@"${cflags_last}
EOF
cat >"${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-clang++" <<EOF
#!/bin/sh
set -eu
${get_toolchain_dir:-}exec ${CLANG:-clang}++${cxxflags} "\$@"${cxxflags_last}
EOF
chmod +x "${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-clang" "${TOOLCHAIN_DIR}/bin/${RUST_TARGET}-clang++"
