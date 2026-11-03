# SPDX-License-Identifier: Apache-2.0
include(FetchContent)

FetchContent_Declare(googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG        v1.14.0
    FIND_PACKAGE_ARGS NAMES GTest
)
FetchContent_MakeAvailable(googletest)

add_executable(unit_tests
    test_crc16.cpp
    test_ringbuf.cpp
    test_frame_parser.cpp
)

target_link_libraries(unit_tests PRIVATE firmware GTest::gtest_main)

apply_sanitizers(unit_tests)
apply_coverage(unit_tests)

include(GoogleTest)
gtest_discover_tests(unit_tests)
