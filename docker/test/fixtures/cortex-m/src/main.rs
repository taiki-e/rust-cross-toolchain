#![no_main]
#![no_std]
#![warn(rust_2018_idioms, unsafe_op_in_unsafe_fn)]

use core::fmt::Write;
use cortex_m::asm;
use cortex_m_rt::entry;
use cortex_m_semihosting as semihosting;

#[cfg(feature = "c")]
extern "C" {
    fn int_c() -> i32;
    #[cfg(feature = "cpp")]
    fn int_cpp() -> i32;
}

#[entry]
fn main() -> ! {
    loop {
        asm::nop();

        let mut hstdout = semihosting::hio::hstdout().unwrap();
        let _ = write!(hstdout, "Hello Rust!\n");
        #[cfg(feature = "c")]
        let _ = write!(hstdout, "x = {}\n", unsafe { int_c() });
        #[cfg(feature = "cpp")]
        let _ = write!(hstdout, "y = {}\n", unsafe { int_cpp() });

        semihosting::debug::exit(semihosting::debug::EXIT_SUCCESS);
    }
}

#[inline(never)]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo<'_>) -> ! {
    // atomic::compiler_fence is no longer needed: https://github.com/korken89/panic-halt/issues/3
    loop {}
}
