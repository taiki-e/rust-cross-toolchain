use std::{fs, path::Path};

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=int_c.c");
    println!("cargo:rerun-if-changed=int_cpp.cpp");

    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    for e in fs::read_dir(manifest_dir).unwrap() {
        let path = e.unwrap().path();
        if path.extension().map_or(false, |e| e == "ld" || e == "x") {
            let path = path.strip_prefix(manifest_dir).unwrap();
            println!("cargo:rerun-if-changed={}", path.to_str().unwrap());
        }
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
}
