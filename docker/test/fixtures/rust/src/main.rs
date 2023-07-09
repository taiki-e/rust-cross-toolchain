#![warn(rust_2018_idioms, unsafe_op_in_unsafe_fn)]

#[cfg(not(no_c))]
extern "C" {
    fn hello_c();
    #[cfg(feature = "cpp")]
    fn hello_cpp();
    fn hello_cmake(input: std::os::raw::c_int) -> std::os::raw::c_int;
}

fn main() {
    println!("Hello Rust!");
    #[cfg(not(no_c))]
    unsafe {
        hello_c();
        #[cfg(feature = "cpp")]
        hello_cpp();

        let input = 4;
        let output = hello_cmake(input);
        assert_eq!(output, 8);
        println!("Hello Cmake from Rust!");
        println!("{input} * 2 = {output}");
    }
}

#[cfg(test)]
mod tests {
    #[cfg(not(no_c))]
    use super::*;

    #[test]
    fn test() {
        println!("Hello Rust!");
        #[cfg(not(no_c))]
        unsafe {
            hello_c();
            #[cfg(feature = "cpp")]
            hello_cpp();
        }
    }
}
