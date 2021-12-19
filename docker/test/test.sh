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
    x cargo "${subcmd}" --target "${RUST_TARGET}" ${cargo_flags[@]+"${cargo_flags[@]}"} "$@"
}
assert_file_info() {
    local pat="$1"
    shift
    for bin in "$@"; do
        echo -n "info: checking file info pattern '${pat}' in ${bin} ..."
        if ! file "${bin}" | grep -E "(\\s|\\(|,|^)${pat}(\\s|\\)|,|$)" >/dev/null; then
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
        if ! readelf --file-header "${bin}" | grep -E "(\\s|\\(|,|^)${pat}(\\s|\\)|,|$)" >/dev/null; then
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
        if ! readelf --arch-specific "${bin}" | grep -E "(\\s|\\(|,|^)${pat}(\\s|\\)|,|$)" >/dev/null; then
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
# See entrypoint.sh
case "${RUST_TARGET}" in
    aarch64_be-unknown-linux-gnu | arm-unknown-linux-gnueabihf)
        # TODO(aarch64_be-unknown-linux-gnu,arm-unknown-linux-gnueabihf)
        export LD_LIBRARY_PATH="${toolchain_dir}/${RUST_TARGET}/libc/lib:${toolchain_dir}/${RUST_TARGET}/lib:${LD_LIBRARY_PATH:-}"
        ;;
    riscv32gc-unknown-linux-gnu)
        # TODO(riscv32gc-unknown-linux-gnu)
        export LD_LIBRARY_PATH="${toolchain_dir}/${RUST_TARGET}/lib:${toolchain_dir}/sysroot/lib:${toolchain_dir}/sysroot/usr/lib:${LD_LIBRARY_PATH:-}"
        ;;
esac

dpkg_arch="$(dpkg --print-architecture)"
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
export CARGO_NET_OFFLINE=true
export RUST_BACKTRACE=1
export RUSTUP_MAX_RETRIES=10
export RUSTFLAGS="${RUSTFLAGS:-} -D warnings -Z print-link-args"
# shellcheck disable=SC1091
. "${HOME}/.cargo/env"

case "${RUST_TARGET}" in
    wasm*) exe=".wasm" ;;
    asmjs-*) exe=".js" ;;
    *-windows-*) exe=".exe" ;;
    *) exe="" ;;
esac
no_std=""
case "${RUST_TARGET}" in
    *-none* | *-cuda*) no_std=1 ;;
esac
no_cpp=""
case "${RUST_TARGET}" in
    # TODO(aarch64-unknown-openbsd): clang segfault
    # TODO(sparc64-unknown-openbsd): error: undefined symbol: main
    # TODO(hexagon-unknown-linux-musl): use gcc based toolchain or pass -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" in llvm build
    aarch64-unknown-openbsd | sparc64-unknown-openbsd | hexagon-unknown-linux-musl) no_cpp=1 ;;
esac
no_rust_cpp="${no_cpp}"
case "${RUST_TARGET}" in
    # TODO(wasm32-wasi):
    #    Error: failed to run main module `/tmp/test-clang/rust/target/wasm32-wasi/debug/rust-test.wasm`
    #    Caused by:
    #        0: failed to instantiate "/tmp/test-clang/rust/target/wasm32-wasi/debug/rust-test.wasm"
    #        1: unknown import: `env::_ZnwmSt11align_val_t` has not been defined
    wasm32-wasi | *-android*) no_rust_cpp=1 ;;
esac
# Whether or not to build the test.
no_build_test=""
case "${RUST_TARGET}" in
    # TODO(sparc-unknown-linux-gnu):
    #     undefined reference to `__sync_val_compare_and_swap_8'
    # TODO(sparc64-unknown-openbsd):
    #     /sparc64-unknown-openbsd/bin/sparc64-unknown-openbsd7.0-ld: /sparc64-unknown-openbsd/sparc64-unknown-openbsd/usr/lib/libm.a(s_fmin.o): in function `*_libm_fmin':
    #         /usr/src/lib/libm/src/s_fmin.c:35: undefined reference to `__isnan'
    sparc-unknown-linux-gnu | sparc64-unknown-openbsd) no_build_test=1 ;;
