#!/bin/false
# shellcheck shell=bash # not executable
# shellcheck disable=SC2034

# Linux (GNU)
# rustup target list | grep -e '-linux-gnu'
# rustc --print target-list | grep -e '-linux-gnu'
linux_gnu_targets=(
    aarch64-unknown-linux-gnu
    # aarch64-unknown-linux-gnu_ilp32 # tier3
    aarch64_be-unknown-linux-gnu # tier3
    # aarch64_be-unknown-linux-gnu_ilp32 # tier3
    arm-unknown-linux-gnueabi
    arm-unknown-linux-gnueabihf
    # armeb-unknown-linux-gnueabi # tier3
    # armv4t-unknown-linux-gnueabi # tier3, rustc generate code for armv5t (probably needs to pass +v4t to llvm)
    armv5te-unknown-linux-gnueabi
    armv7-unknown-linux-gnueabi
    armv7-unknown-linux-gnueabihf
    i586-unknown-linux-gnu
    i686-unknown-linux-gnu
    # m68k-unknown-linux-gnu # tier3, build fail: https://github.com/rust-lang/rust/issues/89498
    mips-unknown-linux-gnu
    mips64-unknown-linux-gnuabi64
    mips64el-unknown-linux-gnuabi64
    mipsel-unknown-linux-gnu
    mipsisa32r6-unknown-linux-gnu        # tier3
    mipsisa32r6el-unknown-linux-gnu      # tier3
    mipsisa64r6-unknown-linux-gnuabi64   # tier3
    mipsisa64r6el-unknown-linux-gnuabi64 # tier3
    powerpc-unknown-linux-gnu
    powerpc-unknown-linux-gnuspe # tier3
    powerpc64-unknown-linux-gnu
    powerpc64le-unknown-linux-gnu
    riscv32gc-unknown-linux-gnu # tier3
    riscv64gc-unknown-linux-gnu
    s390x-unknown-linux-gnu
    # sparc-unknown-linux-gnu # tier3
    sparc64-unknown-linux-gnu
    thumbv7neon-unknown-linux-gnueabihf
    x86_64-unknown-linux-gnu
    x86_64-unknown-linux-gnux32
)
# Linux (musl)
# rustup target list | grep -e '-linux-musl'
# rustc --print target-list | grep -e '-linux-musl'
linux_musl_targets=(
    aarch64-unknown-linux-musl
    arm-unknown-linux-musleabi
    arm-unknown-linux-musleabihf
    armv5te-unknown-linux-musleabi
    armv7-unknown-linux-musleabi
    armv7-unknown-linux-musleabihf
    # hexagon-unknown-linux-musl # tier3, musl-cross-make doesn't support this target
    i586-unknown-linux-musl
    i686-unknown-linux-musl
    mips-unknown-linux-musl
    # mips64-openwrt-linux-musl # tier3, https://github.com/rust-lang/rust/pull/92300
    mips64-unknown-linux-muslabi64
    mips64el-unknown-linux-muslabi64
    mipsel-unknown-linux-musl
    powerpc-unknown-linux-musl # tier3
    # powerpc64-unknown-linux-musl # tier3, ABI version 1 is not compatible with ABI version 2 output
    powerpc64le-unknown-linux-musl # tier3
    # riscv32gc-unknown-linux-musl # tier3, musl-cross-make doesn't support this target
    riscv64gc-unknown-linux-musl         # tier3
    s390x-unknown-linux-musl             # tier3
    thumbv7neon-unknown-linux-musleabihf # tier3
    x86_64-unknown-linux-musl
)
# Linux (uClibc)
# rustc --print target-list | grep -e '-linux-uclibc'
linux_uclibc_targets=(
    armv5te-unknown-linux-uclibceabi # tier3
    # armv7-unknown-linux-uclibceabi   # tier3, As of 2022-06-13, bootlin doesn't seem to provide toolchain for this target
    armv7-unknown-linux-uclibceabihf # tier3
    # mips-unknown-linux-uclibc        # tier3, error: Undefined temporary symbol $BB6_15
    # mipsel-unknown-linux-uclibc      # tier3, error: Undefined temporary symbol $BB6_15
)
# Android
# rustup target list | grep -e '-android'
# rustc --print target-list | grep -e '-android'
android_targets=(
    aarch64-linux-android
    arm-linux-androideabi
    armv7-linux-androideabi
    i686-linux-android
    thumbv7neon-linux-androideabi
    x86_64-linux-android
)
# macOS
# rustup target list | grep -e '-darwin'
# rustc --print target-list | grep -e '-darwin'
macos_targets=(
    # aarch64-apple-darwin
    # # i686-apple-darwin # tier3
    # x86_64-apple-darwin
)
# iOS
# rustup target list | grep -e '-ios'
# rustc --print target-list | grep -e '-ios'
ios_targets=(
    # aarch64-apple-ios
    # # aarch64-apple-ios-macabi # tier3
    # aarch64-apple-ios-sim
    # # armv7-apple-ios # tier3
    # # armv7s-apple-ios # tier3
    # # i386-apple-ios # tier3
    # x86_64-apple-ios
    # # x86_64-apple-ios-macabi # tier3
)
# tvOS
# rustc --print target-list | grep -e '-tvos'
tvos_targets=(
    # aarch64-apple-tvos # tier3
    # x86_64-apple-tvos # tier3
)
# watchOS
# rustc --print target-list | grep -e '-watchos'
watchos_targets=(
    # aarch64-apple-watchos-sim # tier3
    # arm64_32-apple-watchos    # tier3
    # armv7k-apple-watchos      # tier3
    # x86_64-apple-watchos-sim  # tier3
)
# FreeBSD
# rustup target list | grep -e '-freebsd'
# rustc --print target-list | grep -e '-freebsd'
freebsd_targets=(
    aarch64-unknown-freebsd # tier3
    # armv6-unknown-freebsd # tier3
    # armv7-unknown-freebsd # tier3
    i686-unknown-freebsd
    powerpc-unknown-freebsd     # tier3
    powerpc64-unknown-freebsd   # tier3
    powerpc64le-unknown-freebsd # tier3
    riscv64gc-unknown-freebsd   # tier3
    x86_64-unknown-freebsd
)
# NetBSD
# rustup target list | grep -e '-netbsd'
# rustc --print target-list | grep -e '-netbsd'
netbsd_targets=(
    aarch64-unknown-netbsd      # tier3
    armv6-unknown-netbsd-eabihf # tier3
    armv7-unknown-netbsd-eabihf # tier3
    i686-unknown-netbsd         # tier3
    powerpc-unknown-netbsd      # tier3
    sparc64-unknown-netbsd      # tier3
    x86_64-unknown-netbsd
)
# OpenBSD
# rustc --print target-list | grep -e '-openbsd'
openbsd_targets=(
    aarch64-unknown-openbsd   # tier3
    i686-unknown-openbsd      # tier3
    powerpc-unknown-openbsd   # tier3
    powerpc64-unknown-openbsd # tier3
    riscv64gc-unknown-openbsd # tier3
    sparc64-unknown-openbsd   # tier3
    x86_64-unknown-openbsd    # tier3
)
# DragonFly BSD
# rustc --print target-list | grep -e '-dragonfly'
dragonfly_targets=(
    x86_64-unknown-dragonfly # tier3
)
# Solaris
# rustup target list | grep -e '-solaris'
# rustc --print target-list | grep -e '-solaris'
solaris_targets=(
    sparcv9-sun-solaris
    x86_64-pc-solaris
    x86_64-sun-solaris
)
# illumos
# rustup target list | grep -e '-illumos'
# rustc --print target-list | grep -e '-illumos'
illumos_targets=(
    x86_64-unknown-illumos
)
# Windows (MSVC)
# rustup target list | grep -e '-windows-msvc'
# rustc --print target-list | grep -e '-windows-msvc'
windows_msvc_targets=(
    # aarch64-pc-windows-msvc
    # aarch64-uwp-windows-msvc # tier3
    # i586-pc-windows-msvc
    # i686-pc-windows-msvc
    # i686-uwp-windows-msvc # tier3
    # thumbv7a-pc-windows-msvc # tier3
    # thumbv7a-uwp-windows-msvc # tier3
    # x86_64-pc-windows-msvc
    # x86_64-uwp-windows-msvc # tier3
)
# Windows (GNU)
# rustup target list | grep -e '-windows-gnu'
# rustc --print target-list | grep -e '-windows-gnu'
windows_gnu_targets=(
    # aarch64-pc-windows-gnullvm # tier3
    i686-pc-windows-gnu
    # i686-uwp-windows-gnu # tier3
    x86_64-pc-windows-gnu
    # x86_64-pc-windows-gnullvm # tier3
    # x86_64-uwp-windows-gnu # tier3
)
# WASI
# rustup target list | grep -e '-wasi'
# rustc --print target-list | grep -e '-wasi'
wasi_targets=(
    wasm32-wasi
)
# Emscripten
# rustup target list | grep -e '-emscripten'
# rustc --print target-list | grep -e '-emscripten'
emscripten_targets=(
    asmjs-unknown-emscripten
    wasm32-unknown-emscripten
)
# WebAssembly (unknown)
# rustup target list | grep -e '-unknown-unknown'
# rustc --print target-list | grep -e '-unknown-unknown'
wasm_targets=(
    # wasm32-unknown-unknown
    # wasm64-unknown-unknown # tier3
)
# AIX
# rustc --print target-list | grep -e '-aix'
aix_targets=(
    # powerpc64-ibm-aix # tier3
)
# CUDA
# rustup target list | grep -e '-cuda'
# rustc --print target-list | grep -e '-cuda'
cuda_targets=(
    # nvptx64-nvidia-cuda
)
# ESP-IDF
# rustc --print target-list | grep -e '-espidf'
espidf_targets=(
    # riscv32imc-esp-espidf # tier3
)
# Fuchsia
# rustup target list | grep -e '-fuchsia'
# rustc --print target-list | grep -e '-fuchsia'
fuchsia_targets=(
    # aarch64-fuchsia
    # x86_64-fuchsia
)
# Haiku
# rustc --print target-list | grep -e '-haiku'
haiku_targets=(
    # i686-unknown-haiku # tier3
    # x86_64-unknown-haiku # tier3
)
# Hermit
# rustc --print target-list | grep -e '-unknown-hermit'
hermit_targets=(
    # aarch64-unknown-hermit # tier3
    # x86_64-unknown-hermit # tier3
)
# Horizon
# rustc --print target-list | grep -e '-nintendo'
horizon_targets=(
    # armv6k-nintendo-3ds # tier3
)
# L4Re
# rustc --print target-list | grep -e '-l4re'
l4re_targets=(
    # x86_64-unknown-l4re-uclibc # tier3
)
# QNX Neutrino
# rustc --print target-list | grep -e '-nto'
nto_targets=(
    # aarch64-unknown-nto-qnx710 # tier3
    # x86_64-pc-nto-qnx710 # tier3
)
# PSP
# rustc --print target-list | grep -e '-psp'
psp_targets=(
    # mipsel-sony-psp # tier3
)
# PSP
# rustc --print target-list | grep -e '-psx'
psx_targets=(
    # mipsel-sony-psx # tier3
)
# Redox
# rustup target list | grep -e '-redox'
# rustc --print target-list | grep -e '-redox'
redox_targets=(
    # aarch64-unknown-redox # tier3
    x86_64-unknown-redox
)
# SGX
# rustup target list | grep -e '-sgx'
# rustc --print target-list | grep -e '-sgx'
sgx_targets=(
    # x86_64-fortanix-unknown-sgx
)
# SOLID
# rustc --print target-list | grep -e '-solid_asp3'
solid_asp3_targets=(
    # aarch64-kmc-solid_asp3 # tier3
    # armv7a-kmc-solid_asp3-eabi # tier3
    # armv7a-kmc-solid_asp3-eabihf # tier3
)
# UEFI
# rustc --print target-list | grep -e '-uefi'
uefi_targets=(
    # aarch64-unknown-uefi # tier3
    # i686-unknown-uefi # tier3
    # x86_64-unknown-uefi # tier3
)
# VxWorks
# rustc --print target-list | grep -e '-vxworks'
vxworks_targets=(
    # aarch64-wrs-vxworks # tier3
    # armv7-wrs-vxworks-eabihf # tier3
    # i686-wrs-vxworks # tier3
    # powerpc-wrs-vxworks # tier3
    # powerpc-wrs-vxworks-spe # tier3
    # powerpc64-wrs-vxworks # tier3
    # x86_64-wrs-vxworks # tier3
)
xous_targets=(
    # riscv32imac-unknown-xous-elf # tier3
)
# no-std
# rustup target list | grep -e '-none'
# rustc --print target-list | grep -e '-none'
none_targets=(
    aarch64-unknown-none
    # aarch64-unknown-none-hermitkernel # tier3
    aarch64-unknown-none-softfloat
    armebv7r-none-eabi
    armebv7r-none-eabihf
    # armv4t-none-eabi # tier3
    # armv5te-none-eabi # tier3
    armv7a-none-eabi
    armv7a-none-eabihf # tier3
    armv7r-none-eabi
    armv7r-none-eabihf
    # avr-unknown-gnu-atmega328 # tier3
    # bpfeb-unknown-none # tier3
    # bpfel-unknown-none # tier3
    # mipsel-unknown-none # tier3
    # msp430-none-elf # tier3
    riscv32i-unknown-none-elf
    riscv32im-unknown-none-elf # tier3
    riscv32imac-unknown-none-elf
    riscv32imc-unknown-none-elf
    riscv64gc-unknown-none-elf
    riscv64imac-unknown-none-elf
    # thumbv4t-none-eabi # tier3
    # thumbv5te-none-eabi # tier3
    thumbv6m-none-eabi
    thumbv7em-none-eabi
    thumbv7em-none-eabihf
    thumbv7m-none-eabi
    thumbv8m.base-none-eabi
    thumbv8m.main-none-eabi
    thumbv8m.main-none-eabihf
    # x86_64-unknown-none # tier3
)
targets=(
    ${linux_gnu_targets[@]+"${linux_gnu_targets[@]}"}
    ${linux_musl_targets[@]+"${linux_musl_targets[@]}"}
    ${linux_uclibc_targets[@]+"${linux_uclibc_targets[@]}"}
    ${android_targets[@]+"${android_targets[@]}"}
    ${macos_targets[@]+"${macos_targets[@]}"}
    ${ios_targets[@]+"${ios_targets[@]}"}
    ${tvos_targets[@]+"${tvos_targets[@]}"}
    ${watchos_targets[@]+"${watchos_targets[@]}"}
    ${freebsd_targets[@]+"${freebsd_targets[@]}"}
    ${netbsd_targets[@]+"${netbsd_targets[@]}"}
    ${openbsd_targets[@]+"${openbsd_targets[@]}"}
    ${dragonfly_targets[@]+"${dragonfly_targets[@]}"}
    ${solaris_targets[@]+"${solaris_targets[@]}"}
    ${illumos_targets[@]+"${illumos_targets[@]}"}
    ${windows_msvc_targets[@]+"${windows_msvc_targets[@]}"}
    ${windows_gnu_targets[@]+"${windows_gnu_targets[@]}"}
    ${wasi_targets[@]+"${wasi_targets[@]}"}
    ${emscripten_targets[@]+"${emscripten_targets[@]}"}
    ${wasm_unknown_targets[@]+"${wasm_unknown_targets[@]}"}
    ${aix_targets[@]+"${aix_targets[@]}"}
    ${cuda_targets[@]+"${cuda_targets[@]}"}
    ${espidf_targets[@]+"${espidf_targets[@]}"}
    ${fuchsia_targets[@]+"${fuchsia_targets[@]}"}
    ${haiku_targets[@]+"${haiku_targets[@]}"}
    ${hermit_targets[@]+"${hermit_targets[@]}"}
    ${horizon_targets[@]+"${horizon_targets[@]}"}
    ${l4re_targets[@]+"${l4re_targets[@]}"}
    ${nto_targets[@]+"${nto_targets[@]}"}
    ${psp_targets[@]+"${psp_targets[@]}"}
    ${psx_targets[@]+"${psx_targets[@]}"}
    ${redox_targets[@]+"${redox_targets[@]}"}
    ${sgx_targets[@]+"${sgx_targets[@]}"}
    ${solid_asp3_targets[@]+"${solid_asp3_targets[@]}"}
    ${uefi_targets[@]+"${uefi_targets[@]}"}
    ${vxworks_targets[@]+"${vxworks_targets[@]}"}
    ${xous_targets[@]+"${xous_targets[@]}"}
    ${none_targets[@]+"${none_targets[@]}"}
)
