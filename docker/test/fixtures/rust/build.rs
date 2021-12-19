use std::env;

fn main() {
    let target = &*env::var("TARGET").unwrap();

    cc::Build::new().file("hello_c.c").compile("hello_c");
    if !target.contains("-windows-gnu") && !target.contains("-openbsd") {
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
            "cargo:warning={}: C++ from Rust for '{}' is currently disabled",
            env!("CARGO_PKG_NAME"),
            target
        );
    }

    let cmake_dst = cmake::build("libhello_cmake");
    println!("cargo:rustc-link-search=native={}", cmake_dst.display());
    println!("cargo:rustc-link-lib=static=hello_cmake");
}
