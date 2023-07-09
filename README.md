# rust-cross-toolchain

- [Platform Support](#platform-support)
  - [Linux (GNU)](#linux-gnu)
  - [Linux (musl)](#linux-musl)
  - [Linux (uClibc)](#linux-uclibc)
  - [Android](#android)
  - [FreeBSD](#freebsd)
  - [NetBSD](#netbsd)
  - [OpenBSD](#openbsd)
  - [DragonFly BSD](#dragonfly-bsd)
  - [Solaris](#solaris)
  - [illumos](#illumos)
  - [Redox](#redox)
  - [WASI](#wasi)
  - [Emscripten](#emscripten)
  - [Windows (GNU)](#windows-gnu)
  - [No-std](#no-std)

## Platform Support

### Linux (GNU)

| libc | GCC | clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| glibc [1] | [1] | host [3] | ✓ (libstdc++) | ✓ (qemu) [2] | [1] |

[1] See target list below for details<br>
[2] Except for powerpc-unknown-linux-gnuspe, riscv32gc-unknown-linux-gnu, and x86_64-unknown-linux-gnux32<br>
[3] Except for sparc-unknown-linux-gnu<br>

([Dockerfile](docker/linux-gnu.Dockerfile))

**Supported targets**:

| target | glibc | GCC | host |
| ------ | ----- | --- | ---- |
| `aarch64-unknown-linux-gnu` | 2.27 (x86_64 host) / host (aarch64 host) | 7.4.0 (x86_64 host) / host (aarch64 host) | x86_64 linux (glibc 2.27+) |
| `aarch64_be-unknown-linux-gnu` (tier3) | 2.31 | 10.2.1 | x86_64 linux (glibc 2.27+) |
| `armeb-unknown-linux-gnueabi` (tier3) | 2.25 | 7.5.0 | x86_64 linux (glibc 2.27+) |
| `arm-unknown-linux-gnueabi` | 2.27 | 7.4.0 | x86_64/aarch64 linux (glibc 2.27+) |
| `arm-unknown-linux-gnueabihf` | 2.24 | 9.4.0 | x86_64/aarch64 linux (glibc 2.27+) |
| `armv5te-unknown-linux-gnueabi` | 2.27 | 7.4.0 | x86_64/aarch64 linux (glibc 2.27+) |
| `armv7-unknown-linux-gnueabi` | 2.27 | 7.4.0 | x86_64/aarch64 linux (glibc 2.27+) |
| `armv7-unknown-linux-gnueabihf` | 2.27 | 7.4.0 | x86_64/aarch64 linux (glibc 2.27+) |
| `i586-unknown-linux-gnu` | 2.27 | 7.4.0 | x86_64/aarch64 linux (glibc 2.27+) |
| `i686-unknown-linux-gnu` | 2.27 | 7.4.0 | x86_64/aarch64 linux (glibc 2.27+) |
| `mips-unknown-linux-gnu` | 2.27 | 7.4.0 | x86_64 linux (glibc 2.27+) |
| `mips64-unknown-linux-gnuabi64` | 2.27 | 7.4.0 | x86_64 linux (glibc 2.27+) |
| `mips64el-unknown-linux-gnuabi64` | 2.27 | 7.4.0 | x86_64 linux (glibc 2.27+) |
| `mipsel-unknown-linux-gnu` | 2.27 | 7.4.0 | x86_64 linux (glibc 2.27+) |
| `mipsisa32r6-unknown-linux-gnu` (tier3) | 2.31 | 9.3.0 | x86_64 linux (glibc 2.31+) |
| `mipsisa32r6el-unknown-linux-gnu` (tier3) | 2.31 | 9.3.0 | x86_64 linux (glibc 2.31+) |
| `mipsisa64r6-unknown-linux-gnuabi64` (tier3) | 2.31 | 9.3.0 | x86_64 linux (glibc 2.31+) |
| `mipsisa64r6el-unknown-linux-gnuabi64` (tier3) | 2.31 | 9.3.0 | x86_64 linux (glibc 2.31+) |
| `powerpc-unknown-linux-gnu` | 2.27 | 7.4.0 | x86_64 linux (glibc 2.27+) |
| `powerpc-unknown-linux-gnuspe` (tier3) | 2.27 | 7.4.0 | x86_64 linux (glibc 2.27+) |
| `powerpc64-unknown-linux-gnu` | 2.27 | 7.4.0 | x86_64 linux (glibc 2.27+) |
| `powerpc64le-unknown-linux-gnu` | 2.27 | 7.4.0 | x86_64/aarch64 linux (glibc 2.27+) |
| `riscv32gc-unknown-linux-gnu` (tier3) | 2.33 | 11.1.0 | x86_64 linux (glibc 2.27+) |
| `riscv64gc-unknown-linux-gnu` | 2.27 | 7.4.0 | x86_64/aarch64 linux (glibc 2.27+) |
| `s390x-unknown-linux-gnu` | 2.27 | 7.4.0 | x86_64/aarch64 linux (glibc 2.27+) |
| `sparc64-unknown-linux-gnu` | 2.27 | 7.4.0 | x86_64 linux (glibc 2.27+) |
| `thumbv7neon-unknown-linux-gnueabihf` | 2.27 | 7.4.0 | x86_64/aarch64 linux (glibc 2.27+) |
| `x86_64-unknown-linux-gnu` | host (x86_64 host) / 2.27 (aarch64 host) | host (x86_64 host) / 7.4.0 (aarch64 host) | x86_64/aarch64 linux (glibc 2.27+) |
| `x86_64-unknown-linux-gnux32` | 2.27 | 7.4.0 | x86_64/aarch64 linux (glibc 2.27+) |

### Linux (musl)

| libc | GCC | clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| musl 1.1.24 [1] [2] / 1.2.3 | 9.4.0 | host | ✓ (libstdc++) | ✓ (qemu) | x86_64 linux (any libc) |

[1] Default (see [libc#1848] for details)<br>
[2] With a patch that fixes CVE-2020-28928<br>

([Dockerfile](docker/linux-musl.Dockerfile))

[libc#1848]: https://github.com/rust-lang/libc/issues/1848

**Supported targets**:

- `aarch64-unknown-linux-musl`
- `arm-unknown-linux-musleabi`
- `arm-unknown-linux-musleabihf`
- `armv5te-unknown-linux-musleabi`
- `armv7-unknown-linux-musleabi`
- `armv7-unknown-linux-musleabihf`
- `i586-unknown-linux-musl`
- `i686-unknown-linux-musl`
- `mips-unknown-linux-musl`
- `mips64-unknown-linux-muslabi64`
- `mips64el-unknown-linux-muslabi64`
- `mipsel-unknown-linux-musl`
- `powerpc-unknown-linux-musl` (tier3)
- `powerpc64le-unknown-linux-musl` (tier3)
- `s390x-unknown-linux-musl` (tier3)
- `thumbv7neon-unknown-linux-musleabihf` (tier3)
- `x86_64-unknown-linux-musl`

### Linux (uClibc)

| libc | GCC | clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| uClibc-ng 1.0.34 | 10.2.0 | host | ✓ (libstdc++) | ✓ (qemu) | x86_64 linux (glibc 2.27+) |

([Dockerfile](docker/linux-uclibc.Dockerfile))

**Supported targets**:

- `armv5te-unknown-linux-uclibceabi` (tier3)
- `armv7-unknown-linux-uclibceabi` (tier3)
- `armv7-unknown-linux-uclibceabihf` (tier3)

### Android

| libc | GCC | clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| [1] | 4.9 | 5.0 | ? (libc++) |  | x86_64 linux (glibc 2.27+) |

[1] See target list below for details<br>

([Dockerfile](docker/android.Dockerfile))

**Supported targets**:

| target | NDK version |
| ------ | ------- |
| `aarch64-linux-android` | 21 |
| `arm-linux-androideabi` [1] | 14 (default), 21 |
| `armv7-linux-androideabi` | 14 (default), 21 |
| `i686-linux-android` | 14 (default), 21 |
| `thumbv7neon-linux-androideabi` | 14 (default), 21 |
| `x86_64-linux-android` | 21 |

[1] The pre-compiled libraries distributed by rustup targets armv7a because [it uses](https://github.com/rust-lang/rust/blob/1.70.0/src/bootstrap/cc_detect.rs#L239) the [default arm-linux-androideabi-clang](https://android.googlesource.com/platform/ndk/+/refs/heads/ndk-r15-release/docs/user/standalone_toolchain.md#abi-compatibility). To target armv5te, which is the minimum supported architecture of arm-linux-androideabi, you need to recompile the standard library with arm-linux-androideabi-gcc.

### FreeBSD

| libc | GCC | clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| freebsd [1] | N/A | host | ✓ (libc++) |  | [1] |

[1] See target list below for details<br>

([Dockerfile](docker/freebsd.Dockerfile))

**Supported targets**:

| target | version | host |
| ------ | ------- | ---- |
| `aarch64-unknown-freebsd` (tier3) | 12.4 (default), 13.1 | linux (any arch, any libc) |
| `i686-unknown-freebsd` | 12.4 (default), 13.1 | linux (any arch, any libc) |
| `powerpc-unknown-freebsd` (tier3) | 13.1 | linux (any arch, any libc) |
| `powerpc64-unknown-freebsd` (tier3) | 13.1 | linux (any arch, any libc) |
| `powerpc64le-unknown-freebsd` (tier3) | 13.1 | linux (any arch, any libc) |
| `riscv64gc-unknown-freebsd` (tier3) | 13.1 | x86_64 linux (glibc 2.27+) |
| `x86_64-unknown-freebsd` | 12.4 (default), 13.1 | linux (any arch, any libc) |

### NetBSD

| libc | GCC | clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| netbsd [1] | 7.5.0 | host | ✓ (libstdc++) |  | x86_64 linux (glibc 2.27+) |

[1] See target list below for details<br>

([Dockerfile](docker/netbsd.Dockerfile))

**Supported targets**:

| target | version |
| ------ | ------- |
| `aarch64-unknown-netbsd` (tier3) | 9.3 |
| `armv6-unknown-netbsd-eabihf` (tier3) | 8.2 (default), 9.3 |
| `armv7-unknown-netbsd-eabihf` (tier3) | 8.2 (default), 9.3 |
| `i686-unknown-netbsd` (tier3) | 8.2 (default), 9.3 |
| `powerpc-unknown-netbsd` (tier3) | 8.2 (default), 9.3 |
| `sparc64-unknown-netbsd` (tier3) | 8.2 (default), 9.3 |
| `x86_64-unknown-netbsd` | 8.2 (default), 9.3 |

### OpenBSD

| libc | GCC | clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| openbsd [1] | N/A | host | ✓ (libc++) [2] |  | [1] |

[1] See target list below for details<br>
[2] Except for aarch64-unknown-openbsd and sparc64-unknown-openbsd<br>

([Dockerfile](docker/openbsd.Dockerfile))

**Supported targets**:

| target | version | host |
| ------ | ------- | ---- |
| `aarch64-unknown-openbsd` (tier3) | 7.2 (default), 7.3 | linux (any arch, any libc) |
| `i686-unknown-openbsd` (tier3) | 7.2 (default), 7.3 | linux (any arch, any libc) |
| `powerpc-unknown-openbsd` (tier3) | 7.2 (default), 7.3 | linux (any arch, any libc) |
| `powerpc64-unknown-openbsd` (tier3) | 7.2 (default), 7.3 | linux (any arch, any libc) |
| `riscv64gc-unknown-openbsd` (tier3) | 7.2 (default), 7.3 | linux (any arch, any libc) |
| `sparc64-unknown-openbsd` (tier3) | 7.2 (default), 7.3 | x86_64 linux (glibc 2.27+) |
| `x86_64-unknown-openbsd` (tier3) | 7.2 (default), 7.3 | linux (any arch, any libc) |

### DragonFly BSD

| libc | GCC | clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| dragonfly 6.4.0 | N/A | host (requires 13+) | ✓ (libstdc++) |  | linux (any arch, any libc) |

([Dockerfile](docker/dragonfly.Dockerfile))

**Supported targets**:

- `x86_64-unknown-dragonfly` (tier3)

### Solaris

| libc | GCC | clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| solaris 2.11 | 8.5.0 |  | ✓ (libstdc++) |  | x86_64 linux (glibc 2.27+) |

([Dockerfile](docker/solaris.Dockerfile))

**Supported targets**:

- `sparcv9-sun-solaris`
- `x86_64-pc-solaris`
- `x86_64-sun-solaris`

### illumos

| libc | GCC | clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| solaris 2.10 | 8.5.0 | host | ✓ (libstdc++) |  | x86_64 linux (glibc 2.27+) |

([Dockerfile](docker/illumos.Dockerfile))

**Supported targets**:

- `x86_64-unknown-illumos`

### Redox

| libc | GCC | clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| redox 0.6.0 | 8.2.0 | host | ✓ (libstdc++) |  | x86_64 linux (glibc 2.31+) |

([Dockerfile](docker/redox.Dockerfile))

<!--
TODO: I guess libc from https://static.redox-os.org/toolchain is for the latest version of redox, but I'm not 100% sure it is correct.
https://gitlab.redox-os.org/redox-os/redox/-/releases
-->

**Supported targets**:

- `x86_64-unknown-redox`

### WASI

| libc | GCC | clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| wasi-sdk 16 (wasi-libc 30094b6) | N/A | 14.0.4 | ? (libc++) | ✓ (wasmtime) | x86_64 linux (glibc 2.31+) |

<!--
clang version and wasi-libc hash can be found here: https://github.com/WebAssembly/wasi-sdk/tree/wasi-sdk-16/src
-->

([Dockerfile](docker/wasi.Dockerfile))

**Supported targets**:

- `wasm32-wasi`

### Emscripten

| libc | GCC | clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| emscripten 1.39.20 | N/A |  | ✓ (libc++) | ✓ (node) | x86_64 linux (glibc 2.27+) |

([Dockerfile](docker/emscripten.Dockerfile))

**Supported targets**:

- `asmjs-unknown-emscripten`
- `wasm32-unknown-emscripten`

### Windows (GNU)

| libc | GCC | clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| Mingw-w64 7.0.0 | 9.3.0 | host | ✓ (libstdc++) | ✓ (wine) | [1] |

<!--
Mingw-w64 version: https://packages.ubuntu.com/en/focal/mingw-w64-common
GCC version: https://packages.ubuntu.com/en/focal/gcc-mingw-w64-base
-->

[1] See target list below for details<br>

([Dockerfile](docker/windows-gnu.Dockerfile))

**Supported targets**:

| target | host |
| ------ | ---- |
| `x86_64-pc-windows-gnu` | x86_64/aarch64 linux (glibc 2.31+) |
| `i686-pc-windows-gnu` | x86_64 linux (glibc 2.31+) |

### No-std

| libc | GCC | clang | C++ | run | host |
| ---- | --- | ----- | --- | ---- | ---- |
| newlib 4.1.0 | [1] |  | ✓ (libstdc++) | [1] | [1] |

[1] See target list below for details<br>

([Dockerfile](docker/none.Dockerfile))

**Supported targets**:

| target | GCC | run | host |
| ------ | --- | ---- | ---- |
| `aarch64-unknown-none` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 linux (glibc 2.27+) |
| `aarch64-unknown-none-softfloat` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 linux (glibc 2.27+) |
| `armebv7r-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 linux (glibc 2.27+) |
| `armebv7r-none-eabihf` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 linux (glibc 2.27+) |
| `armv5te-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 linux (glibc 2.27+) |
| `armv7a-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 linux (glibc 2.27+) |
| `armv7a-none-eabihf` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 linux (glibc 2.27+) |
| `armv7r-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 linux (glibc 2.27+) |
| `armv7r-none-eabihf` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 linux (glibc 2.27+) |
| `riscv32i-unknown-none-elf` | 11.1.0 | ✓ (qemu) | x86_64 linux (glibc 2.27+) |
| `riscv32im-unknown-none-elf` (tier3) | 11.1.0 | ✓ (qemu) | x86_64 linux (glibc 2.27+) |
| `riscv32imac-unknown-none-elf` | 11.1.0 | ✓ (qemu) | x86_64 linux (glibc 2.27+) |
| `riscv32imc-unknown-none-elf` | 11.1.0 | ✓ (qemu) | x86_64 linux (glibc 2.27+) |
| `riscv64gc-unknown-none-elf` | 11.1.0 | ✓ (qemu) | x86_64 linux (glibc 2.27+) |
| `riscv64imac-unknown-none-elf` | 11.1.0 | ✓ (qemu) | x86_64 linux (glibc 2.27+) |
| `thumbv5te-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 linux (glibc 2.27+) |
| `thumbv6m-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 linux (glibc 2.27+) |
| `thumbv7em-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 linux (glibc 2.27+) |
| `thumbv7em-none-eabihf` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 linux (glibc 2.27+) |
| `thumbv7m-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 linux (glibc 2.27+) |
| `thumbv8m.base-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 linux (glibc 2.27+) |
| `thumbv8m.main-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 linux (glibc 2.27+) |
| `thumbv8m.main-none-eabihf` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 linux (glibc 2.27+) |