esac
# Whether or not to run the test.
no_run_test=""
case "${RUST_TARGET}" in
    # TODO(powerpc-unknown-linux-gnuspe):
    #     run-pass, but test-fail: process didn't exit successfully: `qemu-ppc /tmp/test-gcc/rust/target/powerpc-unknown-linux-gnuspe/debug/deps/rust_test-14b6784dbe26b668` (signal: 4, SIGILL: illegal instruction)
    powerpc-unknown-linux-gnuspe) no_run_test=1 ;;
esac

if [[ -z "${no_std}" ]]; then
    runner=""
    # TODO(freebsd): can we use vm or ci images for testing? https://download.freebsd.org/ftp/releases/VM-IMAGES https://download.freebsd.org/ftp/releases/CI-IMAGES
    case "${RUST_TARGET}" in
        # TODO(riscv32gc-unknown-linux-gnu): libstd's io-related feature on riscv32 linux is broken: https://github.com/rust-lang/rust/issues/88995
        # TODO(x86_64-unknown-linux-gnux32): Invalid ELF image for this architecture
        riscv32gc-unknown-linux-gnu | x86_64-unknown-linux-gnux32) ;;
        # TODO(android):
        *-unknown-linux-* | *-wasi* | *-emscripten* | *-windows-gnu*) runner="${RUST_TARGET}-runner" ;;
    esac
    if [[ -z "${runner}" ]]; then
        echo "info: test for target '${RUST_TARGET}' is not supported yet"
    fi
    case "${RUST_TARGET}" in
        *-windows-gnu*)
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
            ;;
    esac

    # Build std for tier3 linux-musl targets.
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
                        rm -rf "${rustlib}"
                        mkdir -p "${self_contained}"

                        rm -rf /tmp/libunwind
                        mkdir -p /tmp/libunwind
                        x "${dev_tools_dir}/build-libunwind" --target="${RUST_TARGET}" --out=/tmp/libunwind
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
                            x cargo build -Z build-std --target "${RUST_TARGET}" --all-targets --release
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
    x "${target_cc}" -o c.out hello.c
    bin="$(pwd)"/c.out
    case "${RUST_TARGET}" in
        arm*-unknown-linux-gnu* | thumbv7neon-unknown-linux-gnu* | arm*-linux-android* | thumb*-linux-android*) ;;
        *) cp "${bin}" "${out_dir}" ;;
    esac
    if [[ -n "${runner}" ]]; then
        [[ ! -x "${bin}" ]] || x "${runner}" "${bin}" | grep -E "^Hello C!"
    fi

    if [[ -z "${no_cpp}" ]]; then
        x "${target_cxx}" -v
        case "${cc}" in
            gcc | clang) x "${target_cxx}" '-###' hello.cpp ;;
        esac
        x "${target_cxx}" -o cpp.out hello.cpp
        bin="$(pwd)"/cpp.out
        case "${RUST_TARGET}" in
            arm*-unknown-linux-gnu* | thumbv7neon-unknown-linux-gnu* | arm*-linux-android* | thumb*-linux-android*) ;;
            *) cp "${bin}" "${out_dir}" ;;
        esac
        if [[ -n "${runner}" ]]; then
            case "${RUST_TARGET}" in
                armv5te-unknown-linux-uclibceabi | armv7-unknown-linux-uclibceabihf)
                    # TODO(clang,uclibc): qemu: uncaught target signal 11 (Segmentation fault) - core dumped
                    if [[ "${cc}" != "clang" ]]; then
                        [[ ! -x "${bin}" ]] || x "${runner}" "${bin}" | grep -E "^Hello C\+\+!"
                    fi
                    ;;
                *)
                    [[ ! -x "${bin}" ]] || x "${runner}" "${bin}" | grep -E "^Hello C\+\+!"
                    ;;
            esac
        fi
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
                    bin="${out_dir}/rust-test-no-cpp-static${exe}"
                    cp "$(pwd)/target/${RUST_TARGET}/debug/rust-test${exe}" "${bin}"
                    if [[ -n "${runner}" ]]; then
                        x "${runner}" "${bin}" | tee run.log
                        if ! grep <run.log -E '^Hello Rust!' >/dev/null; then
                            bail
                        fi
                        if ! grep <run.log -E '^Hello C from Rust!' >/dev/null; then
                            bail
                        fi
                    fi
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
    if [[ -n "${runner}" ]] && [[ -x "${bin}" ]]; then
        x "${runner}" "$(pwd)/target/${RUST_TARGET}"/debug/rust*test"${exe}" | tee run.log
        if ! grep <run.log -E '^Hello Rust!' >/dev/null; then
            bail
        fi
        if ! grep <run.log -E '^Hello C from Rust!' >/dev/null; then
            bail
        fi
        if [[ -z "${no_rust_cpp}" ]]; then
            if ! grep <run.log -E '^Hello C\+\+ from Rust!' >/dev/null; then
                bail
            fi
        fi
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
    if [[ -n "${runner}" ]] && [[ -x "${bin}" ]]; then
        x "${runner}" "$(pwd)/target/${RUST_TARGET}"/debug/rust*cmake*test"${exe}" | tee run.log
        if ! grep <run.log -E '^Hello Cmake from Rust!' >/dev/null; then
            bail
        fi
        if ! grep <run.log -E '^4 \* 2 = 8' >/dev/null; then
            bail
        fi
    fi
    popd >/dev/null

    # Build Rust tests
    pushd rust >/dev/null
    if [[ -z "${no_build_test}" ]]; then
        run_cargo test --no-run
        if [[ -n "${runner}" ]] && [[ -z "${no_run_test}" ]]; then
            run_cargo test
        fi
    fi
    popd >/dev/null
