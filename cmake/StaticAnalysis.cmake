# SPDX-License-Identifier: Apache-2.0

function(apply_clang_tidy target)
    if(NOT ENABLE_CLANG_TIDY)
        return()
    endif()

    find_program(CLANG_TIDY_EXE NAMES clang-tidy)
    if(NOT CLANG_TIDY_EXE)
        message(FATAL_ERROR "ENABLE_CLANG_TIDY is on but clang-tidy was not found")
    endif()

    set_target_properties(${target} PROPERTIES
        C_CLANG_TIDY "${CLANG_TIDY_EXE};--warnings-as-errors=*"
    )
endfunction()

function(apply_gcc_analyzer target)
    if(NOT ENABLE_GCC_ANALYZER)
        return()
    endif()

    if(NOT CMAKE_C_COMPILER_ID STREQUAL "GNU")
        message(FATAL_ERROR "-fanalyzer requires gcc")
    endif()
    if(CMAKE_C_COMPILER_VERSION VERSION_LESS 10)
        message(FATAL_ERROR "-fanalyzer requires gcc 10 or newer")
    endif()

    target_compile_options(${target} PRIVATE $<$<COMPILE_LANGUAGE:C>:-fanalyzer>)
endfunction()
