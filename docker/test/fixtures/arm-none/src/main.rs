#![no_main]
#![no_std]
#![feature(asm)]
#![warn(rust_2018_idioms, unsafe_op_in_unsafe_fn)]
#![allow(non_upper_case_globals)]

use core::panic::PanicInfo;

#[cfg(feature = "c")]
extern "C" {
    fn int_c() -> i32;
    #[cfg(feature = "cpp")]
    fn int_cpp() -> i32;
}

#[no_mangle]
unsafe fn _start() -> ! {
    #[cfg(feature = "c")]
    let _ = unsafe { int_c() };
    #[cfg(feature = "cpp")]
    let _ = unsafe { int_cpp() };

    exit();
}

// https://developer.arm.com/documentation/100863/latest
const angel_SWIreason_ReportException: usize = 0x18;
const ADP_Stopped_ApplicationExit: usize = 0x20026;

fn exit() -> ! {
    unsafe {
        // https://stackoverflow.com/a/40957928
        #[cfg(target_arch = "arm")]
        #[cfg(not(thumb))]
        {
            asm!(
                "svc 0x00123456",
                in("r0") angel_SWIreason_ReportException,
                in("r1") ADP_Stopped_ApplicationExit,
                options(nostack)
            );
        }
        // https://stackoverflow.com/a/62100259
        #[cfg(target_arch = "arm")]
        #[cfg(thumb)]
        {
            asm!(
                "bkpt 0xAB",
                in("r0") angel_SWIreason_ReportException,
                in("r1") ADP_Stopped_ApplicationExit,
                options(nostack)
            );
        }
        // https://stackoverflow.com/a/49930361
        #[cfg(target_arch = "aarch64")]
        {
            asm!(
                "hlt 0xF000",
                in("w0") angel_SWIreason_ReportException,
                in("x1") &[ADP_Stopped_ApplicationExit, 0] as *const _ as usize,
                options(nostack)
            );
        }
        loop {}
    }
}

#[inline(never)]
#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
    // atomic::compiler_fence is no longer needed: https://github.com/korken89/panic-halt/issues/3
    loop {}
}
