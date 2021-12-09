#!/bin/bash
set -euxo pipefail
IFS=$'\n\t'

# Test the toolchain.

bail() {
    echo >&2 "error: ${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}: $*"
    exit 1
}
assert_file_info() {
    local pat="$1"
    shift
    for bin in "$@"; do
        if ! file "${bin}" | grep -E "(\\b|^)${pat}(\\b|$)" >/dev/null; then
            bail "expected '${pat}', actually: $(file "${bin}")"
        fi
    done
}
assert_not_file_info() {
    local pat="$1"
    shift
    for bin in "$@"; do
        if ! file "${bin}" | grep -v "${pat}" >/dev/null; then
            bail
        fi
    done
}
assert_file_header() {
    local pat="$1"
    shift
    for bin in "$@"; do
        if ! readelf --file-header "${bin}" | grep -E "(\\b|^)${pat}(\\b|$)" >/dev/null; then
            bail "expected '${pat}', actually: $(readelf --file-header "${bin}")"
        fi
    done
}
assert_not_file_header() {
    local pat="$1"
    shift
    for bin in "$@"; do
        if ! readelf --file-header "${bin}" | grep -v "${pat}" >/dev/null; then
            bail
        fi
    done
}
assert_arch_specific() {
    local pat="$1"
    shift
    for bin in "$@"; do
        if ! readelf --arch-specific "${bin}" | grep -E "(\\b|^)${pat}(\\b|$)" >/dev/null; then
            bail "expected '${pat}', actually: $(readelf --arch-specific "${bin}")"
        fi
    done
}
assert_not_arch_specific() {
    local pat="$1"
    shift
    for bin in "$@"; do
        if ! readelf --arch-specific "${bin}" | grep -v "${pat}" >/dev/null; then
            bail
        fi
    done
}

export CARGO_NET_RETRY=10
export RUSTUP_MAX_RETRIES=10
# shellcheck disable=SC1091
. "${HOME}/.cargo/env"

cc="$1"

test_dir="/tmp/test-${cc}"
mkdir -p "${test_dir}"
cd "${test_dir}"
cp -r /test/fixtures/. ./

toolchain_dir="$(dirname "$(dirname "$(type -P "${RUST_TARGET}-${cc}")")")"
case "${RUST_TARGET}" in
    aarch64_be-unknown-linux-gnu | arm-unknown-linux-gnueabihf)
        sysroot_dir="${toolchain_dir}/${RUST_TARGET}/libc"
        # TODO
        export LD_LIBRARY_PATH="${toolchain_dir}/${RUST_TARGET}/libc/lib:${toolchain_dir}/${RUST_TARGET}/lib"
        ;;
    riscv32gc-unknown-linux-gnu)
        sysroot_dir="${toolchain_dir}/sysroot"
        # TODO
        export LD_LIBRARY_PATH="${toolchain_dir}/${RUST_TARGET}/lib:${toolchain_dir}/sysroot/lib:${toolchain_dir}/sysroot/usr/lib"
        ;;
    *) sysroot_dir="${toolchain_dir}/${RUST_TARGET}" ;;
esac
dev_tools_dir="/${RUST_TARGET}-dev"
mkdir -p "${dev_tools_dir}"

rust_target_lower="${RUST_TARGET//-/_}"
rust_target_lower="${rust_target_lower//./_}"
rust_target_upper="$(tr '[:lower:]' '[:upper:]' <<<"${rust_target_lower}")"
case "${cc}" in
    gcc)
        cxx=g++
        tee >"${dev_tools_dir}/${cc}.env" <<EOF
export AR_${rust_target_lower}=${RUST_TARGET}-ar
EOF
        ;;
    clang)
        cxx=clang++
        # https://www.kernel.org/doc/html/latest/kbuild/llvm.html#llvm-utilities
        tee >"${dev_tools_dir}/${cc}.env" <<EOF
export AR=llvm-ar
export NM=llvm-nm
export STRIP=llvm-strip
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export READELF=llvm-readelf
EOF
        ;;
