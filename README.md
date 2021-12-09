# rust-cross-toolchain

- [Platform Support](#platform-support)
  - [Linux (GNU)](#linux-gnu)
  - [Linux (musl)](#linux-musl)
  - [Linux (uClibc)](#linux-uclibc)
  - [FreeBSD](#freebsd)
  - [NetBSD](#netbsd)
  - [OpenBSD](#openbsd)
  - [DragonFly BSD](#dragonfly-bsd)
  - [Solaris](#solaris)
  - [illumos](#illumos)
  - [Redox](#redox)
  - [WASI](#wasi)
  - [Windows (GNU)](#windows-gnu)

## Platform Support

### Linux (GNU)

| libc | GCC | clang | C++ | test |
| ---- | --- | ----- | --- | ---- |
| glibc [1] | [1] | host | ✓ (libstdc++) | ✓ (qemu-user) [2] |

[1] See target list below for details<br>
[2] Except for powerpc-unknown-linux-gnuspe, riscv32gc-unknown-linux-gnu, and x86_64-unknown-linux-gnux32<br>

([Dockerfile](docker/linux-gnu.Dockerfile))

**Supported targets**:

| Target | glibc | GCC |
| ------ | ----- | --- |
| `aarch64-unknown-linux-gnu` | 2.27 | 7.4.0 |
| `aarch64_be-unknown-linux-gnu` (tier3) | 2.31 | 10.2.1 |
| `arm-unknown-linux-gnueabi` | 2.27 | 7.4.0 |
| `arm-unknown-linux-gnueabihf` | 2.24 | 9.4.0 |
| `armv5te-unknown-linux-gnueabi` | 2.27 | 7.4.0 |
| `armv7-unknown-linux-gnueabi` | 2.27 | 7.4.0 |
| `armv7-unknown-linux-gnueabihf` | 2.27 | 7.4.0 |
| `i586-unknown-linux-gnu` | 2.27 | 7.4.0 |
| `i686-unknown-linux-gnu` | 2.27 | 7.4.0 |
| `mips-unknown-linux-gnu` | 2.27 | 7.4.0 |
| `mips64-unknown-linux-gnuabi64` | 2.27 | 7.4.0 |
| `mips64el-unknown-linux-gnuabi64` | 2.27 | 7.4.0 |
| `mipsel-unknown-linux-gnu` | 2.27 | 7.4.0 |
| `mipsisa32r6-unknown-linux-gnu` (tier3) | 2.31 | 9.3.0 |
| `mipsisa32r6el-unknown-linux-gnu` (tier3) | 2.31 | 9.3.0 |
| `mipsisa64r6-unknown-linux-gnuabi64` (tier3) | 2.31 | 9.3.0 |
| `mipsisa64r6el-unknown-linux-gnuabi64` (tier3) | 2.31 | 9.3.0 |
| `powerpc-unknown-linux-gnu` | 2.27 | 7.4.0 |
| `powerpc-unknown-linux-gnuspe` (tier3) | 2.27 | 7.4.0 |
| `powerpc64-unknown-linux-gnu` | 2.27 | 7.4.0 |
| `powerpc64le-unknown-linux-gnu` | 2.27 | 7.4.0 |
| `riscv32gc-unknown-linux-gnu` (tier3) | 2.33 | 11.1.0 |
| `riscv64gc-unknown-linux-gnu` | 2.27 | 7.4.0 |
| `s390x-unknown-linux-gnu` | 2.27 | 7.4.0 |
| `sparc64-unknown-linux-gnu` | 2.27 | 7.4.0 |
| `thumbv7neon-unknown-linux-gnueabihf` | 2.27 | 7.4.0 |
| `x86_64-unknown-linux-gnux32` | 2.27 | 7.4.0 |

### Linux (musl)

| libc | GCC | clang | C++ | test |
| ---- | --- | ----- | --- | ---- |
| musl 1.2.2 / 1.1.24 (32-bit) [1] | 9.4.0 | host | ✓ (libstdc++) | ✓ (qemu-user) |

[1] For 32-bit targets, we use musl 1.1 (with a patch that fixes CVE-2020-28928) for [compatibility with upstream][libc#1848]<br>

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

| libc | GCC | clang | C++ | test |
| ---- | --- | ----- | --- | ---- |
| uClibc-ng 1.0.34 | 10.2.0 | host | ✓ (libstdc++) | ✓ (qemu-user) |

([Dockerfile](docker/linux-uclibc.Dockerfile))

**Supported targets**:

- `armv5te-unknown-linux-uclibceabi` (tier3)
- `armv7-unknown-linux-uclibceabihf` (tier3)
- `mips-unknown-linux-uclibc` (tier3)
- `mipsel-unknown-linux-uclibc` (tier3)

### FreeBSD

| libc | GCC | clang | C++ | test |
| ---- | --- | ----- | --- | ---- |
| freebsd 12.2 [1] / 13.0 [2] | N/A | host | ✓ (libc++) |  |

[1] default, only aarch64, i686, and x86_64<br>
[2] default of powerpc, powerpc64, and powerpc64le<br>

([Dockerfile](docker/freebsd.Dockerfile))

**Supported targets**:

- `aarch64-unknown-freebsd` (tier3)
- `i686-unknown-freebsd`
- `powerpc-unknown-freebsd` (tier3)
- `powerpc64-unknown-freebsd` (tier3)
- `powerpc64le-unknown-freebsd` (tier3)
- `x86_64-unknown-freebsd`

### NetBSD

| libc | GCC | clang | C++ | test |
| ---- | --- | ----- | --- | ---- |
| netbsd 9.2 | N/A | host | ✓ (libstdc++) |  |

([Dockerfile](docker/netbsd.Dockerfile))

**Supported targets**:

- `aarch64-unknown-netbsd` (tier3)
- `i686-unknown-netbsd` (tier3)
- `x86_64-unknown-netbsd` (tier3)

### OpenBSD

| libc | GCC | clang | C++ | test |
| ---- | --- | ----- | --- | ---- |
| openbsd 7.0 | N/A | host | ✓ (libc++) [1] |  |

[1] only i686 and x86_64<br>

([Dockerfile](docker/openbsd.Dockerfile))

**Supported targets**:

- `aarch64-unknown-openbsd` (tier3)
- `i686-unknown-openbsd` (tier3)
- `x86_64-unknown-openbsd` (tier3)

### DragonFly BSD

| libc | GCC | clang | C++ | test |
| ---- | --- | ----- | --- | ---- |
| dragonfly 6.0 | N/A | host (requires 13+) | ✓ (libstdc++) |  |

([Dockerfile](docker/dragonfly.Dockerfile))

**Supported targets**:

- `x86_64-unknown-dragonfly` (tier3)

### Solaris

| libc | GCC | clang | C++ | test |
| ---- | --- | ----- | --- | ---- |
| solaris 2.11 | 8.5.0 |  | ✓ (libstdc++) |  |

([Dockerfile](docker/solaris.Dockerfile))

**Supported targets**:

- `sparcv9-sun-solaris`
- `x86_64-pc-solaris`
- `x86_64-sun-solaris`

### illumos

| libc | GCC | clang | C++ | test |
| ---- | --- | ----- | --- | ---- |
| solaris 2.10 | 8.5.0 | host | ✓ (libstdc++) |  |

([Dockerfile](docker/illumos.Dockerfile))

**Supported targets**:

- `x86_64-unknown-illumos`

### Redox

| libc | GCC | clang | C++ | test |
| ---- | --- | ----- | --- | ---- |
| redox 0.6.0 | 8.2.0 | host | ✓ (libstdc++) |  |

([Dockerfile](docker/redox.Dockerfile))

<!--
TODO: I guess libc from https://static.redox-os.org/toolchain is for the latest version of redox, but I'm not 100% sure it is correct.
https://gitlab.redox-os.org/redox-os/redox/-/releases
-->

**Supported targets**:

- `x86_64-unknown-redox`

### WASI

| libc | GCC | clang | C++ | test |
| ---- | --- | ----- | --- | ---- |
| wasi-sdk 14 (wasi-libc ad51334) | N/A | 13.0.0 | ? (libc++) | ✓ (wasmtime) |

<!--
wasi-libc hash can be found here: https://github.com/WebAssembly/wasi-sdk/tree/wasi-sdk-14/src
-->

([Dockerfile](docker/wasi.Dockerfile))

**Supported targets**:

- `wasm32-wasi`

### Windows (GNU)

| libc | GCC | clang | C++ | test |
| ---- | --- | ----- | --- | ---- |
| Mingw-w64 5.0.3 | 7.3.0 | host | ✓ (libstdc++) |  |

<!--
Mingw-w64 version: https://packages.ubuntu.com/en/bionic/mingw-w64-common
GCC version: https://packages.ubuntu.com/en/bionic/gcc-mingw-w64-base
-->

([Dockerfile](docker/windows-gnu.Dockerfile))

**Supported targets**:

- `x86_64-pc-windows-gnu`
- `i686-pc-windows-gnu`
