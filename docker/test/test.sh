#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -eEuo pipefail
IFS=$'\n\t'

# shellcheck disable=SC2154
trap 's=$?; echo >&2 "$0: error on line "${LINENO}": ${BASH_COMMAND}"; exit ${s}' ERR

# Test the toolchain.

x() {
    local cmd="$1"
    shift
    (
        set -x
        "${cmd}" "$@"
    )
}
bail() {
    echo >&2 "error: ${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}: $*"
    exit 1
}
run_cargo() {
    local cargo_flags=()
    if [[ -n "${no_rust_cpp}" ]] && [[ "$*" != *"--no-default-features"* ]]; then
        cargo_flags+=(--no-default-features)
    fi
    if [[ "${build_mode}" == "release" ]] && [[ "$*" != *"--release"* ]]; then
        cargo_flags+=(--release)
    fi
    subcmd="$1"
    shift
    x cargo "${subcmd}" ${build_std[@]+"${build_std[@]}"} --target "${RUST_TARGET}" ${cargo_flags[@]+"${cargo_flags[@]}"} "$@"
}
assert_file_info() {
    local pat="$1"
    shift
    for bin in "$@"; do
        echo -n "info: checking file info pattern '${pat}' in ${bin} ..."
        if ! (file "${bin}" || true) | grep -Eq "(\\s|\\(|,|^)${pat}(\\s|\\)|,|$)"; then
            echo "failed"
            echo "error: expected '${pat}' in ${bin}, actually:"
            echo "======================================="
            x file "${bin}" || true
            echo "======================================="
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
        if ! (file "${bin}" || true) | grep -q -v "${pat}"; then
            echo "failed"
            echo "error: unexpected '${pat}' in ${bin}:"
            echo "======================================="
            x file "${bin}" || true
            echo "======================================="
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
        if ! (readelf --file-header "${bin}" || true) | grep -Eq "(\\s|\\(|,|^)${pat}(\\s|\\)|,|$)"; then
            echo "failed"
            echo "error: expected '${pat}' in ${bin}, actually:"
            echo "======================================="
            x readelf --file-header "${bin}" || true
            echo "======================================="
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
        if ! (readelf --file-header "${bin}" || true) | grep -q -v "${pat}"; then
            echo "failed"
            echo "error: unexpected '${pat}' in ${bin}:"
            echo "======================================="
            x readelf --file-header "${bin}" || true
            echo "======================================="
            exit 1
        fi
        echo "ok"
    done
}
assert_arch_specific() {
    local pat="$1"
    shift
    for bin in "$@"; do
        echo -n "info: checking arch specific pattern '${pat}' in ${bin} ..."
        if ! (readelf --arch-specific "${bin}" || true) | grep -Eq "(\\s|\\(|,|^)${pat}(\\s|\\)|,|$)"; then
            echo "failed"
            echo "error: expected '${pat}' in ${bin}, actually:"
            echo "======================================="
            x readelf --arch-specific "${bin}" || true
            echo "======================================="
            exit 1
        fi
        echo "ok"
    done
}
assert_not_arch_specific() {
    local pat="$1"
    shift
    for bin in "$@"; do
        echo -n "info: checking arch specific pattern (not) '${pat}' in ${bin} ..."
        if ! (readelf --arch-specific "${bin}" || true) | grep -q -v "${pat}"; then
            echo "failed"
            echo "error: unexpected '${pat}' in ${bin}:"
            echo "======================================="
            x readelf --arch-specific "${bin}" || true
            echo "======================================="
            exit 1
        fi
        echo "ok"
    done
}

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
    toolchain_dir=$(dirname "$(dirname "$(type -P "${target_cc}")")")
else
    target_cc="${cc}"
    target_cxx="${cxx}"
    # TODO
    if [[ -e "/${RUST_TARGET}" ]]; then
        toolchain_dir="/${RUST_TARGET}"
    else
        case "${RUST_TARGET}" in
            *-linux-gnu*) toolchain_dir="/usr" ;;
            *-emscripten*) toolchain_dir="/usr/local/${RUST_TARGET}" ;;
            *) bail "unrecognized target '${RUST_TARGET}'" ;;
        esac
    fi
fi
dev_tools_dir="${toolchain_dir}/share/rust-cross-toolchain/${RUST_TARGET}"
/test/entrypoint.sh "${cc}"
# shellcheck disable=SC1090
. "${dev_tools_dir}/${cc}-env"
# TODO(linux-gnu)
# NB: Sync with entrypoint.sh
case "${RUST_TARGET}" in
    arm-unknown-linux-gnueabihf)
        export LD_LIBRARY_PATH="${toolchain_dir}/${RUST_TARGET}/libc/lib:${toolchain_dir}/${RUST_TARGET}/lib:${LD_LIBRARY_PATH:-}"
        ;;
    loongarch64-unknown-linux-gnu)
        export LD_LIBRARY_PATH="${toolchain_dir}/target/usr/lib64:${toolchain_dir}/${RUST_TARGET}/lib64:${LD_LIBRARY_PATH:-}"
        ;;
esac

dpkg_arch=$(dpkg --print-architecture)
case "${dpkg_arch##*-}" in
    amd64) ;;
    *)
        # TODO: don't skip if actual host is arm64
        echo >&2 "info: testing on hosts other than amd64 is currently being skipped: '${dpkg_arch}'"
        exit 0
        ;;
esac
if [[ -n "${NO_RUN:-}" ]]; then
    exit 0
fi

export CARGO_NET_RETRY=10
export RUST_BACKTRACE=1
export RUSTUP_MAX_RETRIES=10
export RUST_TEST_THREADS=1 # TODO: set in entrypoint.sh? https://github.com/taiki-e/setup-cross-toolchain-action/issues/10
export RUSTFLAGS="${RUSTFLAGS:-} -D warnings --print link-args"
# shellcheck disable=SC1091
. "${HOME}/.cargo/env"

