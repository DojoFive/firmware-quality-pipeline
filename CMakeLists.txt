# SPDX-License-Identifier: Apache-2.0
cmake_minimum_required(VERSION 3.24)
project(firmware_quality_pipeline VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(ENABLE_WARNINGS_AS_ERRORS "Fail the build on any compiler warning"      ON)
option(ENABLE_SANITIZERS         "Build host tests with ASan and UBSan"        OFF)
option(ENABLE_COVERAGE           "Build host tests with coverage instrumentation" OFF)
option(ENABLE_CLANG_TIDY         "Run clang-tidy as part of the build"         OFF)
option(ENABLE_GCC_ANALYZER       "Enable gcc -fanalyzer during the build"      OFF)
option(ENABLE_FUZZING            "Build the libFuzzer targets (clang only)"    OFF)
option(BUILD_TESTING             "Build the host unit tests"                   ON)

# Seeded defect selector. 0 is the clean build. See README for the catalog.
# Defect 5 is a vulnerable dependency in the SBOM and changes nothing in the build.
set(DEMO_BUG "0" CACHE STRING "Seeded defect to compile in (0 = none, 1-5)")
set_property(CACHE DEMO_BUG PROPERTY STRINGS 0 1 2 3 4 5)

include(cmake/Warnings.cmake)
include(cmake/Sanitizers.cmake)
include(cmake/Coverage.cmake)
include(cmake/StaticAnalysis.cmake)

set(FIRMWARE_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/src/crc16.c
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ringbuf.c
    ${CMAKE_CURRENT_SOURCE_DIR}/src/frame_parser.c
)

add_library(firmware STATIC ${FIRMWARE_SOURCES})
target_include_directories(firmware PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_compile_definitions(firmware PUBLIC DEMO_BUG=${DEMO_BUG})

apply_warnings(firmware)
apply_sanitizers(firmware)
apply_coverage(firmware)
apply_gcc_analyzer(firmware)
apply_clang_tidy(firmware)

if(BUILD_TESTING)
    enable_testing()
    add_subdirectory(tests)
endif()

if(ENABLE_FUZZING)
    add_subdirectory(fuzz)
endif()

message(STATUS "")
message(STATUS "  firmware-quality-pipeline")
message(STATUS "  seeded defect ......... DEMO_BUG=${DEMO_BUG}")
message(STATUS "  warnings as errors .... ${ENABLE_WARNINGS_AS_ERRORS}")
message(STATUS "  sanitizers ............ ${ENABLE_SANITIZERS}")
message(STATUS "  coverage .............. ${ENABLE_COVERAGE}")
message(STATUS "  clang-tidy ............ ${ENABLE_CLANG_TIDY}")
message(STATUS "  gcc -fanalyzer ........ ${ENABLE_GCC_ANALYZER}")
message(STATUS "  fuzzing ............... ${ENABLE_FUZZING}")
message(STATUS "")
