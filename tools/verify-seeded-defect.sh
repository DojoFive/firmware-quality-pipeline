#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Runs tools/check.sh with one seeded defect compiled in and compares the
# result, stage by stage, against the table in README.md. The stages the
# table says catch the defect must report a finding, and the stages it says
# miss the defect must pass. A stage that was skipped or could not run counts
# as a mismatch, because a missing tool or a broken build is neither a catch
# nor a miss.
#
# Checking only whether the gate failed is not enough. A broken fuzz build
# fails the gate for every defect, which would make every defect look caught.
#
#   ./tools/verify-seeded-defect.sh 2
#   ./tools/verify-seeded-defect.sh 0   the clean build must pass every stage
#   ./tools/verify-seeded-defect.sh 5   the seeded vulnerable dependency
set -uo pipefail

BUG="${1:?usage: $0 <seeded defect number, 0-5>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALL="warnings cppcheck clang-tidy gcc-analyzer cve-scan unit-tests sanitizers fuzz"

# One line per row of the README table. Stages a row leaves out are n/a.
# Coverage is never listed because it reports and does not gate.
case "$BUG" in
    0) caught="";                                          missed="$ALL" ;;
    1) caught="fuzz";                                      missed="warnings cppcheck clang-tidy gcc-analyzer cve-scan unit-tests sanitizers" ;;
    2) caught="sanitizers fuzz";                           missed="warnings cppcheck clang-tidy gcc-analyzer cve-scan unit-tests" ;;
    3) caught="warnings cppcheck clang-tidy gcc-analyzer"; missed="cve-scan" ;;
    4) caught="unit-tests sanitizers";                     missed="warnings cppcheck clang-tidy gcc-analyzer cve-scan fuzz" ;;
    5) caught="cve-scan";                                  missed="warnings cppcheck clang-tidy gcc-analyzer unit-tests sanitizers fuzz" ;;
    *) echo "unknown seeded defect: $BUG" >&2; exit 2 ;;
esac

DEMO_BUG="$BUG" "$ROOT/tools/check.sh"

results="$ROOT/build-check/results"
status_of() { awk -v s="$1" '$1 == s { print $2 }' "$results"; }

describe() {
    case "$1" in
        pass)  echo "passed" ;;
        fail)  echo "reported a finding" ;;
        error) echo "could not run" ;;
        skip)  echo "was skipped" ;;
        *)     echo "did not run" ;;
    esac
}

unexpected=0
expect() {
    local s want="$1"; shift
    for s in "$@"; do
        local got
        got="$(status_of "$s")"
        if [ "$got" != "$want" ]; then
            printf 'UNEXPECTED: %s %s, expected it to %s\n' \
                "$s" "$(describe "$got")" "$([ "$want" = fail ] && echo "catch defect $BUG" || echo pass)"
            unexpected=$((unexpected + 1))
        fi
    done
}
# shellcheck disable=SC2086  # word splitting of the stage lists is intended
expect fail $caught
# shellcheck disable=SC2086
expect pass $missed

echo
if [ "$unexpected" -ne 0 ]; then
    echo "seeded defect $BUG: $unexpected stage(s) did not behave as expected"
    exit 1
fi
if [ "$BUG" = "0" ]; then
    echo "clean build: every stage passed"
else
    echo "seeded defect $BUG: caught by $(echo $caught | sed 's/ /, /g')"
fi
