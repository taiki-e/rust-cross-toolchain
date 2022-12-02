use std::env;

fn main() {
    let target = &*env::var("TARGET").expect("TARGET not set");

    // Note: `starts_with("thumb")` is not enough because arch such as thumbv7neon-, thumbv7a- means armv7a.
    if target.starts_with("thumbv6m")
        || target.starts_with("thumbv7em")
        || target.starts_with("thumbv7m")
        || target.starts_with("thumbv8m")
    {
        println!("cargo:rustc-cfg=thumb");
    }

    #[cfg(feature = "c")]
    {
        cc::Build::new().file("int_c.c").compile("int_c");
        // Make sure that the link with libc.a works.
        println!("cargo:rustc-link-lib=c");
    }
    #[cfg(feature = "cpp")]
    {
        cc::Build::new()
            .cpp(true)
            .file("int_cpp.cpp")
            .compile("libint_cpp.a");
    }
    println!("cargo:rerun-if-changed=int_c.c");
    println!("cargo:rerun-if-changed=int_cpp.cpp");
    println!("cargo:rerun-if-changed=build.rs");
}
