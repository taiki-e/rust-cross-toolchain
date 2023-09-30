// SPDX-License-Identifier: Apache-2.0 OR MIT

#![no_main]
#![no_std]
#![warn(rust_2018_idioms)]

use semihosting::println;

#[cfg(feature = "c")]
extern "C" {
    fn int_c() -> i32;
    #[cfg(feature = "cpp")]
    fn int_cpp() -> i32;
}

semihosting_no_std_test_rt::entry!(run);
fn run() {
    println!("Hello Rust!");
    #[cfg(feature = "c")]
    println!("x = {}", unsafe { int_c() });
    #[cfg(feature = "cpp")]
    println!("y = {}", unsafe { int_cpp() });
}
