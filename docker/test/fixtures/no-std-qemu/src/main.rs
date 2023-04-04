#![no_main]
#![no_std]
#![warn(rust_2018_idioms, unsafe_op_in_unsafe_fn)]

use semihosting::println;

#[cfg(feature = "c")]
extern "C" {
    fn int_c() -> i32;
    #[cfg(feature = "cpp")]
    fn int_cpp() -> i32;
}

#[cfg(all(target_arch = "aarch64", feature = "qemu-system"))]
#[no_mangle]
#[link_section = ".text._start_arguments"]
pub static BOOT_CORE_ID: u64 = 0;
#[cfg(all(target_arch = "aarch64", feature = "qemu-system"))]
core::arch::global_asm!(include_str!("../raspi/boot.s"));

#[cfg(all(target_arch = "arm", target_feature = "mclass"))]
#[cortex_m_rt::entry]
fn main() -> ! {
    run();
    semihosting::process::exit(0)
}
#[cfg(feature = "qemu-system")]
#[cfg(any(target_arch = "aarch64"))]
#[no_mangle]
pub unsafe fn _start_rust() -> ! {
    #[cfg(feature = "panic-unwind")]
    init_global_allocator();
    run();
    semihosting::process::exit(0)
}
#[cfg(not(all(target_arch = "aarch64", feature = "qemu-system")))]
#[cfg(not(all(target_arch = "arm", target_feature = "mclass")))]
#[no_mangle]
unsafe fn _start(_: usize, _: usize) -> ! {
    #[cfg(all(
        any(target_arch = "riscv32", target_arch = "riscv64"),
        feature = "qemu-system",
    ))]
    unsafe {
        core::arch::asm!("la sp, _stack");
    }
    #[cfg(all(
        target_arch = "arm",
        not(target_feature = "v6"),
        target_feature = "v5te",
        feature = "qemu-system",
    ))]
    unsafe {
        #[instruction_set(arm::a32)]
        #[inline]
        unsafe fn init() {
            unsafe {
                core::arch::asm!("mov sp, #0x8000");
            }
        }
        init();
    }
    run();
    semihosting::process::exit(0)
}

fn run() {
    println!("Hello Rust!");
    #[cfg(feature = "c")]
    println!("x = {}", unsafe { int_c() });
    #[cfg(feature = "cpp")]
    println!("y = {}", unsafe { int_cpp() });
}
