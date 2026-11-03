# SPDX-License-Identifier: Apache-2.0
#
# Compiler warnings, all treated as errors. They need no extra tools and catch
# many common C defects.

function(apply_warnings target)
    set(flags
        -Wall
        -Wextra
        -Wpedantic
        -Wshadow
        -Wconversion
        -Wsign-conversion
        -Wcast-qual
        -Wcast-align
        -Wpointer-arith
        -Wstrict-prototypes
        -Wmissing-prototypes
        -Wredundant-decls
        -Wswitch-enum
        -Wundef
        -Wdouble-promotion
        -Wformat=2
        -Wwrite-strings
    )

    # Stack depth is a hard constraint on bare metal, but the two compilers
    # spell the check differently and clang rejects unknown -W options.
    if(CMAKE_C_COMPILER_ID STREQUAL "GNU")
        list(APPEND flags -Wstack-usage=512 -Wjump-misses-init -Wlogical-op)
    elseif(CMAKE_C_COMPILER_ID MATCHES "Clang")
        list(APPEND flags -Wframe-larger-than=512)
    endif()

    foreach(flag IN LISTS flags)
        target_compile_options(${target} PRIVATE $<$<COMPILE_LANGUAGE:C>:${flag}>)
    endforeach()

    if(ENABLE_WARNINGS_AS_ERRORS)
        target_compile_options(${target} PRIVATE $<$<COMPILE_LANGUAGE:C>:-Werror>)
    endif()
endfunction()