else
    case "${RUST_TARGET}" in
        aarch64-unknown-none* | arm*-none-eabi* | thumb*-none-eabi*)
            pushd /test/fixtures/arm-none >/dev/null
            CARGO_NET_OFFLINE=false x cargo fetch --target "${RUST_TARGET}"
            popd >/dev/null
            case "${RUST_TARGET}" in
                thumb*)
                    pushd /test/fixtures/cortex-m >/dev/null
                    CARGO_NET_OFFLINE=false x cargo fetch --target "${RUST_TARGET}"
                    popd >/dev/null
                    ;;
            esac
            ;;
        riscv*-unknown-none-elf)
            pushd /test/fixtures/riscv-none >/dev/null
            CARGO_NET_OFFLINE=false x cargo fetch --target "${RUST_TARGET}"
            popd >/dev/null
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
        # https://github.com/rust-embedded/cortex-m-rt/blob/b145dadc8ea934a10a828e27be0d7079b2c76b20/ci/script.sh
        # https://github.com/rust-lang/rust/blob/83b32f27fc6c34b0b411f47be31ab4ae07eafed4/src/test/run-make/thumb-none-qemu/example/.cargo/config
        case "${linker}" in
            rust-lld) flag="" ;;
            *-gcc) flag="-C linker=${linker} -C link-arg=-nostartfiles" ;;
            *) flag="-C linker=${linker}" ;;
        esac
        case "${linker}" in
            # If the linker contains a dot, rustc will misinterpret the linker flavor.
            thumbv8m.*-ld) flag="${flag} -C linker-flavor=ld" ;;
            thumbv8m.*-gcc) flag="${flag} -C linker-flavor=gcc" ;;
        esac
        case "${RUST_TARGET}" in
            aarch64-unknown-none* | arm*-none-eabi* | thumb*-none-eabi*)
                case "${RUST_TARGET}" in
                    armeb*)
                        case "${linker}" in
                            # TODO: lld doesn't support big-endian arm https://groups.google.com/g/clang-built-linux/c/XkHn49b_TnI/m/S-3yh7H1BgAJ
                            rust-lld) continue ;;
                            *-ld) flag="${flag} -C link-arg=-EB" ;;
                            *-gcc) flag="${flag} -C link-arg=-mbig-endian" ;;
                        esac
                        ;;
                esac
                pushd arm-none >/dev/null
                cargo clean
                case "${linker}" in
                    rust-lld | *-ld)
                        RUSTFLAGS="${RUSTFLAGS:-} ${flag}" \
                            run_cargo build
                        ;;
                    *)
                        RUSTFLAGS="${RUSTFLAGS:-} ${flag}" \
                            run_cargo build --features cpp
                        cp "$(pwd)/target/${RUST_TARGET}"/debug/build/arm-none-test-*/out/int_c.o "${out_dir}/arm-none-test-${linker}-c.o"
                        cp "$(pwd)/target/${RUST_TARGET}"/debug/build/arm-none-test-*/out/int_cpp.o "${out_dir}/arm-none-test-${linker}-cpp.o"
                        ;;
                esac
                bin="$(pwd)/target/${RUST_TARGET}"/debug/arm-none-test
                cp "${bin}" "${out_dir}/arm-none-test-${linker}"
                # TODO(none,aarch64,cortex-m,cortex-r)
                case "${RUST_TARGET}" in
                    armv7a-*) x "${RUST_TARGET}-runner-qemu-system" "${bin}" ;;
                esac
                x "${RUST_TARGET}-runner-qemu-user" "${bin}"
                popd >/dev/null
                case "${RUST_TARGET}" in
                    thumb*)
                        pushd cortex-m >/dev/null
                        cargo clean
                        # To link to pre-compiled C libraries provided by a C
                        # toolchain use GCC as the linker.
                        case "${linker}" in
                            rust-lld | *-ld)
                                RUSTFLAGS="${RUSTFLAGS:-} ${flag} -C link-arg=-Tlink.x" \
                                    run_cargo build
                                ;;
                            *)
                                RUSTFLAGS="${RUSTFLAGS:-} ${flag} -C link-arg=-Tlink.x" \
                                    run_cargo build --features cpp
                                cp "$(pwd)/target/${RUST_TARGET}"/debug/build/cortex-m-test-*/out/int_c.o "${out_dir}/cortex-m-test-${linker}-c.o"
                                cp "$(pwd)/target/${RUST_TARGET}"/debug/build/cortex-m-test-*/out/int_cpp.o "${out_dir}/cortex-m-test-${linker}-cpp.o"
                                ;;
                        esac
                        bin="$(pwd)/target/${RUST_TARGET}"/debug/cortex-m-test
                        cp "${bin}" "${out_dir}/cortex-m-test-${linker}"
                        x "${RUST_TARGET}-runner-qemu-system" "${bin}" | tee run.log
                        if ! grep <run.log -E '^Hello Rust!' >/dev/null; then
                            bail
                        fi
                        case "${linker}" in
                            rust-lld | *-ld) ;;
                            *)
                                if ! grep <run.log -E '^x = 5' >/dev/null; then
                                    bail
                                fi
                                if ! grep <run.log -E '^y = 6' >/dev/null; then
                                    bail
                                fi
                                ;;
                        esac
                        popd >/dev/null
                        ;;
                esac
                ;;
            riscv*-unknown-none-elf)
                pushd riscv-none >/dev/null
                cargo clean
                case "${linker}" in
                    rust-lld | *-ld)
                        RUSTFLAGS="${RUSTFLAGS:-} ${flag} -C link-arg=-Tmemory.x -C link-arg=-Tlink.x" \
                            run_cargo build
                        ;;
                    *)
                        RUSTFLAGS="${RUSTFLAGS:-} ${flag} -C link-arg=-Tmemory.x -C link-arg=-Tlink.x" \
                            run_cargo build --features cpp
                        cp "$(pwd)/target/${RUST_TARGET}"/debug/build/riscv-none-test-*/out/int_c.o "${out_dir}/riscv-none-test-${linker}-c.o"
                        cp "$(pwd)/target/${RUST_TARGET}"/debug/build/riscv-none-test-*/out/int_cpp.o "${out_dir}/riscv-none-test-${linker}-cpp.o"
                        ;;
                esac
                bin="$(pwd)/target/${RUST_TARGET}/debug/riscv-none-test"
                cp "${bin}" "${out_dir}/riscv-none-test-${linker}"
                # TODO(none,riscv)
                # x "${RUST_TARGET}-runner-qemu-system" "${bin}"
                # or
                # x "${RUST_TARGET}-runner-qemu-user" "${bin}"
                popd >/dev/null
                ;;
            *) bail "unrecognized target '${RUST_TARGET}'" ;;
        esac
    done
