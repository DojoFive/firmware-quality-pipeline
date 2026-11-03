# SPDX-License-Identifier: Apache-2.0
if(NOT CMAKE_C_COMPILER_ID MATCHES "Clang")
    message(FATAL_ERROR "ENABLE_FUZZING requires clang (libFuzzer is not in gcc)")
endif()

set(fuzz_flags
    -fsanitize=fuzzer,address,undefined
    -fno-sanitize-recover=all
    -fno-omit-frame-pointer
    -g
)

# The firmware sources are compiled into the fuzz target directly rather than
# linked from the plain static library. libFuzzer needs coverage
# instrumentation inside the code under test to guide mutation, and ASan only
# checks loads and stores it has instrumented. With an uninstrumented library
# the fuzzer still runs, but it cannot find anything.
add_executable(fuzz_frame_parser fuzz_frame_parser.c ${FIRMWARE_SOURCES})

target_include_directories(fuzz_frame_parser PRIVATE ${CMAKE_SOURCE_DIR}/include)
target_compile_definitions(fuzz_frame_parser PRIVATE DEMO_BUG=${DEMO_BUG})
target_compile_options(fuzz_frame_parser PRIVATE ${fuzz_flags})
target_link_options(fuzz_frame_parser PRIVATE ${fuzz_flags})
