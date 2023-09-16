// SPDX-License-Identifier: Apache-2.0 OR MIT

#include <iostream>

extern "C" void hello_cpp() {
    std::cout << "Hello C++ from Rust!" << std::endl;
}
