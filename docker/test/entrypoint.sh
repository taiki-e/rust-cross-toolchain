#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -CeEuo pipefail
IFS=$'\n\t'
trap -- 's=$?; printf >&2 "%s\n" "${0##*/}:${LINENO}: \`${BASH_COMMAND}\` exit with ${s}"; exit ${s}' ERR

# Generate entrypoint.sh.

bail() {
  set +x
  printf >&2 'error: %s\n' "$*"
  exit 1
}

set -x

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
  toolchain_dir=$(dirname -- "$(dirname -- "$(type -P "${target_cc}")")")
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
  aarch64_be-unknown-linux-gnu | armeb-unknown-linux-gnueabi* | arm-unknown-linux-gnueabihf) sysroot_suffix="${RUST_TARGET}/libc" ;;
  csky-unknown-linux-gnuabiv2) sysroot_suffix="${RUST_TARGET}/libc" ;;
  csky-unknown-linux-gnuabiv2hf) sysroot_suffix="${RUST_TARGET}/libc/ck860v" ;;
  riscv32gc-unknown-linux-gnu) sysroot_suffix="sysroot" ;;
  loongarch64-unknown-linux-gnu) sysroot_suffix="target/usr" ;;
  *) sysroot_suffix="${RUST_TARGET}" ;;
esac
dev_tools_dir="${toolchain_dir}/share/rust-cross-toolchain/${RUST_TARGET}"
mkdir -p -- "${toolchain_dir}/bin" "${dev_tools_dir}"

# Except for the linux-gnu target, all toolchains are designed to work
# independent of the installation location.
#
# The env_path defines environment variables that do not depend on the
# toolchain position.
# The entrypoint_path reads env_path and defines environment variables
# that depend on the toolchain position, at runtime.
env_path="${dev_tools_dir}/${cc}-env"
entrypoint_path="${dev_tools_dir}/${cc}-entrypoint.sh"
touch -- "${env_path}"
cat >"${entrypoint_path}" <<EOF
#!/bin/sh
set -eu
toolchain_dir="\$(cd -- "\$(dirname -- "\$0")"/../../../.. && pwd)"
EOF
chmod +x "${entrypoint_path}"

rust_target_lower="${RUST_TARGET//-/_}"
rust_target_lower="${rust_target_lower//./_}"
rust_target_upper=$(tr '[:lower:]' '[:upper:]' <<<"${rust_target_lower}")
case "${cc}" in
  gcc)
    if type -P "${RUST_TARGET}-ar"; then
      cat >>"${env_path}" <<EOF
export AR_${rust_target_lower}=${RUST_TARGET}-ar
export RANLIB_${rust_target_lower}=${RUST_TARGET}-ranlib
export STRIP=${RUST_TARGET}-strip
export OBJDUMP=${RUST_TARGET}-objdump
EOF
    fi
    for tool in strip objdump; do
      if type -P "${RUST_TARGET}-${tool}"; then
        tool_upper=$(tr '[:lower:]' '[:upper:]' <<<"${tool}")
        cat >>"${env_path}" <<EOF
export ${tool_upper}=${RUST_TARGET}-${tool}
EOF
      fi
    done
    ;;
  clang)
    case "${RUST_TARGET}" in
      hexagon-unknown-linux-musl)
        cat >>"${env_path}" <<EOF
export AR_${rust_target_lower}=${RUST_TARGET}-ar
export RANLIB_${rust_target_lower}=${RUST_TARGET}-ranlib
export NM=llvm-nm
export STRIP=llvm-strip
export OBJCOPY=${RUST_TARGET}-objcopy
export OBJDUMP=${RUST_TARGET}-objdump
export READELF=${RUST_TARGET}-readelf
EOF
        ;;
      *)
        # https://github.com/torvalds/linux/blob/v6.10/Documentation/kbuild/llvm.rst#the-llvm-argument
        cat >>"${env_path}" <<EOF
export AR_${rust_target_lower}=llvm-ar
export RANLIB_${rust_target_lower}=llvm-ranlib
export NM=llvm-nm
export STRIP=llvm-strip
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export READELF=llvm-readelf
EOF
        ;;
    esac
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
# TODO(linux-gnu)
# NB: Sync with test.sh
case "${RUST_TARGET}" in
  arm-unknown-linux-gnueabihf)
    cat >>"${entrypoint_path}" <<EOF
