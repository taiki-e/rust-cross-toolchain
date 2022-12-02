#![no_main]
#![no_std]
#![warn(rust_2018_idioms, unsafe_op_in_unsafe_fn)]

use riscv_rt::entry;

#[cfg(feature = "c")]
extern "C" {
    fn int_c() -> i32;
    #[cfg(feature = "cpp")]
    fn int_cpp() -> i32;
}

#[entry]
fn main() -> ! {
    loop {
        #[cfg(feature = "c")]
        let _ = unsafe { int_c() };
        #[cfg(feature = "cpp")]
        let _ = unsafe { int_cpp() };
    }
}

#[inline(never)]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo<'_>) -> ! {
    // atomic::compiler_fence is no longer needed: https://github.com/korken89/panic-halt/issues/3
    loop {}
}
