#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Test the toolchain.

x() {
    local cmd="$1"
    shift
    (
        set -x
        "$cmd" "$@"
    )
}
bail() {
    echo >&2 "error: ${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}: $*"
    exit 1
}
run_cargo() {
    local cargo_flags=()
    if [[ -n "${no_rust_cpp}" ]]; then
        cargo_flags+=(--no-default-features)
    fi
    if [[ -f /BUILD_STD ]]; then
        if [[ "${RUSTFLAGS:-}" == *"panic=abort"* ]]; then
            cargo_flags+=(-Z build-std="panic_abort,std")
        else
            cargo_flags+=(-Z build-std)
        fi
    fi
    subcmd="$1"
    shift
    x cargo "${subcmd}" --offline --target "${RUST_TARGET}" ${cargo_flags[@]+"${cargo_flags[@]}"} "$@"
}
assert_file_info() {
    local pat="$1"
    shift
    for bin in "$@"; do
        echo -n "info: checking file info pattern '${pat}' in ${bin} ..."
        if ! file "${bin}" | grep -E "(\\b|^)${pat}(\\b|$)" >/dev/null; then
            echo "failed"
            echo "error: expected '${pat}' in ${bin}, actually:"
            x file "${bin}"
            exit 1
        fi
        echo "ok"
    done
}
assert_not_file_info() {
    local pat="$1"
    shift
    for bin in "$@"; do
        echo -n "info: checking file info pattern (not) '${pat}' in ${bin} ..."
        if ! file "${bin}" | grep -v "${pat}" >/dev/null; then
            echo "failed"
            echo "error: unexpected '${pat}' in ${bin}:"
            x file "${bin}"
            exit 1
        fi
        echo "ok"
    done
}
assert_file_header() {
    local pat="$1"
    shift
    for bin in "$@"; do
        echo -n "info: checking file header pattern '${pat}' in ${bin} ..."
        if ! readelf --file-header "${bin}" | grep -E "(\\b|^)${pat}(\\b|$)" >/dev/null; then
            echo "failed"
            echo "error: expected '${pat}' in ${bin}, actually:"
            x readelf --file-header "${bin}"
            exit 1
        fi
        echo "ok"
    done
}
assert_not_file_header() {
    local pat="$1"
    shift
    for bin in "$@"; do
        echo -n "info: checking file header pattern (not) '${pat}' in ${bin} ..."
        if ! readelf --file-header "${bin}" | grep -v "${pat}" >/dev/null; then
            echo "failed"
            echo "error: unexpected '${pat}' in ${bin}:"
            x readelf --file-header "${bin}"
            exit 1
        fi
        echo "ok"
    done
}
assert_arch_specific() {
    local pat="$1"
    shift
    for bin in "$@"; do
        echo -n "info: checking file header pattern '${pat}' in ${bin} ..."
        if ! readelf --arch-specific "${bin}" | grep -E "(\\b|^)${pat}(\\b|$)" >/dev/null; then
            echo "failed"
            echo "error: expected '${pat}' in ${bin}, actually:"
            x readelf --arch-specific "${bin}"
            exit 1
        fi
        echo "ok"
    done
}
assert_not_arch_specific() {
    local pat="$1"
    shift
    for bin in "$@"; do
        echo -n "info: checking file header pattern (not) '${pat}' in ${bin} ..."
        if ! readelf --arch-specific "${bin}" | grep -v "${pat}" >/dev/null; then
            echo "failed"
            echo "error: unexpected '${pat}' in ${bin}:"
            x readelf --arch-specific "${bin}"
            exit 1
        fi
        echo "ok"
    done
}

export CARGO_NET_RETRY=10
export RUST_BACKTRACE=1
export RUSTUP_MAX_RETRIES=10
# shellcheck disable=SC1091
. "${HOME}/.cargo/env"

cc="$1"