export LD_LIBRARY_PATH="\${toolchain_dir}/${RUST_TARGET}/libc/lib:\${toolchain_dir}/${RUST_TARGET}/lib:\${LD_LIBRARY_PATH:-}"
EOF
    ;;
  csky-unknown-linux-gnuabiv2)
    cat >>"${entrypoint_path}" <<EOF
export LD_LIBRARY_PATH="\${toolchain_dir}/${RUST_TARGET}/lib:\${LD_LIBRARY_PATH:-}"
EOF
    ;;
  csky-unknown-linux-gnuabiv2hf)
    cat >>"${entrypoint_path}" <<EOF
export LD_LIBRARY_PATH="\${toolchain_dir}/${RUST_TARGET}/lib/ck860v:\${LD_LIBRARY_PATH:-}"
EOF
    ;;
  loongarch64-unknown-linux-gnu)
    cat >>"${entrypoint_path}" <<EOF
export LD_LIBRARY_PATH="\${toolchain_dir}/target/usr/lib64:\${toolchain_dir}/${RUST_TARGET}/lib:\${LD_LIBRARY_PATH:-}"
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
  mips-unknown-linux-uclibc | mipsel-unknown-linux-uclibc)
    case "${cc}" in
      gcc)
        # mips(el)-buildroot-linux-uclibc-gcc/g++'s default is -march=mips32
        # Allow override by user-set `CC_*`.
        # TODO(linux-uclibc): Rust targets are soft-float (-msoft-float), but toolchain is hard-float.
        # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/mips_unknown_linux_uclibc.rs#L19
        # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/mipsel_unknown_linux_uclibc.rs#L18
        cat >>"${env_path}" <<EOF
export CFLAGS_${rust_target_lower}="-march=mips32r2 \${CFLAGS_${rust_target_lower}:-}"
export CXXFLAGS_${rust_target_lower}="-march=mips32r2 \${CXXFLAGS_${rust_target_lower}:-}"
EOF
        ;;
    esac
    ;;
  armv5te-none-eabi | thumbv5te-none-eabi)
    cat >>"${env_path}" <<EOF
export CFLAGS_${rust_target_lower}="-march=armv5te \${CFLAGS_${rust_target_lower}:-}"
export CXXFLAGS_${rust_target_lower}="-march=armv5te \${CXXFLAGS_${rust_target_lower}:-}"
EOF
    ;;
  armv7a-none-eabi)
    # https://github.com/rust-lang/rust/blob/1.84.0/src/ci/docker/host-x86_64/dist-various-1/Dockerfile#L132
    cat >>"${env_path}" <<EOF
export CFLAGS_${rust_target_lower}="-march=armv7-a \${CFLAGS_${rust_target_lower}:-}"
export CXXFLAGS_${rust_target_lower}="-march=armv7-a \${CXXFLAGS_${rust_target_lower}:-}"
EOF
    ;;
  armv7a-none-eabihf)
    # https://github.com/rust-lang/rust/blob/1.84.0/src/ci/docker/host-x86_64/dist-various-1/Dockerfile#L133
    cat >>"${env_path}" <<EOF
export CFLAGS_${rust_target_lower}="-march=armv7-a+vfpv3 -mfloat-abi=hard \${CFLAGS_${rust_target_lower}:-}"
export CXXFLAGS_${rust_target_lower}="-march=armv7-a+vfpv3 -mfloat-abi=hard \${CXXFLAGS_${rust_target_lower}:-}"
EOF
    ;;
  aarch64-unknown-none-softfloat)
    # https://github.com/rust-lang/rust/blob/1.84.0/src/ci/docker/host-x86_64/dist-various-1/Dockerfile#L135
    cat >>"${env_path}" <<EOF
export CFLAGS_${rust_target_lower}="-mstrict-align -march=armv8-a+nofp+nosimd \${CFLAGS_${rust_target_lower}:-}"
export CXXFLAGS_${rust_target_lower}="-mstrict-align -march=armv8-a+nofp+nosimd \${CXXFLAGS_${rust_target_lower}:-}"
EOF
    ;;
  aarch64-unknown-none)
    # https://github.com/rust-lang/rust/blob/1.84.0/src/ci/docker/host-x86_64/dist-various-1/Dockerfile#L137
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
  armeb-unknown-linux-gnueabi)
    # builtin armeb-unknown-linux-gnueabi is v8
    # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/armeb_unknown_linux_gnueabi.rs#L18
    case "${cc}" in
      gcc)
        cat >>"${env_path}" <<EOF
