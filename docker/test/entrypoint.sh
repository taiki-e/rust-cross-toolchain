#!/bin/bash
set -euxo pipefail
IFS=$'\n\t'

# shellcheck disable=SC2154
trap 's=$?; echo >&2 "$0: Error on line "${LINENO}": ${BASH_COMMAND}"; exit ${s}' ERR

# Generate entrypoint.sh.

bail() {
    set +x
    echo >&2 "error: ${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}: $*"
    exit 1
}

cc="$1"

case "${cc}" in
    gcc) cxx=g++ ;;
    clang) cxx=clang++ ;;
    *) cxx="${cc}" ;;
esac
if type -P "${RUST_TARGET}-${cc}"; then
    target_cc="${RUST_TARGET}-${cc}"
    target_cxx="${RUST_TARGET}-${cxx}"
    target_linker="${RUST_TARGET}-${cc}"
    case "${cc}" in
        clang)
            if type -P "${RUST_TARGET}-gcc"; then
                target_linker="${RUST_TARGET}-gcc"
            fi
            ;;
    esac
    toolchain_dir="$(dirname "$(dirname "$(type -P "${target_cc}")")")"
else
    target_cc="${cc}"
    target_cxx="${cxx}"
    target_linker="${cc}"
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
case "${RUST_TARGET}" in
    aarch64_be-unknown-linux-gnu | arm-unknown-linux-gnueabihf) sysroot_suffix="${RUST_TARGET}/libc" ;;
    riscv32gc-unknown-linux-gnu) sysroot_suffix="sysroot" ;;
    *) sysroot_suffix="${RUST_TARGET}" ;;
esac
dev_tools_dir="${toolchain_dir}/share/rust-cross-toolchain/${RUST_TARGET}"
mkdir -p "${toolchain_dir}/bin" "${dev_tools_dir}"

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
        if type -P "${RUST_TARGET}-ar"; then
            cat >>"${env_path}" <<EOF
export AR_${rust_target_lower}=${RUST_TARGET}-ar
export STRIP=${RUST_TARGET}-strip
export OBJDUMP=${RUST_TARGET}-objdump
EOF
        fi
        for tool in strip objdump; do
            if type -P "${RUST_TARGET}-${tool}"; then
                tool_upper="$(tr '[:lower:]' '[:upper:]' <<<"${tool}")"
                cat >>"${env_path}" <<EOF
export ${tool_upper}=${RUST_TARGET}-${tool}
EOF
            fi
        done
        ;;
    clang)
        # https://www.kernel.org/doc/html/latest/kbuild/llvm.html#llvm-utilities
        cat >>"${env_path}" <<EOF
export AR_${rust_target_lower}=llvm-ar
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
export PATH="\${EMSDK}:\${EMSDK}/upstream/emscripten:\${EMSDK}/node/${NODE_VERSION}_64bit/bin:\${PATH}"
EOF
        ;;
    *)
        cat >>"${env_path}" <<EOF
export CC_${rust_target_lower}=${target_cc}
export CXX_${rust_target_lower}=${target_cxx}
EOF
        cat >>"${entrypoint_path}" <<EOF
export PATH="\${toolchain_dir}/bin:\${PATH}"
EOF
        ;;
esac
case "${RUST_TARGET}" in
    *-emscripten* | *-none*) ;;
    *)
        cat >>"${env_path}" <<EOF
export CARGO_TARGET_${rust_target_upper}_LINKER=${target_linker}
EOF
        ;;
esac
case "${RUST_TARGET}" in
    *-linux-uclibc*)
        # TODO: should we set STAGING_DIR=sysroot?
        cat >>"${entrypoint_path}" <<EOF
"\${toolchain_dir}"/relocate-sdk.sh
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
export RUSTFLAGS="-C debuginfo=0 \${RUSTFLAGS:-}"
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
    mips-unknown-linux-uclibc | mipsel-unknown-linux-uclibc)
        # mips(el)-buildroot-linux-uclibc-gcc/g++'s default is -march=mips32
        # Allow override by user-set `CC_*`.
        cat >>"${env_path}" <<EOF