case "${RUST_TARGET}" in
    wasm*) exe=".wasm" ;;
    *-windows*) exe=".exe" ;;
    *) exe="" ;;
esac
case "${RUST_TARGET}" in
    *-redox*) rust_bin_separator="_" ;;
    *) rust_bin_separator="-" ;;
esac
no_std=""
case "${RUST_TARGET}" in
    *-linux-none*) ;;
    # https://github.com/rust-lang/rust/blob/1.70.0/library/std/build.rs#L41
    *-none* | *-uefi* | *-psp* | *-psx* | *-cuda* | avr-*) no_std=1 ;;
esac
no_cc_bin=""
case "${RUST_TARGET}" in
    # TODO(clang,linux-uclibc): interpreter should be /lib/ld-uClibc.so.0
    # TODO(clang,linux-uclibc): qemu: uncaught target signal 11 (Segmentation fault) - core dumped
    # TODO(clang,mips-musl-sf): interpreter should be /lib/ld-musl-mips(el)-sf.so.1
    mips-unknown-linux-musl | mipsel-unknown-linux-musl | *-linux-uclibc*)
        case "${cc}" in
            clang) no_cc_bin=1 ;;
        esac
        ;;
    # TODO(loongarch64):
    loongarch64-unknown-linux-gnu) no_cc_bin=1 ;;
esac
no_rust_c=""
case "${RUST_TARGET}" in
    # TODO(hexagon):
    # TODO(loongarch64):
    hexagon-unknown-linux-musl | loongarch64-unknown-linux-gnu) no_rust_c=1 ;;
esac
no_cpp=""
case "${RUST_TARGET}" in
    # TODO(android):
    # TODO(aarch64-unknown-openbsd): clang segfault
    # TODO(sparc64-unknown-openbsd): error: undefined symbol: main
    # TODO(wasm32-wasip1-threads): not output
    arm*-android* | thumb*-android* | i686-*-android* | aarch64-unknown-openbsd | sparc64-unknown-openbsd | wasm32-wasip1-threads) no_cpp=1 ;;
    # TODO(redox): /x86_64-unknown-redox/x86_64-unknown-redox/include/bits/wchar.h:12:28: error: cannot combine with previous 'int' declaration specifier
    *-redox*)
        case "${cc}" in
            clang) no_cpp=1 ;;
        esac
        ;;
esac
no_rust_cpp="${no_cpp}"
case "${RUST_TARGET}" in
    # TODO(wasi):
    #    Error: failed to run main module `/tmp/test-clang/rust/target/wasm32-wasi/debug/rust-test.wasm`
    #    Caused by:
    #        0: failed to instantiate "/tmp/test-clang/rust/target/wasm32-wasi/debug/rust-test.wasm"
    #        1: unknown import: `env::_ZnwmSt11align_val_t` has not been defined
    *-wasi*) no_rust_cpp=1 ;;
esac
# Whether or not to build the test.
no_build_test=""
case "${RUST_TARGET}" in
    # TODO(sparc64-unknown-openbsd):
    #     /sparc64-unknown-openbsd/bin/sparc64-unknown-openbsd7.0-ld: /sparc64-unknown-openbsd/sparc64-unknown-openbsd/usr/lib/libm.a(s_fmin.o): in function `*_libm_fmin':
    #         /usr/src/lib/libm/src/s_fmin.c:35: undefined reference to `__isnan'
    sparc64-unknown-openbsd) no_build_test=1 ;;
esac
# Whether or not to run the compiled binaries.
no_run="1"
case "${RUST_TARGET}" in
    # TODO(riscv32gc-unknown-linux-gnu): libstd's io-related feature on riscv32 linux is broken: https://github.com/rust-lang/rust/issues/88995
    # TODO(x86_64-unknown-linux-gnux32): Invalid ELF image for this architecture
    riscv32gc-unknown-linux-gnu | x86_64-unknown-linux-gnux32) ;;
    # TODO(redox):
    *-linux-* | *-android* | *-wasi* | *-emscripten* | *-windows-gnu*) no_run="" ;;
esac
# Whether or not to run the test.
no_run_test=""
case "${RUST_TARGET}" in
    # TODO(powerpc-unknown-linux-gnuspe): run-pass, but test-run-fail: process didn't exit successfully: `qemu-ppc /tmp/test-gcc/rust/target/powerpc-unknown-linux-gnuspe/debug/deps/rust_test-14b6784dbe26b668` (signal: 4, SIGILL: illegal instruction)
    # TODO(wasm32-wasip1-threads): failed to invoke command default
    powerpc-unknown-linux-gnuspe | wasm32-wasip1-threads) no_run_test=1 ;;
esac

build_mode=debug
build_std=()
if [[ -f /BUILD_STD ]]; then
    if [[ -n "${no_std}" ]]; then
        build_std=(-Z build-std="core,alloc")
    elif rustc --print cfg --target "${RUST_TARGET}" | grep -q 'panic="abort"'; then
        build_std=(-Z build-std="std,panic_abort")
    else
        build_std=(-Z build-std)
    fi
    case "${RUST_TARGET}" in
        hexagon-unknown-linux-musl)
            export RUSTFLAGS="${RUSTFLAGS:-} -C link-args=-lclang_rt.builtins-hexagon"
            build_std+=(-Z build-std-features=llvm-libunwind)
            ;;
        # TODO(mips): LLVM bug: Undefined temporary symbol error when building std.
        mips-* | mipsel-*) build_mode=release ;;
    esac
fi

