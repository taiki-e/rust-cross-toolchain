# rust-cross-toolchain

Toolchains for cross compilation and cross testing for Rust.

See also [setup-cross-toolchain-action](https://github.com/taiki-e/setup-cross-toolchain-action) created based on this project.

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
  - [Windows (MinGW)](#windows-mingw)
  - [Windows (LLVM MinGW)](#windows-llvm-mingw)
  - [No-std](#no-std)

## Platform Support

### Linux (GNU)

| libc | GCC | Clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| glibc [1] | [1] | host [2] | ✓ (libstdc++) [3] | ✓ (qemu) [4] | [1] |

[1] See target list below for details<br>
[2] Except for sparc-unknown-linux-gnu and loongarch64-unknown-linux-gnu<br>
[3] Except for csky-unknown-linux-gnuabiv2\* and loongarch64-unknown-linux-gnu<br>
[4] Except for csky-unknown-linux-gnuabiv2\*, powerpc-unknown-linux-gnuspe, and x86_64-unknown-linux-gnux32<br>

([Dockerfile](docker/linux-gnu.Dockerfile))

**Supported targets:**

| target | glibc | GCC | host |
| ------ | ----- | --- | ---- |
| `aarch64-unknown-linux-gnu` | 2.27 (x86_64 host) / host (aarch64 host) | 7.4.0 (x86_64 host) / host (aarch64 host) | x86_64/aarch64 Linux (glibc 2.27+) |
| `aarch64_be-unknown-linux-gnu` (tier3) | 2.31 | 10.2.1 | x86_64 Linux (glibc 2.27+) |
| `arm-unknown-linux-gnueabi` | 2.27 | 7.4.0 | x86_64/aarch64 Linux (glibc 2.27+) |
| `arm-unknown-linux-gnueabihf` | 2.24 | 9.4.0 | x86_64/aarch64 Linux (glibc 2.27+) |
| `armeb-unknown-linux-gnueabi` (tier3) | 2.25 | 7.5.0 | x86_64 Linux (glibc 2.27+) |
| `armv5te-unknown-linux-gnueabi` | 2.27 | 7.4.0 | x86_64/aarch64 Linux (glibc 2.27+) |
| `armv7-unknown-linux-gnueabi` | 2.27 | 7.4.0 | x86_64/aarch64 Linux (glibc 2.27+) |
| `armv7-unknown-linux-gnueabihf` | 2.27 | 7.4.0 | x86_64/aarch64 Linux (glibc 2.27+) |
| `csky-unknown-linux-gnuabiv2` | 2.28 | 6.3.0 | x86_64 Linux (glibc 2.27+) |
| `csky-unknown-linux-gnuabiv2hf` | 2.28 | 6.3.0 | x86_64 Linux (glibc 2.27+) |
| `i586-unknown-linux-gnu` | 2.27 | 7.4.0 | x86_64/aarch64 Linux (glibc 2.27+) |
| `i686-unknown-linux-gnu` | 2.27 | 7.4.0 | x86_64/aarch64 Linux (glibc 2.27+) |
| `loongarch64-unknown-linux-gnu` | 2.40 | 14.2.0 | x86_64 Linux (any libc) |
| `mips-unknown-linux-gnu` (tier3) [1] | 2.27 (x86_64 host) / 2.35 (aarch64 host) | 7.4.0 (x86_64 host) / 11.2.0 (aarch64 host) | x86_64/aarch64 Linux (glibc 2.27+) / aarch64 Linux (glibc 2.35+) |
| `mips64-unknown-linux-gnuabi64` (tier3) | 2.27 (x86_64 host) / 2.35 (aarch64 host) | 7.4.0 (x86_64 host) / 11.2.0 (aarch64 host) | x86_64/aarch64 Linux (glibc 2.27+) / aarch64 Linux (glibc 2.35+) |
| `mips64el-unknown-linux-gnuabi64` (tier3) | 2.27 (x86_64 host) / 2.35 (aarch64 host) | 7.4.0 (x86_64 host) / 11.2.0 (aarch64 host) | x86_64/aarch64 Linux (glibc 2.27+) / aarch64 Linux (glibc 2.35+) |
| `mipsel-unknown-linux-gnu` (tier3) [1] | 2.27 (x86_64 host) / 2.35 (aarch64 host) | 7.4.0 (x86_64 host) / 11.2.0 (aarch64 host) | x86_64/aarch64 Linux (glibc 2.27+) / aarch64 Linux (glibc 2.35+) |
| `mipsisa32r6-unknown-linux-gnu` (tier3) | 2.31 (x86_64 host) / 2.35 (aarch64 host) | 9.3.0 (x86_64 host) / 11.2.0 (aarch64 host) | x86_64/aarch64 Linux (glibc 2.31+) / aarch64 Linux (glibc 2.35+) |
| `mipsisa32r6el-unknown-linux-gnu` (tier3) | 2.31 (x86_64 host) / 2.35 (aarch64 host) | 9.3.0 (x86_64 host) / 11.2.0 (aarch64 host) | x86_64/aarch64 Linux (glibc 2.31+) / aarch64 Linux (glibc 2.35+) |
| `mipsisa64r6-unknown-linux-gnuabi64` (tier3) | 2.31 (x86_64 host) / 2.35 (aarch64 host) | 9.3.0 (x86_64 host) / 11.2.0 (aarch64 host) | x86_64/aarch64 Linux (glibc 2.31+) / aarch64 Linux (glibc 2.35+) |
| `mipsisa64r6el-unknown-linux-gnuabi64` (tier3) | 2.31 (x86_64 host) / 2.35 (aarch64 host) | 9.3.0 (x86_64 host) / 11.2.0 (aarch64 host) | x86_64/aarch64 Linux (glibc 2.31+) / aarch64 Linux (glibc 2.35+) |
| `powerpc-unknown-linux-gnu` | 2.27 | 7.4.0 | x86_64/aarch64 Linux (glibc 2.27+) |
| `powerpc-unknown-linux-gnuspe` (tier3) | 2.27 | 7.4.0 | x86_64 Linux (glibc 2.27+) |
| `powerpc64-unknown-linux-gnu` | 2.27 | 7.4.0 | x86_64 Linux (glibc 2.27+) |
| `powerpc64le-unknown-linux-gnu` | 2.27 | 7.4.0 | x86_64/aarch64 Linux (glibc 2.27+) |
| `riscv32gc-unknown-linux-gnu` (tier3) | 2.33 | 11.1.0 | x86_64 Linux (glibc 2.27+) |
| `riscv64gc-unknown-linux-gnu` | 2.27 | 7.4.0 | x86_64/aarch64 Linux (glibc 2.27+) |
| `s390x-unknown-linux-gnu` | 2.27 | 7.4.0 | x86_64/aarch64 Linux (glibc 2.27+) |
| `sparc64-unknown-linux-gnu` | 2.27 | 7.4.0 | x86_64/aarch64 Linux (glibc 2.27+) |
| `sparc-unknown-linux-gnu` (tier3) | 2.27 | 7.4.0 | x86_64/aarch64 Linux (glibc 2.27+) |
| `thumbv7neon-unknown-linux-gnueabihf` | 2.27 | 7.4.0 | x86_64/aarch64 Linux (glibc 2.27+) |
| `x86_64-unknown-linux-gnu` | host (x86_64 host) / 2.27 (aarch64 host) | host (x86_64 host) / 7.4.0 (aarch64 host) | x86_64/aarch64 Linux (glibc 2.27+) |
| `x86_64-unknown-linux-gnux32` | 2.27 | 7.4.0 | x86_64/aarch64 Linux (glibc 2.27+) |

[1] [Since nightly-2023-07-05](https://github.com/rust-lang/compiler-team/issues/648), mips{,el}-unknown-linux-gnu requires release mode for building std<br>

### Linux (musl)

| libc | GCC | Clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| musl 1.2.3 [6] | 9.4.0 [1] | [2] | ✓ (libstdc++) [1] | ✓ (qemu) [3] [4] | [5] |

[1] 8.5.0 for powerpc-unknown-linux-muslspe, 13.2.0 for risc64gc-unknown-linux-musl, unavailable for hexagon-unknown-linux-musl<br>
[2] 17.0.0-rc3 for hexagon-unknown-linux-musl, otherwise host<br>
[3] hexagon-unknown-linux-musl requires release mode for building test<br>
[4] Except for powerpc-unknown-linux-muslspe and riscv32gc-unknown-linux-musl<br>
[5] See target list below for details<br>
[6] 1.2.5 for riscv32

([Dockerfile](docker/linux-musl.Dockerfile))

**Supported targets:**

| target | host |
| ------ | ---- |
| `aarch64-unknown-linux-musl` | x86_64/aarch64 Linux (any libc) |
| `arm-unknown-linux-musleabi` | x86_64/aarch64 Linux (any libc) |
| `arm-unknown-linux-musleabihf` | x86_64/aarch64 Linux (any libc) |
| `armv5te-unknown-linux-musleabi` | x86_64/aarch64 Linux (any libc) |
| `armv7-unknown-linux-musleabi` | x86_64/aarch64 Linux (any libc) |
| `armv7-unknown-linux-musleabihf` | x86_64/aarch64 Linux (any libc) |
| `hexagon-unknown-linux-musl` (tier3) | x86_64 Linux (glibc 2.27+) |
| `i586-unknown-linux-musl` | x86_64/aarch64 Linux (any libc) |
| `i686-unknown-linux-musl` | x86_64/aarch64 Linux (any libc) |
| `mips-unknown-linux-musl` (tier3) | x86_64/aarch64 Linux (any libc) |
| `mips64-unknown-linux-muslabi64` (tier3) | x86_64/aarch64 Linux (any libc) |
| `mips64el-unknown-linux-muslabi64` (tier3) | x86_64/aarch64 Linux (any libc) |
| `mipsel-unknown-linux-musl` (tier3) | x86_64/aarch64 Linux (any libc) |
| `powerpc-unknown-linux-musl` (tier3) | x86_64/aarch64 Linux (any libc) |
| `powerpc-unknown-linux-muslspe` (tier3) | x86_64/aarch64 Linux (any libc) |
| `powerpc64le-unknown-linux-musl` | x86_64/aarch64 Linux (any libc) |
| `riscv32gc-unknown-linux-musl` (tier3) | x86_64/aarch64 Linux (any libc) |
| `riscv64gc-unknown-linux-musl` | x86_64/aarch64 Linux (any libc) |
| `s390x-unknown-linux-musl` (tier3) | x86_64/aarch64 Linux (any libc) |
| `thumbv7neon-unknown-linux-musleabihf` (tier3) | x86_64/aarch64 Linux (any libc) |
| `x86_64-unknown-linux-musl` | x86_64/aarch64 Linux (any libc) |

### Linux (uClibc)

| libc | GCC | Clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| uClibc-ng 1.0.34 | 10.2.0 | host | ✓ (libstdc++) | ✓ (qemu) | x86_64 Linux (glibc 2.17+) |

([Dockerfile](docker/linux-uclibc.Dockerfile))

**Supported targets:**

- `armv5te-unknown-linux-uclibceabi` (tier3)
- `armv7-unknown-linux-uclibceabi` (tier3)
- `armv7-unknown-linux-uclibceabihf` (tier3)
- `mips-unknown-linux-uclibc` (tier3)
- `mipsel-unknown-linux-uclibc` (tier3)

[1] mips{,el}-unknown-linux-uclibc requires release mode for building std<br>

### Android

| libc | GCC | Clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| [1] | N/A | 14.0.6 | ? (libc++) | ✓ (qemu) | x86_64 Linux (glibc 2.17+) |

[1] See target list below for details<br>

([Dockerfile](docker/android.Dockerfile))

**Supported targets:**

| target | API level |
| ------ | ------- |
| `aarch64-linux-android` | 21 |
| `arm-linux-androideabi` | 21 |
| `armv7-linux-androideabi` | 21 |
| `i686-linux-android` | 21 |
| `thumbv7neon-linux-androideabi` | 21 |
| `x86_64-linux-android` | 21 |

### FreeBSD

| libc | GCC | Clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| freebsd [1] | N/A | host | ✓ (libc++) |  | [1] |

[1] See target list below for details<br>

([Dockerfile](docker/freebsd.Dockerfile))

**Supported targets:**

| target | version | host |
| ------ | ------- | ---- |
| `aarch64-unknown-freebsd` (tier3) | 12.4 (default), 13.4, 14.1 | Linux (any arch, any libc) |
| `i686-unknown-freebsd` | 12.4 (default), 13.4, 14.1 | Linux (any arch, any libc) |
| `powerpc-unknown-freebsd` (tier3) | 13.4 (default), 14.1 | Linux (any arch, any libc) |
| `powerpc64-unknown-freebsd` (tier3) | 13.4 (default), 14.1 | Linux (any arch, any libc) |
| `powerpc64le-unknown-freebsd` (tier3) | 13.4 (default), 14.1 | Linux (any arch, any libc) |
| `riscv64gc-unknown-freebsd` (tier3) | 13.4 (default), 14.1 | x86_64/aarch64 Linux (any libc) |
| `x86_64-unknown-freebsd` | 12.4 (default), 13.4, 14.1 | Linux (any arch, any libc) |

### NetBSD

| libc | GCC | Clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| netbsd [1] | 7.5.0 | host | ✓ (libstdc++) |  | x86_64 Linux (glibc 2.27+) |

[1] See target list below for details<br>

([Dockerfile](docker/netbsd.Dockerfile))

**Supported targets:**

| target | version |
| ------ | ------- |
| `aarch64-unknown-netbsd` (tier3) | 9.4 (default), 10.0 |
| `aarch64_be-unknown-netbsd` (tier3) | 10.0 |
| `armv6-unknown-netbsd-eabihf` (tier3) | 9.4 (default), 10.0 |
| `armv7-unknown-netbsd-eabihf` (tier3) | 9.4 (default), 10.0 |
| `i586-unknown-netbsd` (tier3) | 9.4 (default), 10.0 |
| `i686-unknown-netbsd` (tier3) | 9.4 (default), 10.0 |
| `mipsel-unknown-netbsd` (tier3) | 9.4 (default), 10.0 |
| `powerpc-unknown-netbsd` (tier3) | 9.4 (default), 10.0 |
| `sparc64-unknown-netbsd` (tier3) | 9.4 (default), 10.0 |
| `x86_64-unknown-netbsd` | 9.4 (default), 10.0 |

### OpenBSD

| libc | GCC | Clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| openbsd [1] | N/A | host | ✓ (libc++) [2] |  | [1] |

[1] See target list below for details<br>
[2] Except for aarch64-unknown-openbsd and sparc64-unknown-openbsd<br>

([Dockerfile](docker/openbsd.Dockerfile))

**Supported targets:**

| target | version | host |
| ------ | ------- | ---- |
| `aarch64-unknown-openbsd` (tier3) | 7.5 (default), 7.6 | Linux (any arch, any libc) |
| `i686-unknown-openbsd` (tier3) | 7.5 (default), 7.6 | Linux (any arch, any libc) |
| `powerpc-unknown-openbsd` (tier3) | 7.5 (default), 7.6 | Linux (any arch, any libc) |
| `powerpc64-unknown-openbsd` (tier3) | 7.5 (default), 7.6 | Linux (any arch, any libc) |
| `riscv64gc-unknown-openbsd` (tier3) | 7.5 (default), 7.6 | Linux (any arch, any libc) |
| `sparc64-unknown-openbsd` (tier3) | 7.5 (default), 7.6 | x86_64/aarch64 Linux (any libc) |
| `x86_64-unknown-openbsd` (tier3) | 7.5 (default), 7.6 | Linux (any arch, any libc) |

### DragonFly BSD

| libc | GCC | Clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| dragonfly 6.4.0 | N/A | host (requires 13+) | ✓ (libstdc++) |  | Linux (any arch, any libc) |

([Dockerfile](docker/dragonfly.Dockerfile))

**Supported targets:**

- `x86_64-unknown-dragonfly` (tier3)

### Solaris

| libc | GCC | Clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| solaris 2.10 | 8.5.0 |  | ✓ (libstdc++) |  | x86_64 Linux (any libc) |

([Dockerfile](docker/solaris.Dockerfile))

**Supported targets:**

- `sparcv9-sun-solaris`
- `x86_64-pc-solaris`

### illumos

| libc | GCC | Clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| solaris 2.10 | 8.5.0 | host | ✓ (libstdc++) |  | x86_64 Linux (any libc) |

([Dockerfile](docker/illumos.Dockerfile))

**Supported targets:**

- `x86_64-unknown-illumos`

### Redox

| libc | GCC | Clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| redox 0.8.0 | 13.2.0 | host | ✓ (libstdc++) |  | x86_64 Linux (glibc 2.35+) |

([Dockerfile](docker/redox.Dockerfile))

<!--
TODO: I guess libc from https://static.redox-os.org/toolchain is for the latest version of redox, but I'm not 100% sure it is correct.
https://gitlab.redox-os.org/redox-os/redox/-/releases
-->

**Supported targets:**

- `x86_64-unknown-redox`

### WASI

| libc | GCC | Clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| WASI SDK 25 (wasi-libc 574b88d) | N/A | 19.1.5 | ? (libc++) | ✓ (wasmtime) | x86_64/aarch64 Linux (glibc 2.28+) |

<!--
clang version and wasi-libc hash can be found here: https://github.com/WebAssembly/wasi-sdk/tree/wasi-sdk-25/src
-->

([Dockerfile](docker/wasi.Dockerfile))

**Supported targets:**

- `wasm32-wasip1`
- `wasm32-wasip1-threads`
- `wasm32-wasip2`

### Emscripten

| libc | GCC | Clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| emscripten 3.1.68 | N/A |  | ✓ (libc++) | ✓ (node) | x86_64/aarch64 Linux (glibc 2.27+) |

([Dockerfile](docker/emscripten.Dockerfile))

**Supported targets:**

- `wasm32-unknown-emscripten`

### Windows (MinGW)

| libc | GCC | Clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| Mingw-w64 8.0.0 | 10.3.0 | host | ✓ (libstdc++) | ✓ (wine) | x86_64/aarch64 Linux (glibc 2.35+) |

<!--
Mingw-w64 version: https://packages.ubuntu.com/en/jammy/mingw-w64-common
GCC version: https://packages.ubuntu.com/en/jammy/gcc-mingw-w64-base
-->

([Dockerfile](docker/windows-gnu.Dockerfile))

**Supported targets:**

- `x86_64-pc-windows-gnu`
- `i686-pc-windows-gnu`

### Windows (LLVM MinGW)

| libc | GCC | Clang | C++ | test | host |
| ---- | --- | ----- | --- | ---- | ---- |
| Mingw-w64 7c9cfe6 | N/A | 18.1.8 | ✓ (libc++) | ✓ (wine) | x86_64/aarch64 Linux (glibc 2.17+) |

<!--
Mingw-w64 version: https://github.com/mstorsjo/llvm-mingw/blob/20240619/build-mingw-w64.sh#L21
Clang version: https://github.com/mstorsjo/llvm-mingw/releases/tag/20240619
-->

([Dockerfile](docker/windows-gnullvm.Dockerfile))

**Supported targets:**

- `aarch64-pc-windows-gnullvm`
- `i686-pc-windows-gnullvm`
- `x86_64-pc-windows-gnullvm`

### No-std

| libc | GCC | Clang | C++ | run | host |
| ---- | --- | ----- | --- | ---- | ---- |
| newlib 4.1.0 | [1] |  | ✓ (libstdc++) | [1] | [1] |

[1] See target list below for details<br>

([Dockerfile](docker/none.Dockerfile))

**Supported targets:**

| target | GCC | run | host |
| ------ | --- | ---- | ---- |
| `aarch64-unknown-none` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 Linux (glibc 2.27+) |
| `aarch64-unknown-none-softfloat` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 Linux (glibc 2.27+) |
| `armebv7r-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 Linux (glibc 2.27+) |
| `armebv7r-none-eabihf` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 Linux (glibc 2.27+) |
| `armv5te-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 Linux (glibc 2.27+) |
| `armv7a-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 Linux (glibc 2.27+) |
| `armv7a-none-eabihf` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 Linux (glibc 2.27+) |
| `armv7r-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 Linux (glibc 2.27+) |
| `armv7r-none-eabihf` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 Linux (glibc 2.27+) |
| `riscv32i-unknown-none-elf` | 11.1.0 | ✓ (qemu) | x86_64 Linux (glibc 2.27+) |
| `riscv32im-unknown-none-elf` (tier3) | 11.1.0 | ✓ (qemu) | x86_64 Linux (glibc 2.27+) |
| `riscv32imac-unknown-none-elf` | 11.1.0 | ✓ (qemu) | x86_64 Linux (glibc 2.27+) |
| `riscv32imc-unknown-none-elf` | 11.1.0 | ✓ (qemu) | x86_64 Linux (glibc 2.27+) |
| `riscv64gc-unknown-none-elf` | 11.1.0 | ✓ (qemu) | x86_64 Linux (glibc 2.27+) |
| `riscv64imac-unknown-none-elf` | 11.1.0 | ✓ (qemu) | x86_64 Linux (glibc 2.27+) |
| `thumbv5te-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 Linux (glibc 2.27+) |
| `thumbv6m-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 Linux (glibc 2.27+) |
| `thumbv7em-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 Linux (glibc 2.27+) |
| `thumbv7em-none-eabihf` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 Linux (glibc 2.27+) |
| `thumbv7m-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 Linux (glibc 2.27+) |
| `thumbv8m.base-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 Linux (glibc 2.27+) |
| `thumbv8m.main-none-eabi` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 Linux (glibc 2.27+) |
| `thumbv8m.main-none-eabihf` | 10.3.1 | ✓ (qemu) | x86_64/aarch64 Linux (glibc 2.27+) |