esac
tee >>"${dev_tools_dir}/${cc}.env" <<EOF
export CC_${rust_target_lower}=${RUST_TARGET}-${cc}
export CXX_${rust_target_lower}=${RUST_TARGET}-${cxx}
export CARGO_TARGET_${rust_target_upper}_LINKER=${RUST_TARGET}-${cc}
EOF
case "${RUST_TARGET}" in
    *-musl* | *-redox*)
        # disable static linking to check interpreter
        export RUSTFLAGS="${RUSTFLAGS:-} -C target-feature=-crt-static"
        ;;
    *-wasi*)
        # cc-rs will try to link to libstdc++ by default.
        tee >>"${dev_tools_dir}/${cc}.env" <<EOF
export CXXSTDLIB=c++
EOF
        ;;
esac
case "${RUST_TARGET}" in
    powerpc-unknown-linux-musl | powerpc64-unknown-linux-musl | powerpc64le-unknown-linux-musl | s390x-unknown-linux-musl | thumbv7neon-unknown-linux-musleabihf)
        # TODO: -L* are needed to build std
        export RUSTFLAGS="${RUSTFLAGS:-} -L${toolchain_dir}/${RUST_TARGET}/lib -L${toolchain_dir}/lib/gcc/${RUST_TARGET}/${GCC_VERSION}"
        ;;
esac
# shellcheck disable=SC1090
. "${dev_tools_dir}/${cc}.env"
case "${RUST_TARGET}" in
    wasm*) exe=".wasm" ;;
    *-windows-*) exe=".exe" ;;
    *) exe="" ;;
esac

# Build C/C++.
pushd cpp >/dev/null
"${RUST_TARGET}-${cc}" -v
"${RUST_TARGET}-${cc}" -o c.out hello.c
case "${RUST_TARGET}" in
    arm*-unknown-linux-gnu* | thumbv7neon-unknown-linux-gnu*) ;;
    *) out+=("$(pwd)"/c.out) ;;
esac
case "${RUST_TARGET}" in
    # TODO(aarch64-unknown-openbsd): clang segfault
    aarch64-unknown-openbsd) ;;
    *)
        "${RUST_TARGET}-${cxx}" -v
        "${RUST_TARGET}-${cxx}" -o cpp.out hello.cpp
        case "${RUST_TARGET}" in
            arm*-unknown-linux-gnu* | thumbv7neon-unknown-linux-gnu*) ;;
            *) out+=("$(pwd)"/cpp.out) ;;
        esac
        ;;
esac
popd >/dev/null

# Build Rust with C/C++
pushd rust >/dev/null
if [[ -f /BUILD_STD ]]; then
    cargo build -Z build-std --offline --target "${RUST_TARGET}"
else
    cargo build --offline --target "${RUST_TARGET}"
fi
out+=(
    "$(pwd)/target/${RUST_TARGET}/debug/rust-test${exe}"
    "$(pwd)/target/${RUST_TARGET}"/debug/build/rust-test-*/out/hello_c.o
)
case "${RUST_TARGET}" in
    # TODO: See docker/test/fixtures/rust/build.rs
    aarch64-unknown-openbsd | wasm32-wasi) ;;
    *) out+=("$(pwd)/target/${RUST_TARGET}"/debug/build/rust-test-*/out/hello_cpp.o) ;;
esac
popd >/dev/null

# Build Rust with C using CMake
pushd rust-cmake >/dev/null
if [[ -f /BUILD_STD ]]; then
    cargo build -Z build-std --offline --target "${RUST_TARGET}"
else
    cargo build --offline --target "${RUST_TARGET}"
fi
out+=("$(pwd)/target/${RUST_TARGET}/debug/rust-cmake-test${exe}")
case "${RUST_TARGET}" in
    *-redox* | *-windows-*) out+=("$(pwd)/target/${RUST_TARGET}"/debug/build/rust-cmake-test-*/out/build/CMakeFiles/double.dir/double.obj) ;;
    *) out+=("$(pwd)/target/${RUST_TARGET}"/debug/build/rust-cmake-test-*/out/build/CMakeFiles/double.dir/double.o) ;;
