#![warn(rust_2018_idioms, unsafe_op_in_unsafe_fn)]

extern "C" {
    fn hello_c();
    #[cfg(feature = "cpp")]
    fn hello_cpp();
    fn hello_cmake(input: std::os::raw::c_int) -> std::os::raw::c_int;
}

fn main() {
    println!("Hello Rust!");
    unsafe {
        hello_c();
        #[cfg(feature = "cpp")]
        hello_cpp();

        let input = 4;
        let output = hello_cmake(input);
        assert_eq!(output, 8);
        println!("Hello Cmake from Rust!");
        println!("{} * 2 = {}", input, output);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test() {
        println!("Hello Rust!");
        unsafe {
            hello_c();
            #[cfg(feature = "cpp")]
            hello_cpp();
        }
    }
}