if [[ -z "${no_std}" ]]; then
    runner=""
    if [[ -z "${no_run}" ]]; then
        runner="${RUST_TARGET}-runner"
    fi
    if [[ -z "${runner}" ]]; then
        echo >&2 "info: test for target '${RUST_TARGET}' is not supported yet"
    else
        case "${dpkg_arch##*-}" in
            amd64)
                case "${RUST_TARGET}" in
                    *-windows-gnu*)
                        export HOME=/tmp/home
                        mkdir -p "${HOME}"/.wine
                        export WINEPREFIX=/tmp/wine
                        mkdir -p "${WINEPREFIX}"
                        case "${RUST_TARGET}" in
                            aarch64* | arm64*) wineboot=/opt/wine-arm64/bin/wineserver ;;
                            *) wineboot=wineboot ;;
                        esac
                        if [[ ! -e /WINEBOOT ]]; then
                            x "${wineboot}" &>/dev/null
                            touch /WINEBOOT
                        fi
                        ;;
                esac
                ;;
            *)
                # TODO: don't skip if actual host is arm64
                echo >&2 "info: testing on hosts other than amd64 is currently being skipped: '${dpkg_arch}'"
                runner=""
                ;;
        esac
    fi

    # Build std for tier3 linux-musl targets.
    case "${RUST_TARGET}" in
        *-linux-musl*)
            target_libdir=$(rustc --print target-libdir --target "${RUST_TARGET}")
            self_contained="${target_libdir}/self-contained"
            if [[ -f /BUILD_STD ]]; then
                case "${RUST_TARGET}" in
                    # TODO(powerpc-unknown-linux-musl)
                    # TODO(riscv64gc-unknown-linux-musl)
                    # TODO(powerpc64le,s390x,thumbv7neon,mips): libunwind build issue since around 2022-12-16: https://github.com/taiki-e/rust-cross-toolchain/commit/7913d98f9c73ffb83f46ab83019bdc3358503d8a
                    powerpc-* | powerpc64le-* | riscv64* | s390x-* | thumbv7neon-* | mips*) ;;
                    *)
                        rm -rf "${target_libdir}"
                        mkdir -p "${self_contained}"

                        case "${RUST_TARGET}" in
                            hexagon-*) cp "${toolchain_dir}/${RUST_TARGET}/usr/lib"/libunwind.a "${self_contained}" ;;
                            *)
                                rm -rf /tmp/libunwind
                                mkdir -p /tmp/libunwind
                                x "${dev_tools_dir}/build-libunwind" --target="${RUST_TARGET}" --out=/tmp/libunwind
                                cp /tmp/libunwind/libunwind*.a "${self_contained}"
                                ;;
                        esac

                        rm -rf /tmp/build-std
                        mkdir -p /tmp/build-std/src
                        pushd /tmp/build-std >/dev/null
                        touch src/lib.rs
                        cat >Cargo.toml <<EOF