export CFLAGS_${rust_target_lower}="-march=mips32r2 \${CFLAGS_${rust_target_lower}:-}"
export CXXFLAGS_${rust_target_lower}="-march=mips32r2 \${CXXFLAGS_${rust_target_lower}:-}"
EOF
        ;;
    armv7a-none-eabi)
        # https://github.com/rust-lang/rust/blob/1.65.0/src/ci/docker/host-x86_64/dist-various-1/Dockerfile#L160-L163
        cat >>"${env_path}" <<EOF
export CFLAGS_${rust_target_lower}="-march=armv7-a \${CFLAGS_${rust_target_lower}:-}"
export CXXFLAGS_${rust_target_lower}="-march=armv7-a \${CXXFLAGS_${rust_target_lower}:-}"
EOF
        ;;
    armv7a-none-eabihf)
        # https://github.com/rust-lang/rust/blob/1.65.0/src/ci/docker/host-x86_64/dist-various-1/Dockerfile#L160-L163
        cat >>"${env_path}" <<EOF
export CFLAGS_${rust_target_lower}="-march=armv7-a+vfpv3 -mfloat-abi=hard \${CFLAGS_${rust_target_lower}:-}"
export CXXFLAGS_${rust_target_lower}="-march=armv7-a+vfpv3 -mfloat-abi=hard \${CXXFLAGS_${rust_target_lower}:-}"
EOF
        ;;
    aarch64-unknown-none-softfloat)
        # https://github.com/rust-lang/rust/blob/1.65.0/src/ci/docker/host-x86_64/dist-various-1/Dockerfile#L164-L165
        cat >>"${env_path}" <<EOF
export CFLAGS_${rust_target_lower}="-mstrict-align -march=armv8-a+nofp+nosimd \${CFLAGS_${rust_target_lower}:-}"
export CXXFLAGS_${rust_target_lower}="-mstrict-align -march=armv8-a+nofp+nosimd \${CXXFLAGS_${rust_target_lower}:-}"
EOF
        ;;
    aarch64-unknown-none)
        # https://github.com/rust-lang/rust/blob/1.65.0/src/ci/docker/host-x86_64/dist-various-1/Dockerfile#L166-L167
        cat >>"${env_path}" <<EOF
export CFLAGS_${rust_target_lower}="-mstrict-align -march=armv8-a+fp+simd \${CFLAGS_${rust_target_lower}:-}"
export CXXFLAGS_${rust_target_lower}="-mstrict-align -march=armv8-a+fp+simd \${CXXFLAGS_${rust_target_lower}:-}"
EOF
        ;;
    riscv64gc-unknown-none-elf)
        cat >>"${env_path}" <<EOF
export CFLAGS_${rust_target_lower}="-mabi=lp64d \${CFLAGS_${rust_target_lower}:-}"
export CXXFLAGS_${rust_target_lower}="-mabi=lp64d \${CXXFLAGS_${rust_target_lower}:-}"
EOF
        ;;
    # https://developer.android.com/ndk/guides/abis
    armv7-linux-androideabi)
        case "${cc}" in
            # cc-rs doesn't emit any flags when cc is clang family and target is android.
            # https://github.com/rust-lang/cc-rs/blob/1.0.73/src/lib.rs#L3179-L3186
            clang)
                cat >>"${env_path}" <<EOF
export CFLAGS_${rust_target_lower}="-mfpu=vfpv3-d16 \${CFLAGS_${rust_target_lower}:-}"
export CXXFLAGS_${rust_target_lower}="-mfpu=vfpv3-d16 \${CXXFLAGS_${rust_target_lower}:-}"
EOF
                ;;
        esac
        ;;
    thumbv7neon-linux-androideabi)
        case "${cc}" in
            # cc-rs doesn't emit any flags when cc is clang family and target is android.
            # https://github.com/rust-lang/cc-rs/blob/1.0.73/src/lib.rs#L3179-L3186
            clang)
                cat >>"${env_path}" <<EOF