export CFLAGS_${rust_target_lower}="-march=armv8-a \${CFLAGS_${rust_target_lower}:-}"
export CXXFLAGS_${rust_target_lower}="-march=armv8-a \${CXXFLAGS_${rust_target_lower}:-}"
EOF
        ;;
    esac
    ;;
  # https://developer.android.com/ndk/guides/abis
  armv7-linux-androideabi)
    case "${cc}" in
      # cc-rs doesn't emit any flags when cc is Clang family and target is android.
      # https://github.com/rust-lang/cc-rs/blob/1.0.73/src/lib.rs#L3179-L3186
      # https://github.com/rust-lang/cc-rs/blob/1.0.73/src/lib.rs#L1691-L1706
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
      # cc-rs doesn't emit any flags when cc is Clang family and target is android.
      # https://github.com/rust-lang/cc-rs/blob/1.0.73/src/lib.rs#L3179-L3186
      # https://github.com/rust-lang/cc-rs/blob/1.0.73/src/lib.rs#L1691-L1706
      clang)
        cat >>"${env_path}" <<EOF
export CFLAGS_${rust_target_lower}="-mfpu=neon-vfpv4 \${CFLAGS_${rust_target_lower}:-}"
export CXXFLAGS_${rust_target_lower}="-mfpu=neon-vfpv4 \${CXXFLAGS_${rust_target_lower}:-}"
EOF
        ;;
    esac
    ;;
  arm*v7*-netbsd*hf)
    case "${cc}" in
      clang)
        cat >>"${env_path}" <<EOF
export CFLAGS_${rust_target_lower}="-mfpu=vfpv3-d16 \${CFLAGS_${rust_target_lower}:-}"
export CXXFLAGS_${rust_target_lower}="-mfpu=vfpv3-d16 \${CXXFLAGS_${rust_target_lower}:-}"
EOF
        ;;
    esac
    ;;
  csky-unknown-linux-gnuabiv2hf)
    cat >>"${env_path}" <<EOF
export CFLAGS_${rust_target_lower}="-march=ck860v -mhard-float \${CFLAGS_${rust_target_lower}:-}"
export CXXFLAGS_${rust_target_lower}="-march=ck860v -mhard-float \${CXXFLAGS_${rust_target_lower}:-}"
EOF
    ;;
esac

case "${RUST_TARGET}" in
  *-linux-musl*)
    [[ -f "${dev_tools_dir}/build-libunwind" ]] || cp -- "$(type -P "build-libunwind")" "${dev_tools_dir}"
    ;;
esac

dpkg_arch=$(dpkg --print-architecture)
case "${dpkg_arch##*-}" in
  amd64) host_arch=x86_64 ;;
  arm64) host_arch=aarch64 ;;
  *) bail "unsupported host architecture '${dpkg_arch}'" ;;
