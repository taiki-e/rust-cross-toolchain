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

    println!("cargo:rerun-if-changed=hello_c.c");
    println!("cargo:rerun-if-changed=hello_cpp.cpp");
    println!("cargo:rerun-if-changed=build.rs");
}