export CFLAGS_${rust_target_lower}="-mfpu=neon-vfpv4 \${CFLAGS_${rust_target_lower}:-}"
export CXXFLAGS_${rust_target_lower}="-mfpu=neon-vfpv4 \${CXXFLAGS_${rust_target_lower}:-}"
EOF
                ;;
        esac
        ;;
esac

case "${RUST_TARGET}" in
    *-linux-musl*)
        [[ -f "${dev_tools_dir}/build-libunwind" ]] || cp "$(type -P "build-libunwind")" "${dev_tools_dir}"
        ;;
esac

dpkg_arch="$(dpkg --print-architecture)"
case "${dpkg_arch##*-}" in
    amd64) host_arch=x86_64 ;;
    arm64) host_arch=aarch64 ;;
    *) bail "unsupported architecture '${dpkg_arch}'" ;;
esac
case "${RUST_TARGET}" in
    *-unknown-linux-* | *-android*)
        case "${RUST_TARGET}" in
            aarch64* | arm64*)
                qemu_arch="${RUST_TARGET%%-*}"
                case "${RUST_TARGET}" in
                    arm64*be*) qemu_arch=aarch64_be ;;
                    arm64*) qemu_arch=aarch64 ;;
                esac
                qemu_cpu=a64fx
                ;;
            arm* | thumb*)
                case "${RUST_TARGET}" in
                    armeb* | thumbeb*) qemu_arch=armeb ;;
                    *) qemu_arch=arm ;;
                esac
                case "${RUST_TARGET}" in
                    # ARMv6: https://en.wikipedia.org/wiki/ARM11
                    arm-* | armv6-*) qemu_cpu=arm11mpcore ;;
                    # ARMv4: https://en.wikipedia.org/wiki/StrongARM
                    armv4t-*) qemu_cpu=sa1110 ;;
                    # ARMv5TE
                    armv5te-*) qemu_cpu=arm1026 ;;
                    # ARMv7-A+NEONv2
                    armv7-* | thumbv7neon-*) qemu_cpu=cortex-a15 ;;
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
            x86_64-*)
                qemu_arch=x86_64
                # qemu does not seem to support emulating x86_64 CPU features on x86_64 hosts.
                # > qemu-x86_64: warning: TCG doesn't support requested feature
                # The same warning does not seem to appear on aarch64 hosts, so use qemu-user as runner.
                #
                # A way that works well for emulating x86_64 CPU features on x86_64 hosts is to use Intel SDE.
                # https://www.intel.com/content/www/us/en/developer/articles/tool/software-development-emulator.html
                # It is not OSS, but it is licensed under Intel Simplified Software License and redistribution is allowed.
                # https://www.intel.com/content/www/us/en/developer/articles/license/pre-release-license-agreement-for-software-development-emulator.html
                # https://www.intel.com/content/www/us/en/developer/articles/license/onemkl-license-faq.html
                if [[ "${host_arch}" != "x86_64" ]]; then
                    # AVX512
                    qemu_cpu=Icelake-Server
                fi
                ;;
            *) bail "unrecognized target '${RUST_TARGET}'" ;;
        esac
        if [[ -n "${qemu_cpu:-}" ]]; then
            # We basically set the newer and more powerful CPU as default QEMU_CPU
            # so that we can test more of CPU features. In some contexts, we want to
            # test for a specific CPU, so we allow overrides by user-set QEMU_CPU.
            qemu_cpu=" --cpu \${QEMU_CPU:-${qemu_cpu}}"
        fi
        case "${RUST_TARGET}" in
            *-android*) ;;
            *) qemu_ld_prefix=" -L \"\${toolchain_dir}\"/${sysroot_suffix}" ;;
        esac
        # Include qemu-user in the toolchain, regardless of whether it is actually used by runner.
        [[ -f "${toolchain_dir}/bin/qemu-${qemu_arch}" ]] || cp "$(type -P "qemu-${qemu_arch}")" "${toolchain_dir}/bin"
        runner="${RUST_TARGET}-runner"
        cat >"${toolchain_dir}/bin/${runner}" <<EOF