[package]
name = "build-std"
edition = "2021"
EOF
                        RUSTFLAGS="${RUSTFLAGS:-} -C debuginfo=1 -L ${toolchain_dir}/${RUST_TARGET}/lib -L ${toolchain_dir}/lib/gcc/${RUST_TARGET}/${GCC_VERSION}" \
                            x cargo build "${build_std[@]}" --target "${RUST_TARGET}" --all-targets --release
                        rm target/"${RUST_TARGET}"/release/deps/*build_std-*
                        cp target/"${RUST_TARGET}"/release/deps/lib*.rlib "${target_libdir}"
                        popd >/dev/null

                        # https://github.com/rust-lang/rust/blob/1.70.0/src/bootstrap/compile.rs#L248-L280
                        # https://github.com/rust-lang/rust/blob/1.70.0/compiler/rustc_target/src/spec/crt_objects.rs
                        # Only recent nightly has libc.a in self-contained.
                        # https://github.com/rust-lang/rust/pull/90527
                        # Additionally, there is a vulnerability in the version of libc.a
                        # distributed via rustup.
                        # https://github.com/rust-lang/rust/issues/91178
                        # And if I understand correctly, the code generation on the
                        # 32bit arm targets looks wrong about FPU arch and thumb ISA.
                        case "${RUST_TARGET}" in
                            hexagon-*)
                                cp -f "${toolchain_dir}/${RUST_TARGET}/usr/lib"/{libc.a,Scrt1.o,crt1.o,crti.o,crtn.o,rcrt1.o} "${self_contained}"
                                cp -f "${toolchain_dir}/${RUST_TARGET}/usr/lib"/clang_rt.crtbegin-hexagon.o "${self_contained}"/crtbegin.o
                                cp -f "${toolchain_dir}/${RUST_TARGET}/usr/lib"/clang_rt.crtend-hexagon.o "${self_contained}"/crtend.o
                                ;;
                            *)
                                cp -f "${toolchain_dir}/${RUST_TARGET}/lib"/{libc.a,Scrt1.o,crt1.o,crti.o,crtn.o,rcrt1.o} "${self_contained}"
                                cp -f "${toolchain_dir}/lib/gcc/${RUST_TARGET}/${GCC_VERSION}"/{crtbegin.o,crtbeginS.o,crtend.o,crtendS.o} "${self_contained}"
                                ;;
                        esac

                        build_std=()
                        rm /BUILD_STD
                        ;;
                esac
            fi
            ;;
    esac

    # Build C/C++.
    pushd cpp >/dev/null
    x "${target_cc}" -v
    case "${cc}" in
        gcc | clang) x "${target_cc}" '-###' hello.c ;;
    esac
    if [[ -z "${no_cc_bin}" ]]; then
        x "${target_cc}" -o c.out hello.c
        bin="$(pwd)"/c.out
        case "${RUST_TARGET}" in
            arm* | thumb* | mips-unknown-linux-uclibc | mipsel-unknown-linux-uclibc) ;;
            *) cp "${bin}" "${out_dir}" ;;
        esac
        if [[ -n "${runner}" ]] && [[ -x "${bin}" ]]; then
            x "${runner}" "${bin}" | grep -E "^Hello C!"
        fi
    fi

    if [[ -z "${no_cpp}" ]]; then
        x "${target_cxx}" -v
        case "${cc}" in
            gcc | clang) x "${target_cxx}" '-###' hello.cpp ;;
        esac
        if [[ -z "${no_cc_bin}" ]]; then
            x "${target_cxx}" -o cpp.out hello.cpp
            bin="$(pwd)"/cpp.out
            case "${RUST_TARGET}" in
                arm* | thumb* | mips-unknown-linux-uclibc | mipsel-unknown-linux-uclibc) ;;
                *) cp "${bin}" "${out_dir}" ;;
            esac
            if [[ -n "${runner}" ]] && [[ -x "${bin}" ]]; then
                x "${runner}" "${bin}" | grep -E "^Hello C\+\+!"
            fi
        fi
    fi
    popd >/dev/null

    # Build Rust with C/C++
    pushd rust >/dev/null
    # Static linking
    case "${RUST_TARGET}" in
        *-linux-musl*)
            case "${RUST_TARGET}" in
                # TODO(hexagon): run-fail (segfault)
                # TODO(powerpc-unknown-linux-musl)
                # TODO(riscv64gc-unknown-linux-musl)
                # TODO(s390x-unknown-linux-musl)
                # TODO(powerpc64le,thumbv7neon,mips): libunwind build issue since around 2022-12-16: https://github.com/taiki-e/rust-cross-toolchain/commit/7913d98f9c73ffb83f46ab83019bdc3358503d8a
                hexagon-* | powerpc-* | powerpc64le-* | riscv64* | s390x-* | thumbv7neon-* | mips*) ;;
                *)
                    RUSTFLAGS="${RUSTFLAGS:-} -C target-feature=+crt-static -C link-self-contained=yes" \
                        run_cargo build --no-default-features
                    bin="${out_dir}/rust-test-no-cpp-static${exe}"
                    cp "$(pwd)/target/${RUST_TARGET}/${build_mode}/rust-test${exe}" "${bin}"
                    if [[ -n "${runner}" ]]; then
                        x "${runner}" "${bin}" | tee run.log
                        if ! grep -Eq '^Hello Rust!' run.log; then
                            bail
                        fi
                        if [[ -z "${no_rust_c}" ]]; then
                            if ! grep -Eq '^Hello C from Rust!' run.log; then
                                bail
                            fi
                        fi
                    fi
                    x cargo clean
                    ;;
            esac
            ;;
    esac
    # Dynamic linking
    case "${RUST_TARGET}" in
        *-linux-musl* | *-redox*)
            # disable static linking to check interpreter
            export RUSTFLAGS="${RUSTFLAGS:-} -C target-feature=-crt-static"
            ;;
    esac
    run_cargo build || (tail -n +1 "target/${RUST_TARGET}/${build_mode}"/build/rust-test-*/out/build/CMakeFiles/*.log && exit 1)
    x ls "$(pwd)/target/${RUST_TARGET}/${build_mode}"
    if [[ -z "${no_rust_c}" ]]; then
        x ls "$(pwd)/target/${RUST_TARGET}/${build_mode}"/build/rust-test-*/out "$(pwd)/target/${RUST_TARGET}/${build_mode}"/build/rust-test-*/out/build/CMakeFiles/hello_cmake.dir
    fi
    cp "$(pwd)/target/${RUST_TARGET}/${build_mode}"/rust*test"${exe}" "${out_dir}"
    if [[ -z "${no_rust_c}" ]]; then
        cp "$(pwd)/target/${RUST_TARGET}/${build_mode}"/build/rust-test-*/out/hello_c.o "${out_dir}"
        if [[ -z "${no_rust_cpp}" ]]; then
            cp "$(pwd)/target/${RUST_TARGET}/${build_mode}"/build/rust-test-*/out/hello_cpp.o "${out_dir}"
        fi
        cp "$(pwd)/target/${RUST_TARGET}/${build_mode}"/build/rust-test-*/out/build/CMakeFiles/hello_cmake.dir/hello_cmake.obj "${out_dir}" \
            || cp "$(pwd)/target/${RUST_TARGET}/${build_mode}"/build/rust-test-*/out/build/CMakeFiles/hello_cmake.dir/hello_cmake.o "${out_dir}"
    fi
    bin="$(pwd)/target/${RUST_TARGET}/${build_mode}/rust${rust_bin_separator}test${exe}"
    if [[ -n "${runner}" ]] && [[ -x "${bin}" ]]; then
        x "${runner}" "${bin}" | tee run.log
        if ! grep -Eq '^Hello Rust!' run.log; then
            bail
        fi
        if [[ -z "${no_rust_c}" ]]; then
            if ! grep -Eq '^Hello C from Rust!' run.log; then
                bail
            fi
            if [[ -z "${no_rust_cpp}" ]]; then
                if ! grep -Eq '^Hello C\+\+ from Rust!' run.log; then
                    bail
                fi
            fi
            if ! grep -Eq '^Hello Cmake from Rust!' run.log; then
                bail
            fi
            if ! grep -Eq '^4 \* 2 = 8' run.log; then
                bail
            fi
        fi
    fi
    popd >/dev/null

    # Build Rust tests
    pushd rust >/dev/null
    if [[ -z "${no_build_test}" ]]; then
        case "${RUST_TARGET}" in
            # TODO(hexagon): relocation R_HEX_B22_PCREL out of range: 2156604 is not in [-2097152, 2097151]
            hexagon-unknown-linux-musl)
                run_cargo test --no-run --release
                if [[ -n "${runner}" ]] && [[ -z "${no_run_test}" ]]; then
                    run_cargo test --release
                fi
                ;;
            *)
                run_cargo test --no-run
                if [[ -n "${runner}" ]] && [[ -z "${no_run_test}" ]]; then
                    run_cargo test
                fi
                ;;
        esac
    fi
    popd >/dev/null
