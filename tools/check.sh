#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Runs the whole gate locally, in the same order CI runs it, through the same
# CMake presets the CI jobs use.
#   ./tools/check.sh                  clean build, everything should pass
#   DEMO_BUG=2 ./tools/check.sh       compile in seeded defect 2 to see which stages catch it
#   DEMO_BUG=5 ./tools/check.sh       add the seeded vulnerable dependency to the SBOM
#   FUZZ_SECONDS=120 ./tools/check.sh fuzz for longer than the default 30 seconds
#
# Full logs for every stage land in build-check/. So does build-check/results,
# one "<stage> <status>" line per stage, which verify-seeded-defect.sh reads:
#   pass   the check ran and found nothing
#   fail   the check ran and found something
#   error  the check could not run (broken configure, build or toolchain)
#   skip   the tool is not installed
set -uo pipefail

BUG="${DEMO_BUG:-0}"
FUZZ_SECONDS="${FUZZ_SECONDS:-30}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

# Remove old build trees so a failed build cannot leave stale binaries behind
# for the test stages to run.
rm -rf build build-tidy build-analyzer build-sanitize build-coverage build-fuzz build-check
LOGS="$ROOT/build-check"
mkdir -p "$LOGS"
: >"$LOGS/results"

pass=0; fail=0; broken=0
stage()   { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()      { printf '    \033[32mPASS\033[0m %s\n' "$2"; echo "$1 pass" >>"$LOGS/results"; pass=$((pass+1)); }
bad()     { printf '    \033[31mFAIL\033[0m %s\n' "$2"; echo "$1 fail" >>"$LOGS/results"; fail=$((fail+1)); }
broke()   { printf '    \033[31mERROR\033[0m %s\n' "$2"; echo "$1 error" >>"$LOGS/results"; broken=$((broken+1)); }
skip()    { printf '    SKIP %s\n' "$2"; echo "$1 skip" >>"$LOGS/results"; }
have()    { command -v "$1" >/dev/null 2>&1; }
excerpt() { grep -E "$2" "$LOGS/$1.log" | head -"${3:-3}" | sed 's/^/         /'; }

# Configure and build one preset, logging both steps to build-check/<log>.log.
# Returns 1 if the configure step failed and 2 if the build did.
build_preset() {
    cmake --preset "$1" -DDEMO_BUG="$BUG" >"$LOGS/$2.log" 2>&1 || return 1
    cmake --build --preset "$1" >>"$LOGS/$2.log" 2>&1 || return 2
}

printf '\033[1mfirmware-quality-pipeline\033[0m  (DEMO_BUG=%s)\n' "$BUG"

build_ok=0

stage "Compiler warnings as errors"
build_preset default warnings; rc=$?
if [ "$rc" -eq 0 ]; then
    ok warnings "gcc -Wall -Wextra -Wconversion -Werror"
    build_ok=1
elif [ "$rc" -eq 2 ]; then
    bad warnings "build rejected by the compiler"
    excerpt warnings 'error:'
else
    broke warnings "cmake configure failed, see build-check/warnings.log"
fi

stage "Static analysis"
if have cppcheck; then
    # Exit code 2 means findings. Anything else nonzero is cppcheck itself failing.
    cppcheck --enable=all --inline-suppr --std=c11 --error-exitcode=2 \
        --suppressions-list=.cppcheck-suppressions -Iinclude -DDEMO_BUG="$BUG" \
        src/ >"$LOGS/cppcheck.log" 2>&1; rc=$?
    if [ "$rc" -eq 0 ]; then
        ok cppcheck "cppcheck"
    elif [ "$rc" -eq 2 ]; then
        bad cppcheck "cppcheck"
        excerpt cppcheck ': (error|warning|style|performance|portability):' 5
    else
        broke cppcheck "cppcheck exited $rc, see build-check/cppcheck.log"
    fi
else
    skip cppcheck "cppcheck (not installed)"
fi

if have clang && have clang-tidy; then
    build_preset tidy clang-tidy; rc=$?
    if [ "$rc" -eq 0 ]; then
        ok clang-tidy "clang-tidy"
    elif [ "$rc" -eq 2 ]; then
        bad clang-tidy "clang-tidy"
        excerpt clang-tidy 'warning:|error:' 5
    else
        broke clang-tidy "cmake configure failed, see build-check/clang-tidy.log"
    fi
else
    skip clang-tidy "clang-tidy (clang or clang-tidy not installed)"
fi

# The analyzer preset requires GNU gcc 10 or newer. On macOS "gcc" is clang.
if have gcc && gcc -v 2>&1 | grep -q '^gcc version' \
   && [ "$(gcc -dumpversion | cut -d. -f1)" -ge 10 ]; then
    build_preset analyzer gcc-analyzer; rc=$?
    if [ "$rc" -eq 0 ]; then
        ok gcc-analyzer "gcc -fanalyzer"
    elif [ "$rc" -eq 2 ]; then
        bad gcc-analyzer "gcc -fanalyzer"
        excerpt gcc-analyzer 'warning:|error:' 5
    else
        broke gcc-analyzer "cmake configure failed, see build-check/gcc-analyzer.log"
    fi
else
    skip gcc-analyzer "gcc -fanalyzer (needs GNU gcc 10 or newer)"
fi

stage "Dependency CVE scan (SBOM + grype)"
if have grype && have python3; then
    if ! python3 tools/gen-sbom.py --demo-bug "$BUG" -o "$LOGS/sbom.cdx.json" \
         >"$LOGS/cve-scan.log" 2>&1; then
        broke cve-scan "SBOM generation failed, see build-check/cve-scan.log"
    else
        # grype exits 2 when a finding meets --fail-on and 1 when it cannot run,
        # for example because the vulnerability database download failed.
        grype "sbom:$LOGS/sbom.cdx.json" --fail-on high >>"$LOGS/cve-scan.log" 2>&1; rc=$?
        if [ "$rc" -eq 0 ]; then
            ok cve-scan "grype (no high or critical CVEs)"
        elif [ "$rc" -eq 2 ]; then
            bad cve-scan "grype found high or critical CVEs"
            excerpt cve-scan ' (Critical|High) ' 3
        else
            broke cve-scan "grype exited $rc, see build-check/cve-scan.log"
        fi
    fi
else
    skip cve-scan "grype (grype or python3 not installed)"
fi

stage "Unit tests"
if [ "$build_ok" -eq 0 ]; then
    skip unit-tests "ctest (nothing built)"
elif ctest --preset default >"$LOGS/unit-tests.log" 2>&1; then
    ok unit-tests "ctest"
else
    bad unit-tests "ctest"
    excerpt unit-tests '\*\*\*Failed' 5
fi

stage "Dynamic analysis (ASan + UBSan on the host tests)"
if build_preset sanitize sanitizers; then
    if ctest --preset sanitize >>"$LOGS/sanitizers.log" 2>&1; then
        ok sanitizers "sanitized test run"
    else
        bad sanitizers "sanitized test run"
        excerpt sanitizers 'runtime error|ERROR: AddressSanitizer|\*\*\*Failed'
    fi
else
    broke sanitizers "sanitized build"
    excerpt sanitizers 'error:'
fi

stage "Coverage"
if have gcovr; then
    if build_preset coverage coverage; then
        # Test failures belong to the unit test stage. Coverage reports either way.
        ctest --preset coverage >>"$LOGS/coverage.log" 2>&1
        if (cd build-coverage && gcovr --root .. --filter '../src/' --txt) \
             >"$LOGS/coverage.txt" 2>>"$LOGS/coverage.log"; then
            tail -7 "$LOGS/coverage.txt" | sed 's/^/    /'
            ok coverage "coverage report generated"
        else
            broke coverage "gcovr"
        fi
    else
        broke coverage "coverage build"
    fi
else
    skip coverage "gcovr (not installed)"
fi

stage "Fuzzing"
if have clang; then
    if build_preset fuzz fuzz; then
        # libFuzzer writes new inputs into the first corpus directory and
        # drops crash files into the cwd. Run against a scratch copy so a
        # local run never dirties the tree.
        corpus="$LOGS/fuzz-corpus"
        mkdir -p "$corpus"
        cp fuzz/corpus/*.bin "$corpus/"
        mkdir -p "$LOGS/fuzz-findings"
        if ./build-fuzz/fuzz/fuzz_frame_parser "$corpus" \
             -artifact_prefix="$LOGS/fuzz-findings/" \
             -max_total_time="$FUZZ_SECONDS" >>"$LOGS/fuzz.log" 2>&1; then
            ok fuzz "fuzz_frame_parser (${FUZZ_SECONDS}s, no findings)"
        elif [ -n "$(ls -A "$LOGS/fuzz-findings")" ]; then
            # Count the run as a finding only if libFuzzer saved a reproducer.
            # Any other nonzero exit means the stage itself is broken.
            bad fuzz "fuzz_frame_parser found a crash"
            excerpt fuzz 'ERROR:|SUMMARY:'
            printf '         reproducer saved under %s\n' "$LOGS/fuzz-findings"
        else
            broke fuzz "fuzz_frame_parser exited without a reproducer, see build-check/fuzz.log"
        fi
    else
        broke fuzz "fuzz build"
        excerpt fuzz 'error:'
    fi
else
    skip fuzz "fuzzing (clang not installed)"
fi

printf '\n\033[1m%d passed, %d failed, %d could not run\033[0m\n' "$pass" "$fail" "$broken"
[ "$fail" -eq 0 ] && [ "$broken" -eq 0 ]
