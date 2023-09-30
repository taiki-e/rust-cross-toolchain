// SPDX-License-Identifier: Apache-2.0 OR MIT

#![warn(rust_2018_idioms)]

use std::env;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=hello_c.c");
    println!("cargo:rerun-if-changed=hello_cpp.cpp");
    println!("cargo:rerun-if-changed=libhello_cmake");

    let target = &*env::var("TARGET").expect("TARGET not set");
    let target_arch = &*env::var("CARGO_CFG_TARGET_ARCH").expect("CARGO_CFG_TARGET_ARCH not set");
    let target_os = &*env::var("CARGO_CFG_TARGET_OS").expect("CARGO_CFG_TARGET_OS not set");
    let target_env = &*env::var("CARGO_CFG_TARGET_ENV").expect("CARGO_CFG_TARGET_ENV not set");

    // TODO(hexagon):
    // TODO(loongarch64):
    if target_arch == "hexagon" || target_arch == "loongarch64" {
        println!("cargo:rustc-cfg=no_c");
        return;
    }

    cc::Build::new().file("hello_c.c").compile("hello_c");
    if target_os == "openbsd" || target_os == "windows" {
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

    // TODO(windows-msvc):
    if target_os == "windows" && target_env == "msvc" {
        println!("cargo:rustc-cfg=no_cmake");
        return;
    }
    let cmake_dst = cmake::build("libhello_cmake");
    println!("cargo:rustc-link-search=native={}", cmake_dst.display());
    println!("cargo:rustc-link-lib=static=hello_cmake");
}