else
    case "${dpkg_arch##*-}" in
        amd64) runner="1" ;;
        *)
            # TODO: don't skip if actual host is arm64
            echo >&2 "info: testing on hosts other than amd64 is currently being skipped: '${dpkg_arch}'"
            runner=""
            ;;
    esac

    linkers=(
        # rust-lld (default)
        rust-lld
        # aarch64-none-elf-ld, arm-none-eabi-ld, etc.
        "${RUST_TARGET}-ld"
        # aarch64-none-elf-gcc, arm-none-eabi-gcc, etc.
        "${RUST_TARGET}-gcc"
    )
    for linker in "${linkers[@]}"; do
        # https://github.com/rust-embedded/cortex-m/blob/e6c7249982841a8a39ada0bc80e6d0e492a560c3/cortex-m-rt/ci/script.sh
        # https://github.com/rust-lang/rust/blob/1.70.0/tests/run-make/thumb-none-qemu/example/.cargo/config
        case "${linker}" in
            rust-lld) target_rustflags="" ;;
            *-gcc) target_rustflags="-C linker=${linker} -C link-arg=-nostartfiles" ;;
            *) target_rustflags="-C linker=${linker}" ;;
        esac
        case "${linker}" in
            # If the linker contains a dot, rustc will misinterpret the linker flavor.
            thumbv8m.*-ld) target_rustflags+=" -C linker-flavor=ld" ;;
            thumbv8m.*-gcc)
                # TODO: collect2: fatal error: cannot find 'ld'
                continue
                target_rustflags+=" -C linker-flavor=gcc"
                ;;
        esac
        case "${RUST_TARGET}" in
            armeb*)
                case "${linker}" in
                    *-ld) target_rustflags+=" -C link-arg=-EB" ;;
                    *-gcc) target_rustflags+=" -C link-arg=-mbig-endian" ;;
                esac
                ;;
        esac
        target_rustflags_backup="${target_rustflags}"
        for _runner in qemu-system qemu-user; do
            target_rustflags="${target_rustflags_backup}"
            cargo_args=(build)
            case "${_runner}" in
                qemu-system)
                    cargo_args+=(--features qemu-system)
                    case "${RUST_TARGET}" in
                        # TODO: As of QEMU 7.2, qemu-system-arm doesn't support Cortex-R machine.
                        armv7r* | armebv7r*) continue ;;
                        thumbv6m* | thumbv7m* | thumbv7em* | thumbv8m* | aarch64* | arm64* | riscv*)
                            _linker=link.x
                            target_rustflags+=" -C link-arg=-T${_linker}"
                            ;;
                    esac
                    ;;
                qemu-user)
                    cargo_args+=(--features qemu-user)
                    case "${RUST_TARGET}" in
                        thumb*) continue ;;
                    esac
                    ;;
            esac
            pushd no-std-qemu >/dev/null
            # To link to pre-compiled C libraries provided by a C
            # toolchain use GCC as the linker.
            case "${linker}" in
                rust-lld | *-ld) test_cpp='' ;;
                *) test_cpp='1' ;;
            esac
            if [[ -z "${test_cpp}" ]]; then
                RUSTFLAGS="${RUSTFLAGS:-} ${target_rustflags}" \
                    run_cargo "${cargo_args[@]}"
            else
                RUSTFLAGS="${RUSTFLAGS:-} ${target_rustflags}" \
                    run_cargo "${cargo_args[@]}" --features cpp
                [[ -e "${out_dir}/no-std-qemu-test-${linker}-c.o" ]] || cp "$(pwd)/target/${RUST_TARGET}/${build_mode}"/build/no-std-qemu-test-*/out/int_c.o "${out_dir}/no-std-qemu-test-${linker}-c.o"
                [[ -e "${out_dir}/no-std-qemu-test-${linker}-cpp.o" ]] || cp "$(pwd)/target/${RUST_TARGET}/${build_mode}"/build/no-std-qemu-test-*/out/int_cpp.o "${out_dir}/no-std-qemu-test-${linker}-cpp.o"
            fi
            bin="$(pwd)/target/${RUST_TARGET}/${build_mode}"/no-std-qemu-test
            cp "${bin}" "${out_dir}/no-std-qemu-test-${linker}-${_runner}"
            if [[ -n "${runner}" ]]; then
                if [[ "${_runner}" == "qemu-user" ]]; then
                    # TODO(none,cortex-m)
                    case "${RUST_TARGET}" in
                        thumbv6m-* | thumbv7m-* | thumbv7em-* | thumbv8m.*) continue ;;
                    esac
                fi
                x "${RUST_TARGET}-runner-${_runner}" "${bin}" | tee run.log
                if ! grep -Eq '^Hello Rust!' run.log; then
                    bail
                fi
                if [[ -n "${test_cpp}" ]]; then
                    if ! grep -Eq '^x = 5' run.log; then
                        bail
                    fi
                    if ! grep -Eq '^y = 6' run.log; then
                        bail
                    fi
                fi
            fi
            popd >/dev/null
        done
    done
fi