test_dir="/tmp/test-${cc}"
out_dir="${test_dir}/out"
mkdir -p "${out_dir}"
cd "${test_dir}"
cp -r /test/fixtures/. ./

case "${cc}" in
    gcc) cxx=g++ ;;
    clang) cxx=clang++ ;;
    *) cxx="${cc}" ;;
esac
if type -P "${RUST_TARGET}-${cc}"; then
    target_cc="${RUST_TARGET}-${cc}"
    target_cxx="${RUST_TARGET}-${cxx}"
    toolchain_dir="$(dirname "$(dirname "$(type -P "${target_cc}")")")"
else
    target_cc="${cc}"
    target_cxx="${cxx}"
    # TODO
    if [[ -d "/${RUST_TARGET}" ]]; then
        toolchain_dir="/${RUST_TARGET}"
    else
        case "${RUST_TARGET}" in
            *-emscripten*) toolchain_dir="/usr/local/${RUST_TARGET}" ;;
            *) bail "unrecognized target '${RUST_TARGET}'" ;;
        esac
    fi
fi
case "${RUST_TARGET}" in
    aarch64_be-unknown-linux-gnu | arm-unknown-linux-gnueabihf) sysroot_suffix="${RUST_TARGET}/libc" ;;
    riscv32gc-unknown-linux-gnu) sysroot_suffix="sysroot" ;;
    *) sysroot_suffix="${RUST_TARGET}" ;;
esac
dev_tools_dir="${toolchain_dir}/share/rust-cross-toolchain/${RUST_TARGET}"
mkdir -p "${dev_tools_dir}"/lib

rust_target_lower="${RUST_TARGET//-/_}"
rust_target_lower="${rust_target_lower//./_}"
rust_target_upper="$(tr '[:lower:]' '[:upper:]' <<<"${rust_target_lower}")"
touch "${dev_tools_dir}/${cc}.env"
case "${cc}" in
    gcc)
        cat >>"${dev_tools_dir}/${cc}.env" <<EOF
export AR_${rust_target_lower}=${RUST_TARGET}-ar
EOF
        ;;
    clang)
        # https://www.kernel.org/doc/html/latest/kbuild/llvm.html#llvm-utilities
        cat >>"${dev_tools_dir}/${cc}.env" <<EOF
export AR=llvm-ar
export NM=llvm-nm
export STRIP=llvm-strip
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export READELF=llvm-readelf
EOF
        ;;
esac
case "${RUST_TARGET}" in
    *-emscripten*) ;;
    *)
        cat >>"${dev_tools_dir}/${cc}.env" <<EOF
export CC_${rust_target_lower}=${target_cc}
export CXX_${rust_target_lower}=${target_cxx}
export CARGO_TARGET_${rust_target_upper}_LINKER=${target_cc}
EOF
        ;;
esac
case "${RUST_TARGET}" in
    *-wasi* | *-emscripten*)
        # cc-rs will try to link to libstdc++ by default.
        cat >>"${dev_tools_dir}/${cc}.env" <<EOF
export CXXSTDLIB=c++
EOF
        ;;
esac
case "${RUST_TARGET}" in
    asmjs-unknown-emscripten)
        # emcc: error: wasm2js does not support source maps yet (debug in wasm for now)
        cat >>"${dev_tools_dir}/${cc}.env" <<EOF
export RUSTFLAGS="\${RUSTFLAGS:-} -C debuginfo=0"
EOF
        ;;
    aarch64_be-unknown-linux-gnu | arm-unknown-linux-gnueabihf)
        # TODO(aarch64_be-unknown-linux-gnu,arm-unknown-linux-gnueabihf)
        export LD_LIBRARY_PATH="${toolchain_dir}/${RUST_TARGET}/libc/lib:${toolchain_dir}/${RUST_TARGET}/lib:${LD_LIBRARY_PATH:-}"
        ;;
    riscv32gc-unknown-linux-gnu)
        # TODO(riscv32gc-unknown-linux-gnu)
        export LD_LIBRARY_PATH="${toolchain_dir}/${RUST_TARGET}/lib:${toolchain_dir}/sysroot/lib:${toolchain_dir}/sysroot/usr/lib:${LD_LIBRARY_PATH:-}"
        ;;
