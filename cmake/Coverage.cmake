# SPDX-License-Identifier: Apache-2.0
#
# Coverage instrumentation for the host tests. Coverage shows which lines the
# tests executed, not whether those lines are correct, so it is reported and
# not used as a gate.

function(apply_coverage target)
    if(NOT ENABLE_COVERAGE)
        return()
    endif()

    target_compile_options(${target} PUBLIC --coverage -O0 -g)
    target_link_options(${target} PUBLIC --coverage)
endfunction()