esac
case "${RUST_TARGET}" in
  *-linux-* | *-android*)
    case "${RUST_TARGET}" in
      aarch64* | arm64*)
        case "${RUST_TARGET}" in
          aarch64_be-*) qemu_arch=aarch64_be ;;
          *) qemu_arch=aarch64 ;;
        esac
        qemu_cpu=neoverse-v1
        ;;
      arm* | thumb*)
        case "${RUST_TARGET}" in
          armeb* | thumbeb*) qemu_arch=armeb ;;
          *) qemu_arch=arm ;;
        esac
        case "${RUST_TARGET}" in
          # Armv4: https://en.wikipedia.org/wiki/StrongARM
          armv4t-*) qemu_cpu=sa1110 ;;
          # Armv5TE
          armv5te-*) qemu_cpu=arm1026 ;;
          # Armv7-A+NEONv2
          armv7-* | thumbv7* | arm-*-android*) qemu_cpu=cortex-a15 ;;
          # builtin armeb-unknown-linux-gnueabi is Armv8
          # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/armeb_unknown_linux_gnueabi.rs#L18
          armeb-*) ;;
          # Armv6: https://en.wikipedia.org/wiki/ARM11
          arm-* | armv6-*) qemu_cpu=arm11mpcore ;;
          *) bail "unrecognized target '${RUST_TARGET}'" ;;
        esac
        ;;
      csky-*v2*)
        qemu_arch=cskyv2
        case "${RUST_TARGET}" in
          *hf) qemu_cpu=ck860v ;;
        esac
        ;;
      i?86-*) qemu_arch=i386 ;;
      hexagon-*) qemu_arch=hexagon ;;
      loongarch64-*) qemu_arch=loongarch64 ;;
      m68k-*) qemu_arch=m68k ;;
      mips-* | mipsel-*) qemu_arch="${RUST_TARGET%%-*}" ;;
      mips64-* | mips64el-*)
        qemu_arch="${RUST_TARGET%%-*}"
        # As of QEMU 6.1, only Loongson-3A4000 supports MSA instructions with mips64r5.
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
      riscv32*) qemu_arch=riscv32 ;;
      riscv64*) qemu_arch=riscv64 ;;
      s390x-*) qemu_arch=s390x ;;
      sparc-*) qemu_arch=sparc32plus ;;
      sparc64-* | sparcv9-*) qemu_arch=sparc64 ;;
      x86_64*)
        qemu_arch=x86_64
        # qemu does not seem to support emulating x86_64 CPU features on x86_64 hosts.
        # > qemu-x86_64: warning: TCG doesn't support requested feature
        # The same warning does not seem to appear on AArch64 hosts, so use qemu-user as runner.
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
      qemu_cpu=" -cpu \${QEMU_CPU:-${qemu_cpu}}"
    fi
    case "${RUST_TARGET}" in
      *-android*) ;;
      *) qemu_ld_prefix=" -L \"\${toolchain_dir}\"/${sysroot_suffix}" ;;
    esac
    # Include qemu-user in the toolchain, regardless of whether it is actually used by runner.
    [[ -f "${toolchain_dir}/bin/qemu-${qemu_arch}" ]] || cp -- "$(type -P "qemu-${qemu_arch}")" "${toolchain_dir}/bin"
    "qemu-${qemu_arch}" --version
    runner="${RUST_TARGET}-runner"
    cat >|"${toolchain_dir}/bin/${runner}" <<EOF
