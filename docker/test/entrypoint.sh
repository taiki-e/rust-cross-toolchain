#!/bin/bash
set -euxo pipefail
IFS=$'\n\t'

# Generate entrypoint.sh.

cc="$1"

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
            *-emscripten*) toolchain_dir="/usr/local/${RUST_TARGET}" ;;
            *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
        esac
    fi
fi
case "${RUST_TARGET}" in
    aarch64_be-unknown-linux-gnu | arm-unknown-linux-gnueabihf) sysroot_suffix="${RUST_TARGET}/libc" ;;
    riscv32gc-unknown-linux-gnu) sysroot_suffix="sysroot" ;;
    *) sysroot_suffix="${RUST_TARGET}" ;;
esac
dev_tools_dir="${toolchain_dir}/share/rust-cross-toolchain/${RUST_TARGET}"

# Except for the linux-gnu target, all toolchains are designed to work
# independent of the installation location.
#
# The env_path defines environment variables that do not depend on the
# toolchain position.
# The entrypoint_path reads env_path and defines environment variables
# that depend on the toolchain position, at runtime.
env_path="${dev_tools_dir}/${cc}-env"
entrypoint_path="${dev_tools_dir}/${cc}-entrypoint.sh"
touch "${env_path}"
cat >"${entrypoint_path}" <<EOF
#!/bin/sh
set -eu
toolchain_dir="\$(cd "\$(dirname "\$0")"/../../../.. && pwd)"
EOF
chmod +x "${entrypoint_path}"

rust_target_lower="${RUST_TARGET//-/_}"
rust_target_lower="${rust_target_lower//./_}"
rust_target_upper="$(tr '[:lower:]' '[:upper:]' <<<"${rust_target_lower}")"
case "${cc}" in
    gcc)
        cat >>"${env_path}" <<EOF
export AR_${rust_target_lower}=${RUST_TARGET}-ar
EOF
        ;;
    clang)
        # https://www.kernel.org/doc/html/latest/kbuild/llvm.html#llvm-utilities
        cat >>"${env_path}" <<EOF
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
    *-emscripten*)
        cat >>"${entrypoint_path}" <<EOF
export EMSDK="\${toolchain_dir}"
export EM_CACHE="\${EMSDK}/upstream/emscripten/cache"
export EMSDK_NODE="\${EMSDK}/node/${NODE_VERSION}_64bit/bin/node"
EOF
        ;;
    *)
        cat >>"${env_path}" <<EOF
export CC_${rust_target_lower}=${target_cc}
export CXX_${rust_target_lower}=${target_cxx}
export CARGO_TARGET_${rust_target_upper}_LINKER=${target_cc}
EOF
        ;;
esac
case "${RUST_TARGET}" in
    *-wasi* | *-emscripten*)
        # cc-rs will try to link to libstdc++ by default.
        cat >>"${env_path}" <<EOF
export CXXSTDLIB=c++
EOF
        ;;
esac
case "${RUST_TARGET}" in
    asmjs-unknown-emscripten)
        # emcc: error: wasm2js does not support source maps yet (debug in wasm for now)
        cat >>"${env_path}" <<EOF
export RUSTFLAGS="\${RUSTFLAGS:-} -C debuginfo=0"
EOF
        ;;
    aarch64_be-unknown-linux-gnu | arm-unknown-linux-gnueabihf)
        # TODO(aarch64_be-unknown-linux-gnu,arm-unknown-linux-gnueabihf)
        cat >>"${entrypoint_path}" <<EOF
export LD_LIBRARY_PATH="\${toolchain_dir}/${RUST_TARGET}/libc/lib:\${toolchain_dir}/${RUST_TARGET}/lib:\${LD_LIBRARY_PATH:-}"
EOF
        ;;
    riscv32gc-unknown-linux-gnu)
        # TODO(riscv32gc-unknown-linux-gnu)
        cat >>"${entrypoint_path}" <<EOF
export LD_LIBRARY_PATH="\${toolchain_dir}/${RUST_TARGET}/lib:\${toolchain_dir}/sysroot/lib:\${toolchain_dir}/sysroot/usr/lib:\${LD_LIBRARY_PATH:-}"
EOF
        ;;
esac

