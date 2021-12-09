// Source: https://github.com/alexcrichton/rust-ffi-examples/tree/1a49f1c01dc696fd728b63e66e5ae84017ddd871/rust-to-cmake

extern "C" {
    fn double_input(input: std::os::raw::c_int) -> std::os::raw::c_int;
}

fn main() {
    let input = 4;
    let output = unsafe { double_input(input) };
    println!("Hello Cmake from Rust!");
    println!("{} * 2 = {}", input, output);
}