esac
no_cpp=""
case "${RUST_TARGET}" in
    # TODO(aarch64-unknown-openbsd): clang segfault
    # TODO(hexagon-unknown-linux-musl): use gcc based toolchain or pass -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" in llvm build
    aarch64-unknown-openbsd | hexagon-unknown-linux-musl) no_cpp=1 ;;
esac
no_rust_cpp="${no_cpp}"
case "${RUST_TARGET}" in
    # TODO(wasm32-wasi):
    #    Error: failed to run main module `/tmp/test-clang/rust/target/wasm32-wasi/debug/rust-test.wasm`
    #    Caused by:
    #        0: failed to instantiate "/tmp/test-clang/rust/target/wasm32-wasi/debug/rust-test.wasm"
    #        1: unknown import: `env::_ZnwmSt11align_val_t` has not been defined
    wasm32-wasi) no_rust_cpp=1 ;;
esac
x cat "${dev_tools_dir}/${cc}.env"
# shellcheck disable=SC1090
. "${dev_tools_dir}/${cc}.env"
case "${RUST_TARGET}" in
    wasm*) exe=".wasm" ;;
    asmjs-*) exe=".js" ;;
    *-windows-*) exe=".exe" ;;
    *) exe="" ;;
esac

case "${RUST_TARGET}" in
    *-linux-musl*)
        rustlib="$(rustc --print sysroot)/lib/rustlib/${RUST_TARGET}"
        self_contained="${rustlib}/lib/self-contained"
        if [[ -f /BUILD_STD ]]; then
            case "${RUST_TARGET}" in
                # llvm libunwind does not support s390x, powerpc
                # https://github.com/llvm/llvm-project/blob/54405a49d868444958d1ee51eef8b943aaebebdc/libunwind/src/libunwind.cpp#L48-L77
                powerpc-* | s390x-*) ;;
                # TODO(riscv64gc-unknown-linux-musl)
                riscv64gc-*) ;;
                # TODO(hexagon-unknown-linux-musl)
                hexagon-*) ;;
                *)
                    rm /BUILD_STD
                    rm -rf "${rustlib}"
                    mkdir -p "${self_contained}"

                    rm -rf /tmp/libunwind
                    mkdir -p /tmp/libunwind
                    x build-libunwind --target="${RUST_TARGET}" --out=/tmp/libunwind
                    cp /tmp/libunwind/libunwind*.a "${self_contained}"

                    rm -rf /tmp/build-std
                    mkdir -p /tmp/build-std/src
                    pushd /tmp/build-std >/dev/null
                    touch src/lib.rs
                    cat >Cargo.toml <<EOF
