// SPDX-License-Identifier: Apache-2.0 OR MIT

// Adapted from https://github.com/rust-lang/rust/blob/1.70.0/src/bootstrap/llvm.rs#L1140-L1295
// TODO: update to https://github.com/rust-lang/rust/blob/1.80.0/src/bootstrap/src/core/build_steps/llvm.rs#L1258-L1413

use std::{env, ffi::OsStr, path::PathBuf, process::Command};

use anyhow::Result;
use fs_err as fs;

fn usage() -> String {
    println!("USAGE: build-libunwind --target=<TARGET> --out=<OUT_DIR> [--host=<HOST>] [--sysroot=<SYSROOT>]");
    std::process::exit(1);
}

fn main() -> Result<()> {
    let args: Vec<_> = env::args().skip(1).collect();
    let mut host = None;
    let mut target = None;
    let mut out_dir = None;
    let mut sysroot = None;
    for arg in args {
        if let Some(v) = arg.strip_prefix("--host=") {
            host = Some(v.to_owned());
        } else if let Some(v) = arg.strip_prefix("--target=") {
            target = Some(v.to_owned());
        } else if let Some(v) = arg.strip_prefix("--out=") {
            out_dir = Some(v.to_owned());
        } else if let Some(v) = arg.strip_prefix("--sysroot=") {
            sysroot = Some(v.to_owned());
        } else {
            eprintln!("error: unknown argument '{arg}'");
            usage();
        }
    }
    let target = &target.unwrap_or_else(usage);
    let target_lower = &target.replace(['-', '.'], "_");
    let out_dir = &out_dir.unwrap_or_else(usage);
    let rustc = "rustc";
    let host = &match host {
        Some(host) => host,
        None => {
            let output = Command::new(rustc).arg("-vV").output()?;
            assert!(output.status.success());
            String::from_utf8(output.stdout)?
                .lines()
                .find_map(|line| line.strip_prefix("host: "))
                .unwrap()
                .to_owned()
        }
    };
    let sysroot = &match sysroot {
        Some(sysroot) => PathBuf::from(sysroot),
        None => {
            let output = Command::new(rustc).arg("--print").arg("sysroot").output()?;
            assert!(output.status.success());
            String::from_utf8(output.stdout)?.trim_end().into()
        }
    };
    let root = &sysroot.join("lib/rustlib/src/rust/src/llvm-project/libunwind");

    let target_cc = env::var_os(format!("CC_{target_lower}")).unwrap();
    let target_cxx = env::var_os(format!("CXX_{target_lower}"));
    let target_ar = env::var_os(format!("AR_{target_lower}"));
    fs::create_dir_all(out_dir)?;

    let mut cc_cfg = cc::Build::new();
    let mut cpp_cfg = cc::Build::new();

    cpp_cfg.cpp(true);
    cpp_cfg.cpp_set_stdlib(None);
    cpp_cfg.flag("-nostdinc++");
    cpp_cfg.flag("-fno-exceptions");
    cpp_cfg.flag("-fno-rtti");
    cpp_cfg.flag_if_supported("-fvisibility-global-new-delete-hidden");

    for cfg in &mut [&mut cc_cfg, &mut cpp_cfg] {
        if let Some(ar) = &target_ar {
            cfg.archiver(ar);
        }
        cfg.target(target);
        cfg.host(host);
        cfg.warnings(false);
        cfg.debug(false);
        // get_compiler() need set opt_level first.
        cfg.opt_level(3);
        cfg.flag("-fstrict-aliasing");
        cfg.flag("-funwind-tables");
        cfg.flag("-fvisibility=hidden");
        cfg.define("_LIBUNWIND_DISABLE_VISIBILITY_ANNOTATIONS", None);
        cfg.include(root.join("include"));
        cfg.cargo_metadata(false);
        cfg.out_dir(out_dir);

        if target.contains("x86_64-fortanix-unknown-sgx") {
            cfg.static_flag(true);
            cfg.flag("-fno-stack-protector");
            cfg.flag("-ffreestanding");
            cfg.flag("-fexceptions");

            // easiest way to undefine since no API available in cc::Build to undefine
            cfg.flag("-U_FORTIFY_SOURCE");
            cfg.define("_FORTIFY_SOURCE", "0");
            cfg.define("RUST_SGX", "1");
            cfg.define("__NO_STRING_INLINES", None);
            cfg.define("__NO_MATH_INLINES", None);
            cfg.define("_LIBUNWIND_IS_BAREMETAL", None);
            cfg.define("__LIBUNWIND_IS_NATIVE_ONLY", None);
            cfg.define("NDEBUG", None);
        }
        if target.contains("windows") {
            cfg.define("_LIBUNWIND_HIDE_SYMBOLS", "1");
            cfg.define("_LIBUNWIND_IS_NATIVE_ONLY", "1");
        }
    }

    cc_cfg.compiler(&target_cc);
    if let Some(cxx) = &target_cxx {
        cpp_cfg.compiler(cxx);
    }

    // Don't set this for clang
    // By default, Clang builds C code in GNU C17 mode.
    // By default, Clang builds C++ code according to the C++98 standard,
    // with many C++11 features accepted as extensions.
    if cc_cfg.get_compiler().is_like_gnu() {
        cc_cfg.flag("-std=c99");
    }
    if cpp_cfg.get_compiler().is_like_gnu() {
        cpp_cfg.flag("-std=c++11");
    }

    if target.contains("x86_64-fortanix-unknown-sgx") || target.contains("musl") {
        // use the same GCC C compiler command to compile C++ code so we do not need to setup the
        // C++ compiler env variables on the builders.
        // Don't set this for clang++, as clang++ is able to compile this without libc++.
        if cpp_cfg.get_compiler().is_like_gnu() {
            cpp_cfg.cpp(false);
            cpp_cfg.compiler(&target_cc);
        }
    }

    let mut c_sources = vec![
        "Unwind-sjlj.c",
        "UnwindLevel1-gcc-ext.c",
        "UnwindLevel1.c",
        "UnwindRegistersRestore.S",
        "UnwindRegistersSave.S",
    ];

    let cpp_sources = vec!["Unwind-EHABI.cpp", "Unwind-seh.cpp", "libunwind.cpp"];
    let cpp_len = cpp_sources.len();

    if target.contains("x86_64-fortanix-unknown-sgx") {
        c_sources.push("UnwindRustSgx.c");
    }

    for src in c_sources {
        cc_cfg.file(fs::canonicalize(root.join("src").join(src))?);
    }

    for src in &cpp_sources {
        cpp_cfg.file(fs::canonicalize(root.join("src").join(src))?);
    }

    cpp_cfg.compile("unwind-cpp");

    // FIXME: https://github.com/rust-lang/cc-rs/issues/545#issuecomment-679242845
    let mut count = 0;
    for entry in fs::read_dir(out_dir)? {
        let file = fs::canonicalize(entry?.path())?;
        if file.is_file() && file.extension() == Some(OsStr::new("o")) {
            // file name starts with "Unwind-EHABI", "Unwind-seh" or "libunwind"
            let file_name = file.file_name().unwrap().to_str().expect("UTF-8 file name");
            if cpp_sources.iter().any(|f| file_name.starts_with(&f[..f.len() - 4])) {
                cc_cfg.object(&file);
                count += 1;
            }
        }
    }
    assert_eq!(cpp_len, count, "Can't get object files from {out_dir:?}");

    cc_cfg.compile("unwind");

    Ok(())
}
