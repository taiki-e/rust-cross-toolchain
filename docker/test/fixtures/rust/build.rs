use std::env;

fn main() {
    let target = &*env::var("TARGET").expect("TARGET not set");
    let target_os = &*env::var("CARGO_CFG_TARGET_OS").expect("CARGO_CFG_TARGET_OS not set");
    let target_env = &*env::var("CARGO_CFG_TARGET_ENV").expect("CARGO_CFG_TARGET_ENV not set");

    cc::Build::new().file("hello_c.c").compile("hello_c");
    if target_os == "openbsd" || target_os == "windows" && target_env == "gnu" {
    } else {
        // Make sure that the link with libc works.
        println!("cargo:rustc-link-lib=c");
    }

    if cfg!(feature = "cpp") {
        cc::Build::new()
            .cpp(true)
            .file("hello_cpp.cpp")
            .compile("libhello_cpp.a");
    } else {
        println!(
            "cargo:warning={}: C++ from Rust for '{target}' is currently disabled",
            env!("CARGO_PKG_NAME"),
        );
    }

    let cmake_dst = cmake::build("libhello_cmake");
    println!("cargo:rustc-link-search=native={}", cmake_dst.display());
    println!("cargo:rustc-link-lib=static=hello_cmake");
}
