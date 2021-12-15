fn main() {
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
