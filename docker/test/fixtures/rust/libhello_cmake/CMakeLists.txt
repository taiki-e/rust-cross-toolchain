add_library (
    hello_cmake
    STATIC
    hello_cmake.c
)

install (TARGETS hello_cmake DESTINATION .)