#!/bin/sh
set -eu
toolchain_dir="\$(cd "\$(dirname "\$0")"/.. && pwd)"
exec qemu-${qemu_arch}${qemu_cpu:-}${qemu_ld_prefix:-} "\$@"
EOF
        chmod +x "${toolchain_dir}/bin/${runner}"
        cat "${toolchain_dir}/bin/${runner}"
        ;;
    *-none*)
        case "${RUST_TARGET}" in
            aarch64* | arm64*)
                qemu_arch="${RUST_TARGET%%-*}"
                case "${RUST_TARGET}" in
                    arm64*be*) qemu_arch=aarch64_be ;;
                    arm64*) qemu_arch=aarch64 ;;
                esac
                qemu_cpu=cortex-a72
                qemu_machine=raspi3
                ;;
            arm* | thumb*)
                case "${RUST_TARGET}" in
                    armeb* | thumbeb*) qemu_arch=armeb ;;
                    *) qemu_arch=arm ;;
                esac
                case "${RUST_TARGET}" in
                    # ARMv7-A+NEONv2
                    # https://github.com/rust-lang/rust/blob/1.65.0/compiler/rustc_target/src/spec/armv7a_none_eabi.rs
                    # https://github.com/rust-lang/rust/blob/1.65.0/compiler/rustc_target/src/spec/armv7a_none_eabihf.rs
                    armv7a-none-eabi | armv7a-none-eabihf) qemu_cpu=cortex-a15 ;;
                    # Cortex-R4/Cortex-R5 (ARMv7-R)
                    # https://github.com/rust-lang/rust/blob/1.65.0/compiler/rustc_target/src/spec/armv7r_none_eabi.rs
                    # https://github.com/rust-lang/rust/blob/1.65.0/compiler/rustc_target/src/spec/armebv7r_none_eabi.rs
                    armv7r-none-eabi | armebv7r-none-eabi) qemu_cpu=cortex-r5 ;;
                    # Cortex-R4F/Cortex-R5F (ARMv7-R)
                    # https://github.com/rust-lang/rust/blob/1.65.0/compiler/rustc_target/src/spec/armv7r_none_eabihf.rs
                    # https://github.com/rust-lang/rust/blob/1.65.0/compiler/rustc_target/src/spec/armebv7r_none_eabihf.rs
                    armv7r-none-eabihf | armebv7r-none-eabihf) qemu_cpu=cortex-r5f ;;
                    # TODO: https://github.com/rust-lang/rust/blob/1.65.0/compiler/rustc_target/src/spec/thumbv4t_none_eabi.rs
                    thumbv4t-none-eabi) ;;
                    # Cortex-M0/Cortex-M0+/Cortex-M1 (ARMv6-M): https://github.com/rust-lang/rust/blob/1.65.0/compiler/rustc_target/src/spec/thumbv6m_none_eabi.rs
                    thumbv6m-none-eabi) qemu_cpu=cortex-m0 ;;
                    # Cortex-M4/Cortex-M7 (ARMv7E-M):
                    # https://github.com/rust-lang/rust/blob/1.65.0/compiler/rustc_target/src/spec/thumbv7em_none_eabi.rs
                    # https://github.com/rust-lang/rust/blob/1.65.0/compiler/rustc_target/src/spec/thumbv7em_none_eabihf.rs
                    thumbv7em-none-eabi | thumbv7em-none-eabihf) qemu_cpu=cortex-m7 ;;
                    # Cortex-M3 (ARMv7-M): https://github.com/rust-lang/rust/blob/1.65.0/compiler/rustc_target/src/spec/thumbv7m_none_eabi.rs
                    thumbv7m-none-eabi) qemu_cpu=cortex-m3 ;;
                    # Cortex-M23 (ARMv8-M Baseline): https://github.com/rust-lang/rust/blob/1.65.0/compiler/rustc_target/src/spec/thumbv8m_base_none_eabi.rs
                    # TODO: As of qemu 6.1, qemu doesn't support --cpu=cortex-m23
                    thumbv8m.base-none-eabi) qemu_cpu=cortex-m33 ;;
                    # Cortex-M33 (ARMV8-M Mainline):
                    # https://github.com/rust-lang/rust/blob/1.65.0/compiler/rustc_target/src/spec/thumbv8m_main_none_eabi.rs
                    # https://github.com/rust-lang/rust/blob/1.65.0/compiler/rustc_target/src/spec/thumbv8m_main_none_eabihf.rs
                    thumbv8m.main-none-eabi | thumbv8m.main-none-eabihf) qemu_cpu=cortex-m33 ;;
                    *) bail "unrecognized target '${RUST_TARGET}'" ;;
                esac
                case "${RUST_TARGET}" in
                    # Cortex-m
                    thumb*) qemu_machine=lm3s6965evb ;;
                    # Cortex-a
                    armv7a-*) qemu_machine=vexpress-a15 ;;
                    # TODO: As of qemu 6.1, qemu-system-arm doesn't support Cortex-R machine.
                    arm*v7r-*) ;;
                    *) bail "unrecognized target '${RUST_TARGET}'" ;;
                esac
                ;;
            mipsel-*) qemu_arch=mipsel ;;
            riscv32*) qemu_arch=riscv32 ;;
            riscv64*) qemu_arch=riscv64 ;;
            x86_64-*) qemu_arch=x86_64 ;;
            *) bail "unrecognized target '${RUST_TARGET}'" ;;
        esac
        if [[ -n "${qemu_cpu:-}" ]]; then
            # We basically set the newer and more powerful CPU as default QEMU_CPU
            # so that we can test more of CPU features. In some contexts, we want to
            # test for a specific CPU, so we allow overrides by user-set QEMU_CPU.
            qemu_cpu=" --cpu \${QEMU_CPU:-${qemu_cpu}}"
        fi
        # Include qemu-user in the toolchain, regardless of whether it is actually used by runner.
        [[ -f "${toolchain_dir}/bin/qemu-${qemu_arch}" ]] || cp "$(type -P "qemu-${qemu_arch}")" "${toolchain_dir}/bin"
        runner_qemu_user="${RUST_TARGET}-runner-qemu-user"
        cat >"${toolchain_dir}/bin/${runner_qemu_user}" <<EOF