esac
ls "$(pwd)/target/${RUST_TARGET}"/debug/build/rust-cmake-test-*/out/build/CMakeFiles/double.dir
popd >/dev/null

# Check the compiled binaries.
file "${out[@]}"
case "${RUST_TARGET}" in
    *-wasi* | *-windows-*) ;;
    *)
        readelf --file-header "${out[@]}"
        readelf --arch-specific "${out[@]}"
        ;;
esac
file_info_pat=()     # file
file_info_not=()     # file
file_header_pat=()   # readelf --file-header
file_header_not=()   # readelf --file-header
arch_specific_pat=() # readelf --arch-specific
arch_specific_not=() # readelf --arch-specific
case "${RUST_TARGET}" in
    *-linux-* | *-freebsd* | *-netbsd* | *-openbsd* | *-dragonfly* | *-solaris* | *-illumos* | *-redox*)
        case "${RUST_TARGET}" in
            arm* | i*86-* | mipsel-* | mipsisa32r6el-* | riscv32gc-* | thumbv7neon-* | x86_64-*x32)
                file_info_pat+=('ELF 32-bit LSB')
                file_header_pat+=('Class:\s+ELF32' 'little endian')
                ;;
            mips-* | mipsisa32r6-* | powerpc-*)
                file_info_pat+=('ELF 32-bit MSB')
                file_header_pat+=('Class:\s+ELF32' 'big endian')
                ;;
            aarch64-* | mips64el-* | mipsisa64r6el-* | powerpc64le-* | riscv64gc-* | x86_64-*)
                file_info_pat+=('ELF 64-bit LSB')
                file_header_pat+=('Class:\s+ELF64' 'little endian')
                ;;
            aarch64_be-* | mips64-* | mipsisa64r6-* | powerpc64-* | sparc64-* | sparcv9-* | s390x-*)
                file_info_pat+=('ELF 64-bit MSB')
                file_header_pat+=('Class:\s+ELF64' 'big endian')
                ;;
            *) bail "unrecognized target '${RUST_TARGET}'" ;;
        esac
        case "${RUST_TARGET}" in
            aarch64-* | aarch64_be-*)
                file_info_pat+=('ARM aarch64')
                file_header_pat+=('Machine:\s+AArch64')
                ;;
            arm* | thumbv7neon-*)
                file_info_pat+=('ARM, EABI5')
                file_header_pat+=('Machine:\s+ARM' 'Flags:.*Version5 EABI')
                case "${RUST_TARGET}" in
                    *hf)
                        file_header_pat+=('(Flags:.*hard-float ABI)?')
                        file_header_not+=('soft-float ABI')
                        arch_specific_pat+=('Tag_ABI_VFP_args: VFP registers')
                        ;;
                    *)
                        file_header_pat+=('(Flags:.*soft-float ABI)?')
                        file_header_not+=('hard-float ABI')
                        arch_specific_not+=('VFP registers')
                        ;;
                esac
                case "${RUST_TARGET}" in
                    arm-*hf) arch_specific_pat+=('Tag_CPU_arch: v6' 'Tag_THUMB_ISA_use: Thumb-1' 'Tag_FP_arch: VFPv2') ;;
                    arm-*) arch_specific_pat+=('Tag_CPU_arch: v6' 'Tag_THUMB_ISA_use: Thumb-1') ;;
                    armv4t-*) arch_specific_pat+=('Tag_CPU_arch: v4T' 'Tag_THUMB_ISA_use: Thumb-1') ;;
                    # TODO
                    armv5te-*-uclibceabi) arch_specific_pat+=('Tag_CPU_arch: v5TE(J)?' 'Tag_THUMB_ISA_use: Thumb-1') ;;
                    armv5te-*) arch_specific_pat+=('Tag_CPU_arch: v5TE' 'Tag_THUMB_ISA_use: Thumb-1') ;;
                    armv7-*hf) arch_specific_pat+=('Tag_CPU_arch: v7' 'Tag_CPU_arch_profile: Application' 'Tag_THUMB_ISA_use: Thumb-2' 'Tag_FP_arch: VFPv3-D16') ;;
                    armv7-*) arch_specific_pat+=('Tag_CPU_arch: v7' 'Tag_CPU_arch_profile: Application' 'Tag_THUMB_ISA_use: Thumb-2') ;;
                    thumbv7neon-*) arch_specific_pat+=('Tag_CPU_arch: v7' 'Tag_CPU_arch_profile: Application' 'Tag_THUMB_ISA_use: Thumb-2' 'Tag_FP_arch: VFPv4' 'Tag_Advanced_SIMD_arch: NEONv1 with Fused-MAC') ;;
                    *) bail "unrecognized target '${RUST_TARGET}'" ;;
                esac
                ;;
            i*86-*)
                file_info_pat+=('Intel 80386')
                file_header_pat+=('Machine:\s+Intel 80386')
                ;;
            mips-* | mipsel-*)
                file_info_pat+=('MIPS')
                file_header_pat+=('Machine:\s+MIPS R3000')
                # mips(el)-buildroot-linux-uclibc-gcc/g++'s default is -march=mips32
                case "${RUST_TARGET}" in
                    *-linux-uclibc*)
                        file_info_pat+=('MIPS32( rel2)?')
                        file_header_pat+=('(Flags:.*mips32r2)?')
                        arch_specific_pat+=('ISA: MIPS32(r2)?')
                        ;;
                    *)
                        file_info_pat+=('MIPS32 rel2')
                        file_header_pat+=('Flags:.*mips32r2')
                        arch_specific_pat+=('ISA: MIPS32r2')
                        ;;
                esac
                case "${RUST_TARGET}" in
                    *-linux-gnu*) arch_specific_pat+=('FP ABI: Hard float \(32-bit CPU, Any FPU\)') ;;
                    *-linux-musl*) arch_specific_pat+=('FP ABI: Soft float') ;;
                        # TODO: should be soft float?
                    *-linux-uclibc*) arch_specific_pat+=('FP ABI: Hard float \(32-bit CPU, Any FPU\)') ;;
                    *) bail "unrecognized target '${RUST_TARGET}'" ;;
                esac
                ;;
            mips64-* | mips64el-*)
                file_info_pat+=('MIPS' 'MIPS64 rel2')
                file_header_pat+=('Machine:\s+MIPS R3000' 'Flags:.*mips64r2')
                arch_specific_pat+=('ISA: MIPS64r2')
                arch_specific_pat+=('FP ABI: Hard float \(double precision\)')
                ;;
            mipsisa32r6-* | mipsisa32r6el-*)
                file_info_pat+=('MIPS' 'MIPS32 rel6')
                file_header_pat+=('Machine:\s+MIPS R3000' 'Flags:.*mips32r6')
                arch_specific_pat+=('ISA: MIPS32r6')
                arch_specific_pat+=('FP ABI: Hard float \(32-bit CPU, 64-bit FPU\)')
                ;;
            mipsisa64r6-* | mipsisa64r6el-*)
                file_info_pat+=('MIPS' 'MIPS64 rel6')
                file_header_pat+=('Machine:\s+MIPS R3000' 'Flags:.*mips64r6')
                arch_specific_pat+=('ISA: MIPS64r6')
                arch_specific_pat+=('FP ABI: Hard float \(double precision\)')
                ;;
            powerpc-*)
                file_info_pat+=('PowerPC or cisco 4500')
                file_header_pat+=('Machine:\s+PowerPC')
                ;;
            powerpc64-* | powerpc64le-*)
                file_info_pat+=('64-bit PowerPC or cisco 7500')
                file_header_pat+=('Machine:\s+PowerPC64')
                case "${RUST_TARGET}" in
                    powerpc64le-* | *-linux-musl* | *-freebsd*)
                        file_info_pat+=('(OpenPOWER ELF V2 ABI)?')
                        file_header_pat+=('Flags:.*abiv2')
                        ;;
                    *)
                        file_info_not+=('OpenPOWER ELF V2 ABI')
                        file_header_pat+=('(Flags:.*abiv1)?')
                        file_header_not+=('Flags:.*abiv2')
                        ;;
                esac
                ;;
            riscv32gc-*)
                file_info_pat+=('UCB RISC-V')
                # TODO: Flags
                file_header_pat+=('Machine:\s+RISC-V')
                ;;
            riscv64gc-*)
                file_info_pat+=('UCB RISC-V')
                file_header_pat+=('Machine:\s+RISC-V' 'Flags:.*RVC, double-float ABI')
                ;;
            s390x-*)
                file_info_pat+=('IBM S/390')
                file_header_pat+=('Machine:\s+IBM S/390')
                ;;
            sparc64-* | sparcv9-*)
                file_info_pat+=('SPARC V9')
                file_header_pat+=('Machine:\s+Sparc v9')
                ;;
            x86_64-*)
                file_info_pat+=('x86-64')
                file_header_pat+=('Machine:\s+Advanced Micro Devices X86-64')
                ;;
            *) bail "unrecognized target '${RUST_TARGET}'" ;;
        esac
        case "${RUST_TARGET}" in
            *-freebsd*) file_header_pat+=('OS/ABI:\s+UNIX - FreeBSD') ;;
            *-linux-gnu*) file_header_pat+=('OS/ABI:\s+UNIX - (System V|GNU)') ;;
            *) file_header_pat+=('OS/ABI:\s+UNIX - System V') ;;
        esac
        case "${RUST_TARGET}" in
            *-linux-gnu*)
                case "${RUST_TARGET}" in
                    aarch64-*) ldso='/lib/ld-linux-aarch64\.so\.1' ;;
                    aarch64_be-*) ldso='/lib/ld-linux-aarch64_be\.so\.1' ;;
                    arm*hf | thumbv7neon-*) ldso='/lib/ld-linux-armhf\.so\.3' ;;
                    arm*) ldso='/lib/ld-linux\.so\.3' ;;
                    i586-* | i686-*) ldso='/lib/ld-linux\.so\.2' ;;
                    mips-* | mipsel-*) ldso='/lib/ld\.so\.1' ;;
                    mips64-* | mips64el-*) ldso='/lib64/ld\.so\.1' ;;
                    mipsisa32r6-* | mipsisa32r6el-*) ldso='/lib/ld-linux-mipsn8\.so\.1' ;;
                    mipsisa64r6-* | mipsisa64r6el-*) ldso='/lib64/ld-linux-mipsn8\.so\.1' ;;
                    powerpc-*) ldso='/lib/ld\.so\.1' ;;
                    powerpc64-*) ldso='/lib64/ld64\.so\.1' ;;
                    powerpc64le-*) ldso='/lib64/ld64\.so\.2' ;;
                    riscv32gc-*) ldso='/lib/ld-linux-riscv32-ilp32d\.so\.1' ;;
                    riscv64gc-*) ldso='/lib/ld-linux-riscv64-lp64d\.so\.1' ;;
                    s390x-*) ldso='/lib/ld64\.so\.1' ;;
                    sparc64-*) ldso='/lib64/ld-linux\.so\.2' ;;
                    x86_64-*x32) ldso='/libx32/ld-linux-x32\.so\.2' ;;
                    *) bail "unrecognized target '${RUST_TARGET}'" ;;
                esac
                file_info_pat+=("interpreter ${ldso}")
                ;;
            *-linux-musl*)
                case "${RUST_TARGET}" in
                    aarch64-*) ldso_arch=aarch64 ;;
                    arm*hf | thumbv7neon-*) ldso_arch=armhf ;;
                    arm*) ldso_arch=arm ;;
                    hexagon-*) ldso_arch=hexagon ;;
                    i*86-*) ldso_arch=i386 ;;
                    mips-*)
                        # TODO
                        if [[ "${cc}" == "clang" ]]; then
                            ldso_arch=mips
                        else
                            ldso_arch=mips-sf
                        fi
                        ;;
                    mips64-*) ldso_arch=mips64 ;;
                    mips64el-*) ldso_arch=mips64el ;;
                    mipsel-*)
                        # TODO
                        if [[ "${cc}" == "clang" ]]; then
                            ldso_arch=mipsel
                        else
                            ldso_arch=mipsel-sf
                        fi
                        ;;
                    powerpc-*) ldso_arch=powerpc ;;
                    powerpc64-*) ldso_arch=powerpc64 ;;
                    powerpc64le-*) ldso_arch=powerpc64le ;;
                    riscv32gc-*) ldso_arch=riscv32 ;;
                    riscv64gc-*) ldso_arch=riscv64 ;;
                    s390x-*) ldso_arch=s390x ;;
                    x86_64-*) ldso_arch=x86_64 ;;
                    *) bail "unrecognized target '${RUST_TARGET}'" ;;
                esac
                file_info_pat+=("interpreter /lib/ld-musl-${ldso_arch}\\.so\\.1")
                ;;
            *-linux-uclibc*)
                case "${cc}" in
                    clang)
                        # TODO
                        case "${RUST_TARGET}" in
                            armv5te-*) file_info_pat+=('interpreter /lib/ld-linux\.so\.3') ;;
                            armv7-*) file_info_pat+=('interpreter /lib/ld-linux-armhf\.so\.3') ;;
                            mips-* | mipsel-*) file_info_pat+=('interpreter /lib/ld\.so\.1') ;;
                            *) bail "unrecognized target '${RUST_TARGET}'" ;;
                        esac
                        ;;
                    *) file_info_pat+=('interpreter /lib/ld-uClibc\.so\.0') ;;
                esac
                ;;
            *-freebsd*)
                # Rust binary doesn't include version info
                assert_file_info "for FreeBSD ${FREEBSD_VERSION}" "${out[0]}" "${out[1]}"
                file_info_pat+=('FreeBSD')
                for bin in "${out[@]}"; do
                    if [[ -x "${bin}" ]]; then
                        assert_file_info 'interpreter /libexec/ld-elf\.so\.1' "${bin}"
                        assert_file_info 'FreeBSD-style' "${bin}"
                    fi
                done
                ;;
            *-netbsd*)
                for bin in "${out[@]}"; do
                    if [[ -x "${bin}" ]]; then
                        assert_file_info 'interpreter /libexec/ld\.elf_so' "${bin}"
                        assert_file_info "for NetBSD ${NETBSD_VERSION}" "${bin}"
                    fi
                done
                ;;
            *-openbsd*)
                for bin in "${out[@]}"; do
                    if [[ -x "${bin}" ]]; then
                        assert_file_info 'interpreter /usr/libexec/ld\.so' "${bin}"
                        # version info is not included
                        assert_file_info "for OpenBSD" "${bin}"
                    fi
                done
                ;;
            *-dragonfly*)
                for bin in "${out[@]}"; do
                    if [[ -x "${bin}" ]]; then
                        assert_file_info 'interpreter /usr/libexec/ld-elf\.so\.2' "${bin}"
                        assert_file_info "for DragonFly ${DRAGONFLY_VERSION%.*}" "${bin}"
                    fi
                done
                ;;
            *-solaris* | *-illumos*)
                case "${RUST_TARGET}" in
                    sparcv9-*) file_info_pat+=('interpreter /usr/lib/sparcv9/ld\.so\.1') ;;
                    x86_64-*) file_info_pat+=('interpreter /lib/amd64/ld\.so\.1') ;;
                    *) bail "unrecognized target '${RUST_TARGET}'" ;;
                esac
                ;;
            *-redox*) file_info_pat+=('interpreter /lib/ld64\.so\.1') ;;
            *) bail "unrecognized target '${RUST_TARGET}'" ;;
        esac
        ;;
    *-wasi*)
        file_info_pat+=('WebAssembly \(wasm\) binary module version 0x1 \(MVP\)')
        ;;
    *-windows-gnu*)
        for bin in "${out[@]}"; do
            if [[ -x "${bin}" ]]; then
                case "${RUST_TARGET}" in
                    i686-*) assert_file_info 'PE32 executable \(console\) Intel 80386' "${bin}" ;;
                    x86_64-*) assert_file_info 'PE32\+ executable \(console\) x86-64' "${bin}" ;;
                    *) bail "unrecognized target '${RUST_TARGET}'" ;;
                esac
                assert_file_info 'for MS Windows' "${bin}"
            fi
        done
        ;;
    *) bail "unrecognized target '${RUST_TARGET}'" ;;
