use std::env;

fn main() {
    let target = match env::var("TARGET") {
        Ok(target) => target,
        Err(e) => {
            println!(
                "cargo:warning={}: unable to get TARGET environment variable: {}",
                env!("CARGO_PKG_NAME"),
                e
            );
            return;
        }
    };
    // thumbv7neon means armv7a+neon
    if target.starts_with("thumb") && !target.contains("neon") {
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
