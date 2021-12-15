#![warn(rust_2018_idioms, unsafe_op_in_unsafe_fn)]

extern "C" {
    fn hello_c();
    #[cfg(feature = "cpp")]
    fn hello_cpp();
}

fn main() {
    println!("Hello Rust!");
    unsafe {
        hello_c();
        #[cfg(feature = "cpp")]
        hello_cpp();
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
