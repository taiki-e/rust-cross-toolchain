#!/bin/bash
set -euxo pipefail
IFS=$'\n\t'

# Set up tools to test the toolchain. (target-dependent)

dpkg_arch="$(dpkg --print-architecture)"
case "${dpkg_arch##*-}" in
    amd64) ;;
    *)
        # TODO: don't skip if actual host is arm64
        echo >&2 "info: testing on hosts other than amd64 is currently being skipped: '${dpkg_arch}'"
        exit 0
        ;;
esac

export CARGO_NET_RETRY=10
export RUSTUP_MAX_RETRIES=10
# shellcheck disable=SC1091
. "${HOME}/.cargo/env"

if rustup target list | grep -E "^${RUST_TARGET}( |$)" >/dev/null; then
    rustup target add "${RUST_TARGET}"
else
    touch /BUILD_STD
fi

case "${RUST_TARGET}" in
    hexagon-unknown-linux-musl)
        pushd "${HOME}"/.cargo/registry/src/github.com-*/libc-0.2.108 >/dev/null
        # "error[E0425]: cannot find value `SYS_clone3` in this scope" when building std
        # TODO: send patch to upstream
        patch -p1 <<'EOF'
diff --git a/src/unix/linux_like/linux/musl/b32/hexagon.rs b/src/unix/linux_like/linux/musl/b32/hexagon.rs
index fbb7720e5..1377ae5e5 100644
--- a/src/unix/linux_like/linux/musl/b32/hexagon.rs
+++ b/src/unix/linux_like/linux/musl/b32/hexagon.rs
@@ -655,6 +655,7 @@ pub struct statvfs64 {
 pub const SYS_write: ::c_int = 64;
 pub const SYS_writev: ::c_int = 66;
 pub const SYS_statx: ::c_int = 291;
+pub const SYS_clone3: ::c_long = 435;
 pub const TCFLSH: ::c_int = 21515;
 pub const TCGETA: ::c_int = 21509;
 pub const TCGETS: ::c_int = 21505;
EOF
        popd >/dev/null
        ;;
    riscv64gc-unknown-linux-musl)
        pushd "${HOME}"/.cargo/registry/src/github.com-*/libc-0.2.108 >/dev/null
        # "error[E0425]: cannot find value `SYS_clone3` in this scope" when building std
        # TODO: send patch to upstream
        patch -p1 <<'EOF'
diff --git a/src/unix/linux_like/linux/musl/b64/riscv64/mod.rs b/src/unix/linux_like/linux/musl/b64/riscv64/mod.rs
index 48fee4e63..3272e5df7 100644
--- a/src/unix/linux_like/linux/musl/b64/riscv64/mod.rs
+++ b/src/unix/linux_like/linux/musl/b64/riscv64/mod.rs
@@ -465,6 +465,7 @@ pub struct flock64 {
 pub const SYS_pkey_alloc: ::c_long = 289;
 pub const SYS_pkey_free: ::c_long = 290;
 pub const SYS_statx: ::c_long = 291;
+pub const SYS_clone3: ::c_long = 435;

 pub const O_APPEND: ::c_int = 1024;
 pub const O_DIRECT: ::c_int = 0x4000;
EOF
        popd >/dev/null
        ;;
esac