#!/bin/sh
set -eu
toolchain_dir="\$(cd -- "\$(dirname -- "\$0")"/.. && pwd)"
exec qemu-${qemu_arch}${qemu_cpu:-}${qemu_ld_prefix:-} "\$@"
EOF
    chmod +x "${toolchain_dir}/bin/${runner}"
    cat -- "${toolchain_dir}/bin/${runner}"
    ;;
  *-none*)
    # https://github.com/taiki-e/semihosting/blob/HEAD/tools/qemu-system-runner.sh
    case "${RUST_TARGET}" in
      aarch64* | arm64*)
        qemu_system_arch=aarch64
        case "${RUST_TARGET}" in
          aarch64_be-*) qemu_user_arch=aarch64_be ;;
          *) qemu_user_arch=aarch64 ;;
        esac
        qemu_machine=raspi3b
        ;;
      arm* | thumb*)
        qemu_system_arch=arm
        qemu_user_arch=arm
        case "${RUST_TARGET}" in
          armeb* | thumbeb*) qemu_user_arch=armeb ;;
        esac
        case "${RUST_TARGET}" in
          # Armv7-A
          # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/armv7a_none_eabi.rs
          # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/armv7a_none_eabihf.rs
          armv7a-none-eabi | armv7a-none-eabihf) qemu_cpu=cortex-a9 ;;
          # Cortex-R4/Cortex-R5 (Armv7-R)
          # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/armv7r_none_eabi.rs
          # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/armebv7r_none_eabi.rs
          armv7r-none-eabi | armebv7r-none-eabi) qemu_cpu=cortex-r5 ;;
          # Cortex-R4F/Cortex-R5F (Armv7-R)
          # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/armv7r_none_eabihf.rs
          # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/armebv7r_none_eabihf.rs
          armv7r-none-eabihf | armebv7r-none-eabihf) qemu_cpu=cortex-r5f ;;
          # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/armv4t_none_eabi.rs
          # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/thumbv4t_none_eabi.rs
          armv4t-none-eabi | thumbv4t-none-eabi) ;; # TODO
          # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/armv5te_none_eabi.rs
          # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/thumbv5te_none_eabi.rs
          armv5te-none-eabi | thumbv5te-none-eabi) qemu_cpu=arm926 ;;
          # Cortex-M0/Cortex-M0+/Cortex-M1 (Armv6-M): https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/thumbv6m_none_eabi.rs
          thumbv6m-none-eabi) qemu_cpu=cortex-m0 ;;
          # Cortex-M4/Cortex-M7 (Armv7E-M):
          # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/thumbv7em_none_eabi.rs
          # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/thumbv7em_none_eabihf.rs
          thumbv7em-none-eabi | thumbv7em-none-eabihf) qemu_cpu=cortex-m7 ;;
          # Cortex-M3 (Armv7-M): https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/thumbv7m_none_eabi.rs
          thumbv7m-none-eabi) qemu_cpu=cortex-m3 ;;
          # Cortex-M23 (Armv8-M Baseline): https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/thumbv8m_base_none_eabi.rs
          # TODO: As of QEMU 9.2, QEMU doesn't support -cpu cortex-m23
          thumbv8m.base-none-eabi) qemu_cpu=cortex-m33 ;;
          # Cortex-M33 (ArmV8-M Mainline):
          # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/thumbv8m_main_none_eabi.rs
          # https://github.com/rust-lang/rust/blob/1.84.0/compiler/rustc_target/src/spec/targets/thumbv8m_main_none_eabihf.rs
          thumbv8m.main-none-eabi | thumbv8m.main-none-eabihf) qemu_cpu=cortex-m33 ;;
          *) bail "unrecognized target '${RUST_TARGET}'" ;;
        esac
        case "${RUST_TARGET}" in
          armv5te* | thumbv5te*) qemu_machine=versatilepb ;;
          # Cortex-m
          thumb*) qemu_machine=lm3s6965evb ;;
          # Cortex-a
          armv7a-*) qemu_machine=xilinx-zynq-a9 ;;
          # TODO: As of QEMU 8.2, qemu-system-arm doesn't support Cortex-R machine.
          # TODO: mps3-an536 added in QEMU 9.0 is Cortex-R52 board (Armv8-R AArch32)
          arm*v7r-*) ;;
          *) bail "unrecognized target '${RUST_TARGET}'" ;;
        esac
        ;;
      mips-*)
        qemu_system_arch=mips
        qemu_user_arch=mips
        qemu_machine=malta
        ;;
      mipsel-*)
        qemu_system_arch=mipsel
        qemu_user_arch=mipsel
        qemu_machine=malta
        ;;
      mips64-*)
        qemu_system_arch=mips64
        qemu_user_arch=mips64
        qemu_cpu=MIPS64R2-generic
        qemu_machine=malta
        ;;
      mips64el-*)
        qemu_system_arch=mips64el
        qemu_user_arch=mips64el
        qemu_cpu=MIPS64R2-generic
        qemu_machine=malta
        ;;
      riscv32*)
        qemu_system_arch=riscv32
        qemu_user_arch=riscv32
        qemu_machine=virt
        ;;
      riscv64*)
        qemu_system_arch=riscv64
        qemu_user_arch=riscv64
        qemu_machine=virt
        ;;
      x86_64*)
        qemu_system_arch=x86_64
        qemu_user_arch=x86_64
        ;;
      *) bail "unrecognized target '${RUST_TARGET}'" ;;
    esac
    if [[ -n "${qemu_cpu:-}" ]]; then
      # We basically set the newer and more powerful CPU as default QEMU_CPU
      # so that we can test more of CPU features. In some contexts, we want to
      # test for a specific CPU, so we allow overrides by user-set QEMU_CPU.
      qemu_cpu=" -cpu \${QEMU_CPU:-${qemu_cpu}}"
    fi
    # Include qemu-user in the toolchain, regardless of whether it is actually used by runner.
    [[ -f "${toolchain_dir}/bin/qemu-${qemu_user_arch}" ]] || cp -- "$(type -P "qemu-${qemu_user_arch}")" "${toolchain_dir}/bin"
    "qemu-${qemu_user_arch}" --version
    runner_qemu_user="${RUST_TARGET}-runner-qemu-user"
    cat >"${toolchain_dir}/bin/${runner_qemu_user}" <<EOF
#!/bin/sh
set -eu
exec qemu-${qemu_user_arch}${qemu_cpu:-} "\$@"
EOF
    chmod +x "${toolchain_dir}/bin/${runner_qemu_user}"
    cat -- "${toolchain_dir}/bin/${runner_qemu_user}"
    case "${RUST_TARGET}" in
      armv5te-* | armv7a-* | thumb* | aarch64* | arm64* | riscv*)
        # No default runner is set.
        runner_qemu_system="${RUST_TARGET}-runner-qemu-system"
        cat >"${toolchain_dir}/bin/${runner_qemu_system}" <<EOF