esac
for bin in "${out[@]}"; do
    for pat in "${file_info_pat[@]}"; do
        if [[ ! -x "${bin}" ]] && [[ "${pat}" == "interpreter "* ]]; then
            continue
        fi
        assert_file_info "${pat}" "${bin}"
    done
    for pat in "${file_info_not[@]}"; do
        assert_not_file_info "${pat}" "${bin}"
    done
    for pat in "${file_header_pat[@]}"; do
        assert_file_header "${pat}" "${bin}"
    done
    for pat in "${file_header_not[@]}"; do
        assert_not_file_header "${pat}" "${bin}"
    done
    for pat in "${arch_specific_pat[@]}"; do
        assert_arch_specific "${pat}" "${bin}"
    done
    for pat in "${arch_specific_not[@]}"; do
        assert_not_arch_specific "${pat}" "${bin}"
    done
done

# Run the compiled binaries.
# For now, this will only run on linux and wasi.
# TODO(freebsd): can we use vm or ci images for testing? https://download.freebsd.org/ftp/releases/VM-IMAGES https://download.freebsd.org/ftp/releases/CI-IMAGES
case "${RUST_TARGET}" in
    # TODO(riscv32gc-unknown-linux-gnu): libstd's io-related feature on riscv32 linux is broken: https://github.com/rust-lang/rust/issues/88995
    # TODO(x86_64-unknown-linux-gnux32): Invalid ELF image for this architecture
    riscv32gc-unknown-linux-gnu | x86_64-unknown-linux-gnux32) ;;
    *-unknown-linux-*)
        case "${RUST_TARGET}" in
            aarch64-* | aarch64_be-*)
                qemu_arch="${RUST_TARGET%%-*}"
                export QEMU_CPU=cortex-a72
                ;;
            arm* | thumbv7neon-*)
                qemu_arch=arm
                case "${RUST_TARGET}" in
                    # ARMv6: https://en.wikipedia.org/wiki/ARM11
                    arm-*) export QEMU_CPU=arm11mpcore ;;
                    # ARMv4: https://en.wikipedia.org/wiki/StrongARM
                    armv4t-*) export QEMU_CPU=sa1110 ;;
                    # ARMv5TE
                    armv5te-*) export QEMU_CPU=arm1026 ;;
                    # ARMv7-A+NEONv2
                    armv7-* | thumbv7neon-*) export QEMU_CPU=cortex-a15 ;;
                    *) bail "unrecognized target '${RUST_TARGET}'" ;;
                esac
                ;;
            i*86-*) qemu_arch=i386 ;;
            hexagon-*) qemu_arch=hexagon ;;
            m68k-*) qemu_arch=m68k ;;
            mips-* | mipsel-*) qemu_arch="${RUST_TARGET%%-*}" ;;
            mips64-* | mips64el-*)
                qemu_arch="${RUST_TARGET%%-*}"
                # As of qemu 6.1, only Loongson-3A4000 supports MSA instructions with mips64r5.
                export QEMU_CPU=Loongson-3A4000
                ;;
            mipsisa32r6-* | mipsisa32r6el-*)
                qemu_arch="${RUST_TARGET%%-*}"
                qemu_arch="${qemu_arch/isa32r6/}"
                export QEMU_CPU=mips32r6-generic
                ;;
            mipsisa64r6-* | mipsisa64r6el-*)
                qemu_arch="${RUST_TARGET%%-*}"
                qemu_arch="${qemu_arch/isa64r6/64}"
                export QEMU_CPU=I6400
                ;;
            powerpc-*spe)
                qemu_arch=ppc
                export QEMU_CPU=e500v2
                ;;
            powerpc-*)
                qemu_arch=ppc
                export QEMU_CPU=Vger
                ;;
            powerpc64-*)
                qemu_arch=ppc64
                export QEMU_CPU=power10
                ;;
            powerpc64le-*)
                qemu_arch=ppc64le
                export QEMU_CPU=power10
                ;;
            riscv32gc-* | riscv64gc-*) qemu_arch="${RUST_TARGET%%gc-*}" ;;
            s390x-*) qemu_arch=s390x ;;
            sparc-*) qemu_arch=sparc32plus ;;
            sparc64-*) qemu_arch=sparc64 ;;
            x86_64-*) qemu_arch=x86_64 ;;
            *) bail "unrecognized target '${RUST_TARGET}'" ;;
        esac
        runner="qemu-${qemu_arch}"
        export "CARGO_TARGET_${rust_target_upper}_RUNNER"="${runner}"
        export QEMU_LD_PREFIX="${sysroot_dir}"
        for bin in "${out[@]}"; do
            if [[ ! -x "${bin}" ]]; then
                continue
            fi
            case "${RUST_TARGET}" in
                armv5te-unknown-linux-uclibceabi | armv7-unknown-linux-uclibceabihf)
                    # TODO: qemu: uncaught target signal 11 (Segmentation fault) - core dumped
                    if [[ "${cc}" == "clang" ]] && [[ "${bin}" == *"cpp.out" ]]; then
                        continue
                    fi
                    ;;
            esac
            "${runner}" "${bin}" | tee run.log
            if ! grep <run.log -E '^Hello (C|C\+\+|Rust|C from Rust|C\+\+ from Rust|Cmake from Rust)!' >/dev/null; then
                bail
            fi
        done
        ;;
    *-wasi*)
        runner=wasmtime
        case "${RUST_TARGET}" in
            wasm32-*) runner_flags=(--enable-simd --) ;;
            wasm64-*) runner_flags=(--enable-simd --enable-memory64 --) ;;
            *) bail "unrecognized target '${RUST_TARGET}'" ;;
        esac
        export "CARGO_TARGET_${rust_target_upper}_RUNNER"="${runner} ${runner_flags[*]}"
        for bin in "${out[@]}"; do
            if [[ ! -x "${bin}" ]]; then
                continue
            fi
            "${runner}" "${runner_flags[@]}" "${bin}" | tee run.log
            if ! grep <run.log -E '^Hello (C|C\+\+|Rust|C from Rust|C\+\+ from Rust|Cmake from Rust)!' >/dev/null; then
                bail
            fi
        done
        ;;
esac
if [[ -n "${runner:-}" ]]; then
    case "${RUST_TARGET}" in
        # TODO(powerpc-unknown-linux-gnuspe): run-pass, but test-fail: process didn't exit successfully: `qemu-ppc /tmp/test-gcc/rust/target/powerpc-unknown-linux-gnuspe/debug/deps/rust_test-14b6784dbe26b668` (signal: 4, SIGILL: illegal instruction)
        powerpc-unknown-linux-gnuspe) ;;
        *)
            pushd rust >/dev/null
            if [[ -f /BUILD_STD ]]; then
                cargo test -Z build-std --offline --target "${RUST_TARGET}"
            else
                cargo test --offline --target "${RUST_TARGET}"
            fi
            popd >/dev/null
            ;;
    esac

    if [[ -d "${dev_tools_dir}/bin" ]]; then
        if [[ ! -f "${dev_tools_dir}/bin/${runner}" ]]; then
            cp "$(type -P "${runner}")" "${dev_tools_dir}/bin/${runner}"
        fi
    fi
fi