# Check the compiled binaries.
x file "${out_dir}"/*
case "${RUST_TARGET}" in
    wasm* | *-windows*) ;;
    *)
        x readelf --file-header "${out_dir}"/* || true
        x readelf --arch-specific "${out_dir}"/* || true
        ;;
esac
file_info_pat=()         # file
file_info_pat_not=()     # file
file_header_pat=()       # readelf --file-header
file_header_pat_not=()   # readelf --file-header
arch_specific_pat=()     # readelf --arch-specific
arch_specific_pat_not=() # readelf --arch-specific
case "${RUST_TARGET}" in
    *-linux-* | *-freebsd* | *-netbsd* | *-openbsd* | *-dragonfly* | *-solaris* | *-illumos* | *-redox* | *-none*)
        case "${RUST_TARGET}" in
            armeb* | mips-* | mipsisa32r6-* | powerpc-* | sparc-*)
                file_info_pat+=('ELF 32-bit MSB')
                file_header_pat+=('Class:\s+ELF32' 'big endian')
                ;;
            arm* | hexagon-* | i?86-* | mipsel-* | mipsisa32r6el-* | riscv32* | thumb* | x86_64*x32)
                file_info_pat+=('ELF 32-bit LSB')
                file_header_pat+=('Class:\s+ELF32' 'little endian')
                ;;
            aarch64-* | loongarch64-* | mips64el-* | mipsisa64r6el-* | powerpc64le-* | riscv64* | x86_64*)
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
            aarch64* | arm64*)
                file_info_pat+=('ARM aarch64')
                file_header_pat+=('Machine:\s+AArch64')
                ;;
            arm* | thumb*)
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
                    arm* | thumbv7neon-*) arch_specific_pat+=('Tag_ARM_ISA_use: Yes') ;;
                    *)
                        arch_specific_pat_not+=('Tag_ARM_ISA_use: Yes')
                        arch_specific_pat+=('(Tag_ARM_ISA_use: No)?')
                        ;;
                esac
                case "${RUST_TARGET}" in
                    armv6-*-netbsd-eabihf)
                        case "${cc}" in
                            clang) arch_specific_pat+=('Tag_CPU_arch: v6(KZ)?') ;;
                            *) arch_specific_pat+=('Tag_CPU_arch: v6KZ') ;;
                        esac
                        ;;
                    armv4t-* | thumbv4t-*) arch_specific_pat+=('Tag_CPU_arch: v4T') ;;
                    armv5te-* | thumbv5te-*) arch_specific_pat+=('Tag_CPU_arch: v5TE(J)?') ;;
                    arm*v7* | thumbv7* | arm-*-android*)
                        case "${RUST_TARGET}" in
                            thumbv7em-*) arch_specific_pat+=('Tag_CPU_arch: v7E-M') ;;
                            *) arch_specific_pat+=('Tag_CPU_arch: v7') ;;
                        esac
                        case "${RUST_TARGET}" in
                            arm*v7r-*) arch_specific_pat+=('Tag_CPU_arch_profile: Realtime') ;;
                            thumbv7m-* | thumbv7em-*) arch_specific_pat+=('Tag_CPU_arch_profile: Microcontroller') ;;
                            *) arch_specific_pat+=('Tag_CPU_arch_profile: Application') ;;
                        esac
                        arch_specific_pat+=('Tag_THUMB_ISA_use: Thumb-2')
                        ;;
                    thumbv8m.base-*) arch_specific_pat+=('Tag_CPU_arch: v8-M.baseline' 'Tag_CPU_arch_profile: Microcontroller' 'Tag_THUMB_ISA_use: Yes') ;;
                    thumbv8m.main-*) arch_specific_pat+=('Tag_CPU_arch: v8-M.mainline' 'Tag_CPU_arch_profile: Microcontroller' 'Tag_THUMB_ISA_use: Yes') ;;
                    armeb-*) arch_specific_pat+=('Tag_CPU_arch: v8' 'Tag_CPU_arch_profile: Application' 'Tag_THUMB_ISA_use: Thumb-2') ;;
                    arm-* | armv6* | thumbv6*)
                        case "${RUST_TARGET}" in
                            thumb*)
                                arch_specific_pat+=('Tag_CPU_arch: v6S-M')
                                arch_specific_pat+=('Tag_CPU_arch_profile: Microcontroller')
                                ;;
                            *) arch_specific_pat+=('Tag_CPU_arch: v6') ;;
                        esac
                        ;;
                    *) bail "unrecognized target '${RUST_TARGET}'" ;;
                esac
                case "${RUST_TARGET}" in
                    armv4t-* | thumbv4t-*) arch_specific_pat+=('Tag_THUMB_ISA_use: Thumb-1') ;;
                    armv5te-* | thumbv5te-*)
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
                    thumbv7neon-*hf) arch_specific_pat+=('Tag_FP_arch: VFPv4' 'Tag_Advanced_SIMD_arch: NEONv1 with Fused-MAC') ;;
                    arm*v7*hf | thumbv7*hf | armv7-*android* | arm-*-android* | thumbv7neon-*-android*)
                        case "${RUST_TARGET}" in
                            # TODO: This should be always VFPv4
                            thumbv7neon-*-android*) fp_arch='(VFPv3|VFPv3-D16|VFPv4)' ;;
                            # TODO: This should be VFPv3-D16
                            # https://developer.android.com/ndk/guides/abis
                            # https://github.com/rust-lang/rust/blob/1.70.0/compiler/rustc_target/src/spec/armv7_linux_androideabi.rs#L21
                            # https://github.com/rust-lang/rust/pull/33414
                            # https://github.com/rust-lang/rust/blob/1.70.0/compiler/rustc_target/src/spec/armv7_unknown_netbsd_eabihf.rs#L13
                            *-android* | *-netbsd*) fp_arch='(VFPv3|VFPv3-D16)' ;;
                            # https://github.com/rust-lang/rust/blob/1.70.0/compiler/rustc_target/src/spec/thumbv7em_none_eabihf.rs#L22-L31
                            thumbv7em-*) fp_arch=VFPv4-D16 ;;
                            *) fp_arch=VFPv3-D16 ;;
                        esac
                        for bin in "${out_dir}"/*; do
                            if [[ "${RUST_TARGET}" == *"-linux-musl"* ]] && [[ "${bin}" == *"-static" ]]; then
                                assert_arch_specific 'Tag_FP_arch: VFPv3' "${bin}"
                            else
                                assert_arch_specific "Tag_FP_arch: ${fp_arch}" "${bin}"
                            fi
                        done
                        ;;
                    arm*v7* | thumbv7*) ;;
                    thumbv8m*hf) arch_specific_pat+=('Tag_FP_arch: FPv5/FP-D16 for ARMv8') ;;
                    thumbv8m*) ;;
                    armeb-*) ;;
                    arm-*hf | armv6*hf)
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
                    arm-* | armv6* | thumbv6*)
                        for bin in "${out_dir}"/*; do
                            if [[ "${RUST_TARGET}" == *"-linux-musl"* ]] && [[ "${bin}" == *"-static" ]]; then
                                assert_arch_specific 'Tag_THUMB_ISA_use: Thumb-2' "${bin}"
                            else
                                assert_arch_specific 'Tag_THUMB_ISA_use: Thumb-1' "${bin}"
                            fi
                        done
                        ;;
                    *) bail "unrecognized target '${RUST_TARGET}'" ;;
                esac
                ;;
            hexagon-*)
                file_info_pat+=('QUALCOMM DSP6')
                file_header_pat+=('Machine:\s+QUALCOMM DSP6 Processor')
                ;;
            i?86-*)
                file_info_pat+=('Intel 80386')
                file_header_pat+=('Machine:\s+Intel 80386')
                ;;
            loongarch64-*)
                file_info_pat+=('LoongArch')
                file_header_pat+=('Machine:\s+LoongArch' 'Flags:\s+0x3, LP64, DOUBLE-FLOAT')
                ;;
            mips-* | mipsel-*)
                file_info_pat+=('MIPS' 'MIPS32 rel2')
                file_header_pat+=('Machine:\s+MIPS R3000' 'Flags:.*mips32r2')
                arch_specific_pat+=('ISA: MIPS32r2')
                case "${RUST_TARGET}" in
                    # TODO(linux-uclibc): should be soft-float
                    *-linux-musl*) arch_specific_pat+=('FP ABI: Soft float') ;;
                    # TODO(netbsd):
                    *-netbsd*) arch_specific_pat+=('FP ABI: Hard float (\(double precision\)|\(32-bit CPU, Any FPU\))') ;;
                    *) arch_specific_pat+=('FP ABI: Hard float \(32-bit CPU, Any FPU\)') ;;
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
                    powerpc64le-* | *-linux-musl* | *-freebsd* | *-openbsd*)
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
            riscv32* | riscv64*)
                file_info_pat+=('UCB RISC-V')
                file_header_pat+=('Machine:\s+RISC-V')
                case "${RUST_TARGET}" in
                    riscv*i-* | riscv*im-*) file_header_pat+=('Flags:\s+0x0') ;;
                    riscv*imac-* | riscv*imc-*) file_header_pat+=('Flags:\s+0x1, RVC, soft-float ABI') ;;
                    riscv*gc-*) file_header_pat+=('Flags:\s+0x5, RVC, double-float ABI') ;;
                    *) bail "unrecognized target '${RUST_TARGET}'" ;;
                esac
                ;;
            s390x-*)
                file_info_pat+=('IBM S/390')
                file_header_pat+=('Machine:\s+IBM S/390')
                ;;
            sparc-*)
                file_info_pat+=('SPARC32PLUS' 'V8\+ Required')
                file_header_pat+=('Machine:\s+Sparc v8\+')
                for bin in "${out_dir}"/*; do
                    if [[ -x "${bin}" ]]; then
                        assert_arch_specific 'Tag_GNU_Sparc_HWCAPS: div32' "${bin}"
                    fi
                done
                ;;
            sparc64-* | sparcv9-*)
                file_info_pat+=('SPARC V9')
                file_header_pat+=('Machine:\s+Sparc v9')
                ;;
            x86_64*)
                file_info_pat+=('x86-64')
                file_header_pat+=('Machine:\s+Advanced Micro Devices X86-64')
                ;;
            *) bail "unrecognized target '${RUST_TARGET}'" ;;
        esac
        case "${RUST_TARGET}" in
            *-freebsd*)
                case "${RUST_TARGET}" in
                    riscv64*)
                        file_info_pat+=('(SYSV|FreeBSD)')
                        file_header_pat+=('OS/ABI:\s+UNIX - (System V|FreeBSD)')
                        ;;
                    *)
                        file_info_pat+=('FreeBSD')
                        file_header_pat+=('OS/ABI:\s+UNIX - FreeBSD')
                        ;;
                esac
                ;;
            *-linux-gnu* | *-linux-musl*)
                file_info_pat+=('(SYSV|GNU/Linux)')
                file_header_pat+=('OS/ABI:\s+UNIX - (System V|GNU)')
                ;;
            *)
                file_info_pat+=('SYSV')
                file_header_pat+=('OS/ABI:\s+UNIX - System V')
                ;;
        esac
        case "${RUST_TARGET}" in
            *-linux-gnu*)
                case "${RUST_TARGET}" in
                    aarch64-*) ldso='/lib/ld-linux-aarch64\.so\.1' ;;
                    aarch64_be-*) ldso='/lib/ld-linux-aarch64_be\.so\.1' ;;
                    arm*hf | thumbv7neon-*) ldso='/lib/ld-linux-armhf\.so\.3' ;;
                    arm*) ldso='/lib/ld-linux\.so\.3' ;;
                    i?86-*) ldso='/lib/ld-linux\.so\.2' ;;
                    loongarch64-*) ldso='/lib64/ld-linux-loongarch-lp64d\.so\.1' ;;
                    mips-* | mipsel-*) ldso='/lib/ld\.so\.1' ;;
                    mips64-* | mips64el-*) ldso='/lib64/ld\.so\.1' ;;
                    mipsisa32r6-* | mipsisa32r6el-*) ldso='/lib/ld-linux-mipsn8\.so\.1' ;;
                    mipsisa64r6-* | mipsisa64r6el-*) ldso='/lib64/ld-linux-mipsn8\.so\.1' ;;
                    powerpc-*) ldso='/lib/ld\.so\.1' ;;
                    powerpc64-*) ldso='/lib64/ld64\.so\.1' ;;
                    powerpc64le-*) ldso='/lib64/ld64\.so\.2' ;;
                    riscv32*) ldso='/lib/ld-linux-riscv32-ilp32d\.so\.1' ;;
                    riscv64*) ldso='/lib/ld-linux-riscv64-lp64d\.so\.1' ;;
                    s390x-*) ldso='/lib/ld64\.so\.1' ;;
                    sparc-*) ldso='/lib/ld-linux\.so\.2' ;;
                    sparc64-*) ldso='/lib64/ld-linux\.so\.2' ;;
                    x86_64*x32) ldso='/libx32/ld-linux-x32\.so\.2' ;;
                    x86_64*) ldso='/lib64/ld-linux-x86-64\.so\.2' ;;
                    *) bail "unrecognized target '${RUST_TARGET}'" ;;
                esac
                for bin in "${out_dir}"/*; do
                    if [[ -x "${bin}" ]]; then
                        assert_file_info "interpreter ${ldso}" "${bin}"
                        assert_file_info 'for GNU/Linux' "${bin}"
                    fi
                done
                ;;
            *-linux-musl*)
                case "${RUST_TARGET}" in
                    aarch64-*) ldso_arch=aarch64 ;;
                    arm*hf | thumbv7neon-*) ldso_arch=armhf ;;
                    arm*) ldso_arch=arm ;;
                    hexagon-*) ldso_arch=hexagon ;;
                    i?86-*) ldso_arch=i386 ;;
                    mips-*) ldso_arch=mips-sf ;;
                    mips64-*) ldso_arch=mips64 ;;
                    mips64el-*) ldso_arch=mips64el ;;
                    mipsel-*) ldso_arch=mipsel-sf ;;
                    powerpc-*) ldso_arch=powerpc ;;
                    powerpc64-*) ldso_arch=powerpc64 ;;
                    powerpc64le-*) ldso_arch=powerpc64le ;;
                    riscv32*) ldso_arch=riscv32 ;;
                    riscv64*) ldso_arch=riscv64 ;;
                    s390x-*) ldso_arch=s390x ;;
                    x86_64*) ldso_arch=x86_64 ;;
                    *) bail "unrecognized target '${RUST_TARGET}'" ;;
                esac
                file_info_pat+=("interpreter /lib/ld-musl-${ldso_arch}\\.so\\.1")
                ;;
            *-linux-uclibc*) file_info_pat+=('interpreter /lib/ld-uClibc\.so\.0') ;;
            *-android*)
                case "${RUST_TARGET}" in
                    aarch64-* | x86_64*) file_info_pat+=('interpreter /system/bin/linker64') ;;
                    *) file_info_pat+=('interpreter /system/bin/linker') ;;
                esac
                ;;
            *-freebsd*)
                # Rust binary doesn't include version info
                for bin in "${out_dir}"/*.out; do
                    assert_file_info "for FreeBSD ${FREEBSD_VERSION}" "${bin}"
                done
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
                        assert_file_info "for NetBSD ${NETBSD_VERSION}\\.[0-9]+" "${bin}"
                        # TODO(clang,netbsd): /usr/libexec/ld.elf_so is symbolic link to /libexec/ld.elf_so.
                        case "${cc}" in
                            clang) assert_file_info 'interpreter (/usr)?/libexec/ld\.elf_so' "${bin}" ;;
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
                        case "${RUST_TARGET}" in
                            sparc64-*)
                                if [[ "${bin}" == *".out" ]]; then
                                    assert_file_info 'statically linked' "${bin}"
                                else
                                    assert_file_info 'interpreter /usr/libexec/ld\.so' "${bin}"
                                fi
                                ;;
                            *) assert_file_info 'interpreter /usr/libexec/ld\.so' "${bin}" ;;
                        esac
                        # version info is not included
                        assert_file_info "for OpenBSD" "${bin}"
                    fi
                done
                ;;
            *-dragonfly*)
                for bin in "${out_dir}"/*; do
                    if [[ -x "${bin}" ]]; then
                        assert_file_info 'interpreter /usr/libexec/ld-elf\.so\.2' "${bin}"
                        assert_file_info "for DragonFly ${DRAGONFLY_VERSION%%.*}\\.[0-9]+\\.[0-9]+" "${bin}"
                    fi
                done
                ;;
            *-solaris* | *-illumos*)
                case "${RUST_TARGET}" in
                    sparcv9-*) file_info_pat+=('interpreter /usr/lib/sparcv9/ld\.so\.1') ;;
                    x86_64*) file_info_pat+=('interpreter /lib/amd64/ld\.so\.1') ;;
                    *) bail "unrecognized target '${RUST_TARGET}'" ;;
                esac
                ;;
            *-redox*) file_info_pat+=('interpreter /lib/ld64\.so\.1') ;;
            *-none*)
                # TODO
                ;;
            *) bail "unrecognized target '${RUST_TARGET}'" ;;
        esac
        ;;
    wasm*)
        for bin in "${out_dir}"/*; do
            if [[ -x "${bin}" ]] || [[ "${RUST_TARGET}" != "wasm32-unknown-emscripten" ]]; then
                assert_file_info 'WebAssembly \(wasm\) binary module version 0x1 \(MVP\)'
            else
                # TODO(wasm32-unknown-emscripten): regressed in 1.39.20 -> 2.0.5 update
                assert_file_info 'ASCII text, with very long lines'
            fi
        done
        ;;
    *-windows-gnu*)
        for bin in "${out_dir}"/*; do
            if [[ -x "${bin}" ]]; then
                case "${RUST_TARGET}" in
                    aarch64-*) assert_file_info 'PE32\+ executable \(console\) Aarch64, for MS Windows' "${bin}" ;;
                    i686-*) assert_file_info 'PE32 executable \(console\) Intel 80386' "${bin}" ;;
                    x86_64*) assert_file_info 'PE32\+ executable \(console\) x86-64' "${bin}" ;;
                    *) bail "unrecognized target '${RUST_TARGET}'" ;;
                esac
                assert_file_info 'for MS Windows' "${bin}"
            else
                case "${RUST_TARGET}" in
                    aarch64-*) assert_file_info 'Aarch64 COFF object file' "${bin}" ;;
                    i686-*) assert_file_info 'Intel 80386 COFF object file' "${bin}" ;;
                    x86_64*) assert_file_info 'Intel amd64 COFF object file' "${bin}" ;;
                    *) bail "unrecognized target '${RUST_TARGET}'" ;;
                esac
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
        if (readelf -d "${bin}" || true) | grep 'NEEDED'; then
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

rm -rf "${test_dir}"