case "${RUST_TARGET}" in
    *-unknown-linux-*)
        case "${RUST_TARGET}" in
            aarch64-* | aarch64_be-*)
                qemu_arch="${RUST_TARGET%%-*}"
                # TODO: use a64fx once qemu 6.2 released.
                qemu_cpu=cortex-a72
                ;;
            arm* | thumbv7neon-*)
                qemu_arch=arm
                case "${RUST_TARGET}" in
                    # ARMv6: https://en.wikipedia.org/wiki/ARM11
                    arm-* | armv6-*) qemu_cpu=arm11mpcore ;;
                    # ARMv4: https://en.wikipedia.org/wiki/StrongARM
                    armv4t-*) qemu_cpu=sa1110 ;;
                    # ARMv5TE
                    armv5te-*) qemu_cpu=arm1026 ;;
                    # ARMv7-A+NEONv2
                    armv7-* | thumbv7neon-*) qemu_cpu=cortex-a15 ;;
                    *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
                esac
                ;;
            i*86-*) qemu_arch=i386 ;;
            hexagon-*) qemu_arch=hexagon ;;
            m68k-*) qemu_arch=m68k ;;
            mips-* | mipsel-*) qemu_arch="${RUST_TARGET%%-*}" ;;
            mips64-* | mips64el-*)
                qemu_arch="${RUST_TARGET%%-*}"
                # As of qemu 6.1, only Loongson-3A4000 supports MSA instructions with mips64r5.
                qemu_cpu=Loongson-3A4000
                ;;
            mipsisa32r6-* | mipsisa32r6el-*)
                qemu_arch="${RUST_TARGET%%-*}"
                qemu_arch="${qemu_arch/isa32r6/}"
                qemu_cpu=mips32r6-generic
                ;;
            mipsisa64r6-* | mipsisa64r6el-*)
                qemu_arch="${RUST_TARGET%%-*}"
                qemu_arch="${qemu_arch/isa64r6/64}"
                qemu_cpu=I6400
                ;;
            powerpc-*spe)
                qemu_arch=ppc
                qemu_cpu=e500v2
                ;;
            powerpc-*)
                qemu_arch=ppc
                qemu_cpu=Vger
                ;;
            powerpc64-*)
                qemu_arch=ppc64
                qemu_cpu=power10
                ;;
            powerpc64le-*)
                qemu_arch=ppc64le
                qemu_cpu=power10
                ;;
            riscv32gc-* | riscv64gc-*) qemu_arch="${RUST_TARGET%%gc-*}" ;;
            s390x-*) qemu_arch=s390x ;;
            sparc-*) qemu_arch=sparc32plus ;;
            sparc64-*) qemu_arch=sparc64 ;;
            x86_64-*) qemu_arch=x86_64 ;;
            *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
        esac
        if [[ -n "${qemu_cpu:-}" ]]; then
            # We basically set the newer and more powerful CPU as default QEMU_CPU
            # so that we can test more of CPU features. In some contexts, we want to
            # test for a specific CPU, so we allow overrides by user-set QEMU_CPU.
            qemu_cpu=" --cpu \${QEMU_CPU:-${qemu_cpu}}"
        fi
        [[ -f "${toolchain_dir}/bin/qemu-${qemu_arch}" ]] || cp "$(type -P "qemu-${qemu_arch}")" "${toolchain_dir}/bin"
        runner="${RUST_TARGET}-runner"
        cat >"${toolchain_dir}/bin/${runner}" <<EOF
#!/bin/sh
set -eu
toolchain_dir="\$(cd "\$(dirname "\$0")"/.. && pwd)"
exec qemu-${qemu_arch} -L "\${toolchain_dir}"/${sysroot_suffix}${qemu_cpu:-} "\$@"
EOF
        chmod +x "${toolchain_dir}/bin/${runner}"
        cat "${toolchain_dir}/bin/${runner}"
        ;;
    *-wasi*)
        [[ -f "${toolchain_dir}/bin/wasmtime" ]] || cp "$(type -P "wasmtime")" "${toolchain_dir}/bin"
        runner="${RUST_TARGET}-runner"
        cat >"${toolchain_dir}/bin/${runner}" <<EOF
#!/bin/sh
set -eu
exec wasmtime run --wasm-features all "\$@"
EOF
        chmod +x "${toolchain_dir}/bin/${runner}"
        cat "${toolchain_dir}/bin/${runner}"
        ;;
    *-emscripten*)
        runner="${RUST_TARGET}-runner"
        cat >"${toolchain_dir}/${runner}" <<EOF
#!/bin/sh
set -eu
toolchain_dir="\$(cd "\$(dirname "\$0")" && pwd)"
exec "\${toolchain_dir}"/node/${NODE_VERSION}_64bit/bin/node "\$@"
EOF
        chmod +x "${toolchain_dir}/${runner}"
        cat "${toolchain_dir}/${runner}"
        ;;
    *-windows-gnu*)
        runner="${RUST_TARGET}-runner"
        gcc_lib="$(basename "$(ls -d "${toolchain_dir}/lib/gcc/${RUST_TARGET}"/*posix)")"
        cat >"${toolchain_dir}/bin/${runner}" <<EOF
#!/bin/sh
set -eu
toolchain_dir="\$(cd "\$(dirname "\$0")"/.. && pwd)"
export WINEPATH="\${toolchain_dir}/lib/gcc/${RUST_TARGET}/${gcc_lib};\${toolchain_dir}/${RUST_TARGET}/lib;\${WINEPATH:-}"
exec wine "\$@"
EOF
        chmod +x "${toolchain_dir}/bin/${runner}"
        cat "${toolchain_dir}/bin/${runner}"
        ;;
esac
if [[ -n "${runner:-}" ]]; then
    cat >>"${env_path}" <<EOF
export CARGO_TARGET_${rust_target_upper}_RUNNER=${runner}
EOF
fi

cat >>"${entrypoint_path}" <<EOF
. "\${toolchain_dir}"/share/rust-cross-toolchain/${RUST_TARGET}/${cc}-env
exec "\$@"
EOF

tail -n +1 "${env_path}" "${entrypoint_path}"
