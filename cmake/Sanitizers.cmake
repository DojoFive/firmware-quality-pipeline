# SPDX-License-Identifier: Apache-2.0
#
# ASan and UBSan for the host tests. This code never calls malloc, so most
# findings come from UBSan: signed overflow, shifts past the width of the
# type, and misaligned access.

function(apply_sanitizers target)
    if(NOT ENABLE_SANITIZERS)
        return()
    endif()

    set(san_flags
        -fsanitize=address,undefined
        -fno-sanitize-recover=all
        -fno-omit-frame-pointer
        -g
    )

    target_compile_options(${target} PUBLIC ${san_flags})
    target_link_options(${target} PUBLIC ${san_flags})
endfunction()