fi

# Check the compiled binaries.
x file "${out_dir}"/*
case "${RUST_TARGET}" in
    wasm* | asmjs-* | *-windows-*) ;;
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
    *-linux-* | *-freebsd* | *-netbsd* | *-openbsd* | *-dragonfly* | *-solaris* | *-illumos* | *-redox* | *-none*)
        case "${RUST_TARGET}" in
            armeb* | mips-* | mipsisa32r6-* | powerpc-* | sparc-*)
                file_info_pat+=('ELF 32-bit MSB')
                file_header_pat+=('Class:\s+ELF32' 'big endian')
                ;;
            arm* | hexagon-* | i*86-* | mipsel-* | mipsisa32r6el-* | riscv32* | thumb* | x86_64-*x32)
                file_info_pat+=('ELF 32-bit LSB')
                file_header_pat+=('Class:\s+ELF32' 'little endian')
                ;;
            aarch64-* | mips64el-* | mipsisa64r6el-* | powerpc64le-* | riscv64* | x86_64-*)
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
                    arm-*-android*) arch_specific_pat+=('Tag_CPU_arch: v5TE') ;;
                    arm-* | armv6* | thumbv6*)
                        case "${RUST_TARGET}" in
                            thumb*)
                                arch_specific_pat+=('Tag_CPU_arch: v6S-M')
                                arch_specific_pat+=('Tag_CPU_arch_profile: Microcontroller')
                                ;;
                            *) arch_specific_pat+=('Tag_CPU_arch: v6') ;;
                        esac
                        ;;
                    armv4t-*) arch_specific_pat+=('Tag_CPU_arch: v4T') ;;
                    armv5te-*) arch_specific_pat+=('Tag_CPU_arch: v5TE(J)?') ;;
                    arm*v7* | thumbv7*)
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
                    *) bail "unrecognized target '${RUST_TARGET}'" ;;
                esac
                case "${RUST_TARGET}" in
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
                    thumbv7neon-*) arch_specific_pat+=('Tag_FP_arch: VFPv4' 'Tag_Advanced_SIMD_arch: NEONv1 with Fused-MAC') ;;
                    arm*v7*hf | thumbv7*hf | armv7-*android*)
                        case "${RUST_TARGET}" in
                            # TODO: This should be VFPv3-D16
                            # https://developer.android.com/ndk/guides/abis
                            # https://github.com/rust-lang/rust/blob/5fa94f3c57e27a339bc73336cd260cd875026bd1/compiler/rustc_target/src/spec/armv7_linux_androideabi.rs#L21
                            # https://github.com/rust-lang/rust/pull/33414
                            # https://github.com/rust-lang/rust/blob/5fa94f3c57e27a339bc73336cd260cd875026bd1/compiler/rustc_target/src/spec/armv7_unknown_netbsd_eabihf.rs#L13
                            *-android* | *-netbsd*) fp_arch='(VFPv3|VFPv3-D16)' ;;
                            # https://github.com/rust-lang/rust/blob/5fa94f3c57e27a339bc73336cd260cd875026bd1/compiler/rustc_target/src/spec/thumbv7em_none_eabihf.rs#L22-L31
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
            riscv32* | riscv64*)
                file_info_pat+=('UCB RISC-V')
                file_header_pat+=('Machine:\s+RISC-V')
                case "${RUST_TARGET}" in
                    riscv*i-*) file_header_pat+=('Flags:\s+0x0') ;;
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
            x86_64-*)
                file_info_pat+=('x86-64')
                file_header_pat+=('Machine:\s+Advanced Micro Devices X86-64')
                ;;
            *) bail "unrecognized target '${RUST_TARGET}'" ;;
        esac
        case "${RUST_TARGET}" in
            *-freebsd*)
                case "${RUST_TARGET}" in
                    riscv64gc-*)
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
                    sparc-*) ldso='/lib/ld-linux\.so\.2' ;;
                    sparc64-*) ldso='/lib64/ld-linux\.so\.2' ;;
                    x86_64-*x32) ldso='/libx32/ld-linux-x32\.so\.2' ;;
                    x86_64-*) ldso='/lib64/ld-linux-x86-64\.so\.2' ;;
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
            *-android*)
                case "${RUST_TARGET}" in
                    aarch64-* | x86_64-*) file_info_pat+=('interpreter /system/bin/linker64') ;;
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
                        assert_file_info "for DragonFly ${DRAGONFLY_VERSION%.*}\\.[0-9]+" "${bin}"
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
            *-none*)
                # TODO
                ;;
            *) bail "unrecognized target '${RUST_TARGET}'" ;;
        esac
        ;;
    wasm*) file_info_pat+=('WebAssembly \(wasm\) binary module version 0x1 \(MVP\)') ;;
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
            else
                case "${RUST_TARGET}" in
                    i686-*) assert_file_info 'Intel 80386 COFF object file' "${bin}" ;;
                    x86_64-*) assert_file_info 'Intel amd64 COFF object file' "${bin}" ;;
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