#!/bin/sh
set -eu
exec qemu-${qemu_arch}${qemu_cpu:-} "\$@"
EOF
        chmod +x "${toolchain_dir}/bin/${runner_qemu_user}"
        cat "${toolchain_dir}/bin/${runner_qemu_user}"
        case "${RUST_TARGET}" in
            armv7a-* | thumb* | aarch64* | arm64*)
                # No default runner is set.
                runner_qemu_system="${RUST_TARGET}-runner-qemu-system"
                # https://github.com/rust-lang/rust/blob/1.65.0/src/test/run-make/thumb-none-qemu/example/.cargo/config
                cat >"${toolchain_dir}/bin/${runner_qemu_system}" <<EOF
#!/bin/sh
set -eu
toolchain_dir="\$(cd "\$(dirname "\$0")"/.. && pwd)"
export QEMU_AUDIO_DRV="${QEMU_AUDIO_DRV:-none}"
exec qemu-system-${qemu_arch}${qemu_cpu:-} -machine ${qemu_machine} -nographic -semihosting-config enable=on,target=native -kernel "\$@"
EOF
                chmod +x "${toolchain_dir}/bin/${runner_qemu_system}"
                cat "${toolchain_dir}/bin/${runner_qemu_system}"
                ;;
            # TODO(none)
            *) ;;
        esac
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