#!/bin/sh
set -eu
toolchain_dir="\$(cd -- "\$(dirname -- "\$0")"/.. && pwd)"
export QEMU_AUDIO_DRV="${QEMU_AUDIO_DRV:-none}"
exec qemu-system-${qemu_system_arch} -M ${qemu_machine}${qemu_cpu:-} -display none -semihosting -kernel "\$@"
EOF
        chmod +x "${toolchain_dir}/bin/${runner_qemu_system}"
        cat -- "${toolchain_dir}/bin/${runner_qemu_system}"
        ;;
      # TODO(none)
      *) ;;
    esac
    ;;
  *-wasi*)
    [[ -f "${toolchain_dir}/bin/wasmtime" ]] || cp -- "$(type -P "wasmtime")" "${toolchain_dir}/bin"
    runner="${RUST_TARGET}-runner"
    wasi_options=''
    case "${RUST_TARGET}" in
      *-threads) wasi_options+=' -S threads' ;;
    esac
    # stack-switching is not supported on non-x64: https://github.com/bytecodealliance/wasmtime/issues/10248
    cat >|"${toolchain_dir}/bin/${runner}" <<EOF
#!/bin/sh
set -eu
exec wasmtime run -W all-proposals -W stack-switching=n -S inherit-env${wasi_options} "\$@"
EOF
    chmod +x "${toolchain_dir}/bin/${runner}"
    cat -- "${toolchain_dir}/bin/${runner}"
    ;;
  *-emscripten*)
    runner="${RUST_TARGET}-runner"
    cat >"${toolchain_dir}/${runner}" <<EOF
#!/bin/sh
set -eu
toolchain_dir="\$(cd -- "\$(dirname -- "\$0")" && pwd)"
exec "\${toolchain_dir}"/node/${NODE_VERSION}_64bit/bin/node "\$@"
EOF
    chmod +x "${toolchain_dir}/${runner}"
    cat -- "${toolchain_dir}/${runner}"
    ;;
  *-windows-gnu*)
    runner="${RUST_TARGET}-runner"
    case "${RUST_TARGET}" in
      *-gnullvm*) winepath="\${toolchain_dir}/${RUST_TARGET}/bin" ;;
      *)
        gcc_lib=$(basename -- "$(ls -d -- "${toolchain_dir}/lib/gcc/${RUST_TARGET}"/*posix)")
        winepath="\${toolchain_dir}/lib/gcc/${RUST_TARGET}/${gcc_lib};\${toolchain_dir}/${RUST_TARGET}/lib"
        ;;
    esac
    case "${RUST_TARGET}" in
      aarch64* | arm64*)
        # Refs: https://gitlab.com/Linaro/windowsonarm/woa-linux/-/blob/master/containers/unified.Dockerfile
        wine_root=/opt/wine-arm64
        wine_exe="${wine_root}"/bin/wine
        qemu_arch=aarch64
        case "${host_arch}" in
          x86_64)
            for bin in wine wineserver wine-preloader; do
              sed -Ei "s/qemu-${qemu_arch}-static/qemu-${qemu_arch}/g" "${wine_root}/bin/${bin}"
            done
            cp -- "${wine_root}"/lib/ld-linux-aarch64.so.1 /lib/
            [[ -f "${toolchain_dir}/bin/qemu-${qemu_arch}" ]] || cp -- "$(type -P "qemu-${qemu_arch}")" "${toolchain_dir}/bin"
            "qemu-${qemu_arch}" --version
            ;;
          aarch64)
            for bin in wine wineserver wine-preloader; do
              sed -Ei "s/qemu-${qemu_arch}-static//g" "${wine_root}/bin/${bin}"
            done
            ;;
          *) bail "unsupported host architecture '${host_arch}'" ;;
        esac
        ;;
      *) wine_exe=wine ;;
    esac
    cat >|"${toolchain_dir}/bin/${runner}" <<EOF
#!/bin/sh
set -eu
toolchain_dir="\$(cd -- "\$(dirname -- "\$0")"/.. && pwd)"
export WINEPATH="${winepath};\${WINEPATH:-}"
exec ${wine_exe} "\$@"
EOF
    chmod +x "${toolchain_dir}/bin/${runner}"
    cat -- "${toolchain_dir}/bin/${runner}"
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