[package]
name = "build-std"
version = "0.0.0"
edition = "2021"
EOF
                    RUSTFLAGS="${RUSTFLAGS:-} -C debuginfo=1 -L ${toolchain_dir}/${RUST_TARGET}/lib -L ${toolchain_dir}/lib/gcc/${RUST_TARGET}/${GCC_VERSION}" \
                        x cargo build -Z build-std --offline --target "${RUST_TARGET}" --all-targets --release
                    rm target/"${RUST_TARGET}"/release/deps/*build_std-*
                    cp target/"${RUST_TARGET}"/release/deps/lib*.rlib "${rustlib}/lib"
                    popd >/dev/null

                    # https://github.com/rust-lang/rust/blob/0b42deaccc2cbe17a68067aa5fdb76104369e1fd/src/bootstrap/compile.rs#L201-L231
                    # https://github.com/rust-lang/rust/blob/0b42deaccc2cbe17a68067aa5fdb76104369e1fd/compiler/rustc_target/src/spec/crt_objects.rs
                    # Only recent nightly has libc.a in self-contained.
                    # https://github.com/rust-lang/rust/pull/90527
                    # Additionally, there is a vulnerability in the version of libc.a
                    # distributed via rustup.
                    # https://github.com/rust-lang/rust/issues/91178
                    # And if I understand correctly, the code generation on the
                    # 32bit arm targets looks wrong about FPU arch and thumb ISA.
                    cp -f "${toolchain_dir}/${RUST_TARGET}/lib"/{libc.a,Scrt1.o,crt1.o,crti.o,crtn.o,rcrt1.o} "${self_contained}"
                    cp -f "${toolchain_dir}/lib/gcc/${RUST_TARGET}/${GCC_VERSION}"/{crtbegin.o,crtbeginS.o,crtend.o,crtendS.o} "${self_contained}"
                    ;;
            esac
        fi
        ;;
esac

if [[ -z "${NO_RUN:-}" ]]; then
    # Build C/C++.
    pushd cpp >/dev/null
    x "${target_cc}" -v
    case "${cc}" in
        gcc | clang) x "${target_cc}" '-###' hello.c ;;
    esac
    x "${target_cc}" -o c.out hello.c
    case "${RUST_TARGET}" in
        arm*-unknown-linux-gnu* | thumbv7neon-unknown-linux-gnu*) ;;
        *) cp "$(pwd)"/c.out "${out_dir}" ;;
    esac
    if [[ -z "${no_cpp}" ]]; then
        x "${target_cxx}" -v
        case "${cc}" in
            gcc | clang) x "${target_cxx}" '-###' hello.cpp ;;
        esac
        x "${target_cxx}" -o cpp.out hello.cpp
        case "${RUST_TARGET}" in
            arm*-unknown-linux-gnu* | thumbv7neon-unknown-linux-gnu*) ;;
            *) cp "$(pwd)"/cpp.out "${out_dir}" ;;
        esac
    fi
    popd >/dev/null

    # Build Rust with C/C++
    pushd rust >/dev/null
    case "${RUST_TARGET}" in
        *-linux-musl*)
            case "${RUST_TARGET}" in
                # llvm libunwind does not support s390x, powerpc
                # https://github.com/llvm/llvm-project/blob/54405a49d868444958d1ee51eef8b943aaebebdc/libunwind/src/libunwind.cpp#L48-L77
                powerpc-* | s390x-*) ;;
                # TODO(riscv64gc-unknown-linux-musl)
                riscv64gc-*) ;;
                # TODO(hexagon-unknown-linux-musl)
                hexagon-*) ;;
                *)
                    RUSTFLAGS="${RUSTFLAGS:-} -C target-feature=+crt-static -C link-self-contained=yes" \
                        run_cargo build --no-default-features
                    cp "$(pwd)/target/${RUST_TARGET}/debug/rust-test${exe}" "${out_dir}/rust-test-no-cpp-static${exe}"
                    x cargo clean
                    ;;
            esac
            ;;
    esac
    case "${RUST_TARGET}" in
        *-linux-musl* | *-redox*)
            # disable static linking to check interpreter
            export RUSTFLAGS="${RUSTFLAGS:-} -C target-feature=-crt-static"
            ;;
    esac
    run_cargo build
    x ls "$(pwd)/target/${RUST_TARGET}"/debug
    x ls "$(pwd)/target/${RUST_TARGET}"/debug/build/rust-test-*/out
    cp "$(pwd)/target/${RUST_TARGET}"/debug/rust*test"${exe}" "${out_dir}"
    cp "$(pwd)/target/${RUST_TARGET}"/debug/build/rust-test-*/out/hello_c.o "${out_dir}"
    if [[ -z "${no_rust_cpp}" ]]; then
        cp "$(pwd)/target/${RUST_TARGET}"/debug/build/rust-test-*/out/hello_cpp.o "${out_dir}"
    fi
    popd >/dev/null

    # Build Rust with C using CMake
    pushd rust-cmake >/dev/null
    run_cargo build || (tail -n +1 "target/${RUST_TARGET}"/debug/build/rust-cmake-test-*/out/build/CMakeFiles/*.log && exit 1)
    x ls "$(pwd)/target/${RUST_TARGET}"/debug
    x ls "$(pwd)/target/${RUST_TARGET}"/debug/build/rust-cmake-test-*/out/build/CMakeFiles/double.dir
    cp "$(pwd)/target/${RUST_TARGET}"/debug/rust*cmake*test"${exe}" "${out_dir}"
    case "${RUST_TARGET}" in
        *-redox* | *-windows-*) cp "$(pwd)/target/${RUST_TARGET}"/debug/build/rust-cmake-test-*/out/build/CMakeFiles/double.dir/double.obj "${out_dir}" ;;
        *) cp "$(pwd)/target/${RUST_TARGET}"/debug/build/rust-cmake-test-*/out/build/CMakeFiles/double.dir/double.o "${out_dir}" ;;
    esac
    popd >/dev/null

    # Build Rust tests
    pushd rust >/dev/null
    run_cargo test --no-run
    popd >/dev/null

    # Check the compiled binaries.
    x file "${out_dir}"/*
    case "${RUST_TARGET}" in
        *-wasi* | *-emscripten* | *-windows-*) ;;
        *)
            x readelf --file-header "${out_dir}"/*
            x readelf --arch-specific "${out_dir}"/*
            ;;
    esac
    file_info_pat=()         # file
    file_info_pat_not=()     # file
    file_header_pat=()       # readelf --file-header
    file_header_pat_not=()   # readelf --file-header
    arch_specific_pat=()     # readelf --arch-specific
    arch_specific_pat_not=() # readelf --arch-specific
    case "${RUST_TARGET}" in
        *-linux-* | *-freebsd* | *-netbsd* | *-openbsd* | *-dragonfly* | *-solaris* | *-illumos* | *-redox*)
            case "${RUST_TARGET}" in
                arm* | hexagon-* | i*86-* | mipsel-* | mipsisa32r6el-* | riscv32gc-* | thumbv7neon-* | x86_64-*x32)
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
                            file_header_pat+=('(hard-float ABI)?')
                            file_header_pat_not+=('soft-float')
                            arch_specific_pat+=('Tag_ABI_VFP_args: VFP registers')
                            ;;
                        *)
                            file_header_pat+=('(soft-float ABI)?')
                            file_header_pat_not+=('hard-float')
                            arch_specific_pat_not+=('VFP registers')
                            ;;
                    esac
                    case "${RUST_TARGET}" in
                        armv6-*-netbsd-eabihf)
                            case "${cc}" in
                                clang) arch_specific_pat+=('Tag_CPU_arch: v6(KZ)?') ;;
                                *) arch_specific_pat+=('Tag_CPU_arch: v6KZ') ;;
                            esac
                            ;;
                        arm-* | armv6-*) arch_specific_pat+=('Tag_CPU_arch: v6') ;;
                        armv4t-*) arch_specific_pat+=('Tag_CPU_arch: v4T') ;;
                        armv5te-*) arch_specific_pat+=('Tag_CPU_arch: v5TE(J)?') ;;
                        armv7-* | thumbv7neon-*) arch_specific_pat+=('Tag_CPU_arch: v7' 'Tag_CPU_arch_profile: Application' 'Tag_THUMB_ISA_use: Thumb-2') ;;
                        *) bail "unrecognized target '${RUST_TARGET}'" ;;
                    esac
                    case "${RUST_TARGET}" in
                        arm-*hf | armv6-*hf)
                            for bin in "${out_dir}"/*; do
                                if [[ "${RUST_TARGET}" == *"-linux-musl"* ]] && [[ "${bin}" == *"-static" ]]; then
                                    assert_arch_specific 'Tag_THUMB_ISA_use: Thumb-2' "${bin}"
                                    assert_arch_specific 'Tag_FP_arch: VFPv3' "${bin}"
                                else
                                    assert_arch_specific 'Tag_THUMB_ISA_use: Thumb-1' "${bin}"
                                    assert_arch_specific 'Tag_FP_arch: VFPv2' "${bin}"
                                fi
                            done
                            ;;
                        arm-* | armv6-*)
                            for bin in "${out_dir}"/*; do
                                if [[ "${RUST_TARGET}" == *"-linux-musl"* ]] && [[ "${bin}" == *"-static" ]]; then
                                    assert_arch_specific 'Tag_THUMB_ISA_use: Thumb-2' "${bin}"
                                else
                                    assert_arch_specific 'Tag_THUMB_ISA_use: Thumb-1' "${bin}"
                                fi
                            done
                            ;;
                        armv4t-*) arch_specific_pat+=('Tag_THUMB_ISA_use: Thumb-1') ;;
                        armv5te-*)
                            for bin in "${out_dir}"/*; do
                                if [[ "${RUST_TARGET}" == *"-linux-uclibc"* ]]; then
                                    assert_arch_specific 'Tag_CPU_arch: v5TE(J)?' "${bin}"
                                else
                                    assert_arch_specific 'Tag_CPU_arch: v5TE' "${bin}"
                                fi
                                if [[ "${RUST_TARGET}" == *"-linux-musl"* ]] && [[ "${bin}" == *"-static" ]]; then
                                    assert_arch_specific 'Tag_THUMB_ISA_use: Thumb-2' "${bin}"
                                else
                                    assert_arch_specific 'Tag_THUMB_ISA_use: Thumb-1' "${bin}"
                                fi
                            done
                            ;;
                        armv7-*hf)
                            fp_arch=VFPv3-D16
                            case "${RUST_TARGET}" in
                                *-netbsd*) fp_arch=VFPv3 ;;
                            esac
                            for bin in "${out_dir}"/*; do
                                if [[ "${RUST_TARGET}" == *"-linux-musl"* ]] && [[ "${bin}" == *"-static" ]]; then
                                    assert_arch_specific 'Tag_FP_arch: VFPv3' "${bin}"
                                else
                                    assert_arch_specific "Tag_FP_arch: ${fp_arch}" "${bin}"
                                fi
                            done
                            ;;
                        armv7-*) ;;
                        thumbv7neon-*) arch_specific_pat+=('Tag_FP_arch: VFPv4' 'Tag_Advanced_SIMD_arch: NEONv1 with Fused-MAC') ;;
                        *) bail "unrecognized target '${RUST_TARGET}'" ;;
                    esac
                    ;;
                hexagon-*)
                    file_info_pat+=('QUALCOMM DSP6')
                    file_header_pat+=('Machine:\s+QUALCOMM DSP6 Processor')
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
                            file_info_pat_not+=('OpenPOWER ELF V2 ABI')
                            file_header_pat_not+=('abiv2')
                            for bin in "${out_dir}"/*; do
                                if [[ -x "${bin}" ]]; then
                                    assert_file_header 'Flags:.*abiv1' "${bin}"
                                fi
                            done
                            ;;
                    esac
                    ;;
                riscv32gc-* | riscv64gc-*)
                    file_info_pat+=('UCB RISC-V')
                    file_header_pat+=('Machine:\s+RISC-V' 'Flags:\s+0x5, RVC, double-float ABI')
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
                *-linux-gnu* | *-linux-musl*) file_header_pat+=('OS/ABI:\s+UNIX - (System V|GNU)') ;;
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
                            # TODO(clang,mips-musl-sf):
                            case "${cc}" in
                                clang) ldso_arch=mips ;;
                                *) ldso_arch=mips-sf ;;
                            esac
                            ;;
                        mips64-*) ldso_arch=mips64 ;;
                        mips64el-*) ldso_arch=mips64el ;;
                        mipsel-*)
                            # TODO(clang,mips-musl-sf):
                            case "${cc}" in
                                clang) ldso_arch=mipsel ;;
                                *) ldso_arch=mipsel-sf ;;
                            esac
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
                            # TODO(clang,uclibc): should be /lib/ld-uClibc.so.0
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
                    for bin in "${out_dir}"/*.out; do
                        assert_file_info "for FreeBSD ${FREEBSD_VERSION}" "${bin}"
                    done
                    file_info_pat+=('FreeBSD')
                    for bin in "${out_dir}"/*; do
                        if [[ -x "${bin}" ]]; then
                            assert_file_info 'interpreter /libexec/ld-elf\.so\.1' "${bin}"
                            assert_file_info 'FreeBSD-style' "${bin}"
                        fi
                    done
                    ;;
                *-netbsd*)
                    for bin in "${out_dir}"/*; do
                        if [[ -x "${bin}" ]]; then
                            assert_file_info "for NetBSD ${NETBSD_VERSION}" "${bin}"
                            # /usr/libexec/ld.elf_so is symbolic link to /libexec/ld.elf_so.
                            case "${cc}" in
                                clang) assert_file_info 'interpreter /libexec/ld\.elf_so' "${bin}" ;;
                                *) assert_file_info 'interpreter /usr/libexec/ld\.elf_so' "${bin}" ;;
                            esac
                            case "${RUST_TARGET}" in
                                armv6-*) assert_file_info "compiled for: earmv6hf" "${bin}" ;;
                                armv7-*) assert_file_info "compiled for: earmv7hf" "${bin}" ;;
                            esac
                        fi
                    done
                    ;;
                *-openbsd*)
                    for bin in "${out_dir}"/*; do
                        if [[ -x "${bin}" ]]; then
                            assert_file_info 'interpreter /usr/libexec/ld\.so' "${bin}"
                            # version info is not included
                            assert_file_info "for OpenBSD" "${bin}"
                        fi
                    done
                    ;;
                *-dragonfly*)
                    for bin in "${out_dir}"/*; do
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
        wasm*)
            file_info_pat+=('WebAssembly \(wasm\) binary module version 0x1 \(MVP\)')
            ;;
        asmjs-*) ;;
        *-windows-gnu*)
            for bin in "${out_dir}"/*; do
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
    for bin in "${out_dir}"/*; do
        if [[ "${bin}" == *"-static${exe}" ]]; then
            case "${RUST_TARGET}" in
                x86_64-unknown-linux-musl) ;;
                *) assert_file_info "statically linked" "${bin}" ;;
            esac
            assert_not_file_info "interpreter" "${bin}"
            if readelf -d "${bin}" | grep 'NEEDED'; then
                bail
            fi
        fi
        for pat in "${file_info_pat[@]}"; do
            if [[ "${pat}" == "interpreter "* ]]; then
                if [[ ! -x "${bin}" ]] || [[ "${bin}" == *"-static${exe}" ]]; then
                    continue
                fi
            fi
            assert_file_info "${pat}" "${bin}"
        done
        for pat in "${file_info_pat_not[@]}"; do
            assert_not_file_info "${pat}" "${bin}"
        done
        for pat in "${file_header_pat[@]}"; do
            assert_file_header "${pat}" "${bin}"
        done
        for pat in "${file_header_pat_not[@]}"; do
            assert_not_file_header "${pat}" "${bin}"
        done
        for pat in "${arch_specific_pat[@]}"; do
            assert_arch_specific "${pat}" "${bin}"
        done
        for pat in "${arch_specific_pat_not[@]}"; do
            assert_not_arch_specific "${pat}" "${bin}"
        done
    done
fi

# Run the compiled binaries.
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
                    arm-* | armv6-*) export QEMU_CPU=arm11mpcore ;;
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
        [[ -f "${toolchain_dir}/bin/qemu-${qemu_arch}" ]] || cp "$(type -P "qemu-${qemu_arch}")" "${toolchain_dir}/bin"
        runner="${RUST_TARGET}-runner"
        [[ -f "${toolchain_dir}/bin/${runner}" ]] || cat >"${toolchain_dir}/bin/${runner}" <<EOF
#!/bin/sh
set -eu
toolchain_dir="\$(cd "\$(dirname "\$0")"/.. && pwd)"
exec qemu-${qemu_arch} -L "\${toolchain_dir}"/${sysroot_suffix} "\$@"
EOF
        chmod +x "${toolchain_dir}/bin/${runner}"
        x cat "${toolchain_dir}/bin/${runner}"
        ;;
    *-wasi*)
        [[ -f "${toolchain_dir}/bin/wasmtime" ]] || cp "$(type -P "wasmtime")" "${toolchain_dir}/bin"
        runner="${RUST_TARGET}-runner"
        [[ -f "${toolchain_dir}/bin/${runner}" ]] || cat >"${toolchain_dir}/bin/${runner}" <<EOF
#!/bin/sh
set -eu
exec wasmtime run --wasm-features all "\$@"
EOF
        chmod +x "${toolchain_dir}/bin/${runner}"
        x cat "${toolchain_dir}/bin/${runner}"
        ;;
    *-emscripten*)
        runner=node
        ;;
    *-windows-gnu*)
        runner=wine
        # Adapted from https://github.com/rust-embedded/cross/blob/16a64e7028d90a3fdf285cfd642cdde9443c0645/docker/windows-entry.sh
        export HOME=/tmp/home
        mkdir -p "${HOME}"
        # Initialize the wine prefix (virtual windows installation)
        export WINEPREFIX=/tmp/wine
        mkdir -p "${WINEPREFIX}"
        if [[ ! -e /WINEBOOT ]]; then
            x wineboot &>/dev/null
            touch /WINEBOOT
        fi
        # Put libstdc++ and some other mingw dlls in WINEPATH
        WINEPATH="$(ls -d "${toolchain_dir}/lib/gcc/${RUST_TARGET}"/*posix);${toolchain_dir}/${RUST_TARGET}/lib"
        export WINEPATH
        ;;
esac
if [[ -n "${runner:-}" ]]; then
    cat >>"${dev_tools_dir}/${cc}.env" <<EOF
export CARGO_TARGET_${rust_target_upper}_RUNNER=${runner}
EOF
    export "CARGO_TARGET_${rust_target_upper}_RUNNER"="${runner}"

    if [[ -z "${NO_RUN:-}" ]]; then
        for bin in "${out_dir}"/*; do
            if [[ ! -x "${bin}" ]]; then
                continue
            fi
            case "${RUST_TARGET}" in
                armv5te-unknown-linux-uclibceabi | armv7-unknown-linux-uclibceabihf)
                    # TODO(clang,uclibc): qemu: uncaught target signal 11 (Segmentation fault) - core dumped
                    if [[ "${cc}" == "clang" ]] && [[ "${bin}" == *"cpp.out" ]]; then
                        continue
                    fi
                    ;;
            esac
            x "${runner}" "${bin}" | tee run.log
            if ! grep <run.log -E '^Hello (C|C\+\+|Rust|C from Rust|C\+\+ from Rust|Cmake from Rust)!' >/dev/null; then
                bail
            fi
        done
        case "${RUST_TARGET}" in
            # TODO(powerpc-unknown-linux-gnuspe): run-pass, but test-fail: process didn't exit successfully: `qemu-ppc /tmp/test-gcc/rust/target/powerpc-unknown-linux-gnuspe/debug/deps/rust_test-14b6784dbe26b668` (signal: 4, SIGILL: illegal instruction)
            powerpc-unknown-linux-gnuspe) ;;
            *)
                # Run Rust tests
                pushd rust >/dev/null
                run_cargo test
                popd >/dev/null
                ;;
        esac
    fi
fi
