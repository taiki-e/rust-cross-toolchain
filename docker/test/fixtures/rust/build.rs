use std::env;

fn main() {
    let target = &*env::var("TARGET").unwrap();

    cc::Build::new().file("hello_c.c").compile("hello_c");

    let mut cpp = true;
    if matches!(target, "aarch64-unknown-openbsd" | "wasm32-wasi") {
        /*
        TODO(aarch64-unknown-openbsd): clang segfault
        TODO(wasm32-wasi):
            Error: failed to run main module `/tmp/test-clang/rust/target/wasm32-wasi/debug/rust-test.wasm`
            Caused by:
                0: failed to instantiate "/tmp/test-clang/rust/target/wasm32-wasi/debug/rust-test.wasm"
                1: unknown import: `env::_ZnwmSt11align_val_t` has not been defined
        */
        cpp = false;
    }
    if cpp {
        cc::Build::new()
            .cpp(true)
            .file("hello_cpp.cpp")
            .compile("libhello_cpp.a");
    } else {
        println!(
            "cargo:warning={}: C++ from Rust for '{}' is currently disabled",
            env!("CARGO_PKG_NAME"),
            target
        );
        println!("cargo:rustc-cfg=no_cpp");
    }

    println!("cargo:rerun-if-changed=hello_c.c");
    println!("cargo:rerun-if-changed=hello_cpp.cpp");
    println!("cargo:rerun-if-changed=build.rs");
}
