extern "C" {
    fn hello_c();
    #[cfg(not(no_cpp))]
    fn hello_cpp();
}

fn main() {
    println!("Hello Rust!");
    unsafe {
        hello_c();
        #[cfg(not(no_cpp))]
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
            #[cfg(not(no_cpp))]
            hello_cpp();
        }
    }
}
