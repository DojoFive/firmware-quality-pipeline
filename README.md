<!-- SPDX-License-Identifier: Apache-2.0 -->
# firmware-quality-pipeline

A static and dynamic analysis gate for bare-metal C, built from open-source
tools, with SBOM generation and a dependency CVE scan. Five defects are
seeded: four in the code, each one detectable by a different subset of the
tools, and one vulnerable dependency. CI checks that every stage still catches
the defects it is expected to catch.

```bash
git clone https://github.com/DojoFive/firmware-quality-pipeline.git
cd firmware-quality-pipeline
./tools/install-deps.sh     # Ubuntu 24.04 or Debian 13, uses sudo apt-get
./tools/check.sh
```

```
==> Compiler warnings as errors
    PASS gcc -Wall -Wextra -Wconversion -Werror
==> Static analysis
    PASS cppcheck
    PASS clang-tidy
    PASS gcc -fanalyzer
==> Dependency CVE scan (SBOM + grype)
    PASS grype (no high or critical CVEs)
==> Unit tests
    PASS ctest
==> Dynamic analysis (ASan + UBSan on the host tests)
    PASS sanitized test run
==> Coverage
    src/crc16.c          11   11   100%
    src/frame_parser.c   30   29    96%   77
    src/ringbuf.c        33   33   100%
    TOTAL                74   73    98%
    PASS coverage report generated
==> Fuzzing
    PASS fuzz_frame_parser (30s, no findings)

9 passed, 0 failed, 0 could not run
```

On macOS, `gcc` is Apple clang, so `-fanalyzer` is skipped, and Apple clang
does not include libFuzzer. Run the gate in a Linux container to get every
stage.

## The code under test

Three modules typical of small embedded products such as sensor nodes and
motor controllers. Bare-metal C11, no dynamic allocation, no RTOS,
caller-owned storage.

| Module | What it is |
|---|---|
| `src/crc16.c` | CRC-16/CCITT-FALSE, bitwise, no lookup table |
| `src/ringbuf.c` | Fixed-capacity byte FIFO over caller-supplied storage |
| `src/frame_parser.c` | Decodes a framed telemetry message off the wire |

`frame_parser` is the only module that handles externally supplied bytes, so
it is the fuzz target. It is also the module a CRA or UNECE R155 reviewer is
most likely to ask about.

## The seeded defects

Build with `-DDEMO_BUG=n` to compile one in. `DEMO_BUG=0` is the clean build.
Defect 5 changes only the SBOM, so it builds the same code as the clean build.
The results below come from running `tools/check.sh` against this repo, and CI
re-checks them on every run (see [Running it in CI](#running-it-in-ci)).

| | Compiler `-Werror` | cppcheck / clang-tidy / `-fanalyzer` | CVE scan | Unit tests | ASan + UBSan | Fuzzing |
|---|---|---|---|---|---|---|
| **1.** Off-by-one length check, reads one byte past the buffer | miss | miss | miss | miss | miss | **caught** |
| **2.** Signed shift overflow decoding a payload word | miss | miss | miss | miss | **caught** | **caught** |
| **3.** Read of an uninitialized local | **caught** | **caught** | miss | n/a | n/a | n/a |
| **4.** Ring buffer index corruption after wraparound | miss | miss | miss | **caught** | **caught**¹ | miss |
| **5.** Dependency with known critical CVEs (mbedTLS 2.16.0) | miss | miss | **caught** | miss | miss | miss |

¹ No sanitizer report fires for defect 4, because every access stays in bounds.
The sanitized run fails because it runs the same wraparound test.

No single column catches all five defects. Defect 1, a one-byte overread in
the parser for untrusted radio traffic, is missed by every static tool and
every unit test. The fuzzer finds it in under a second.

### Try it

```bash
DEMO_BUG=1 ./tools/check.sh   # only the fuzzer fails
DEMO_BUG=2 ./tools/check.sh   # unit tests pass, UBSan fails
DEMO_BUG=3 ./tools/check.sh   # the build fails, so nothing runs
DEMO_BUG=4 ./tools/check.sh   # only the tests fail
DEMO_BUG=5 ./tools/check.sh   # only the CVE scan fails
```

## What each stage covers

### Compiler warnings

`cmake/Warnings.cmake` enables about twenty warning flags, including
`-Wconversion`, `-Wsign-conversion`, `-Wcast-align` and `-Wstack-usage=512`,
all as errors. They cost nothing beyond the compiler you already use. Seeded
defect 3 is rejected here, before the static analysis stage. Enable these
before evaluating any additional tools.

### Static analysis

The three analyzers find different classes of bug, so the gate runs all of
them.

**cppcheck** is a common default for embedded C. It is fast, needs no build
integration, and handles the simple data-flow bugs that make up most firmware
defects.

**clang-tidy** is useful for C as well as C++. The `bugprone-*`, `cert-*` and
`clang-analyzer-*` groups all apply to C, and `clang-analyzer` does
path-sensitive analysis, which cppcheck does less of. `.clang-tidy` gives a
one-line reason for every disabled check. The
`insecureAPI.DeprecatedOrUnsafeBufferHandling` checker is disabled because it
recommends C11 Annex K functions (`memcpy_s` and similar), which are optional
in the standard and missing from nearly every embedded libc.

**gcc -fanalyzer** needs gcc 10 or newer and adds no new tool dependency. If
your vendor toolchain is a GCC fork, check its version; it may already
support it.

### SBOM and dependency CVE scan

`tools/gen-sbom.py` writes a CycloneDX SBOM from `sbom/components.toml`, and
grype checks it against public vulnerability databases. The build fails on any
high or critical CVE. The SBOM is saved as a CI artifact on every run.

Firmware dependencies are usually vendored source with no package manifest,
so SBOM tools like syft cannot discover them on their own. Each component is
listed by hand in `sbom/components.toml`, with a CPE. grype matches C
libraries by CPE: tested against mbedTLS 2.16.0, a PURL alone found no CVEs,
while the CPE found 37, 17 of them high or critical. `gen-sbom.py` refuses a
component without a CPE, and checks that the GoogleTest version matches the
`GIT_TAG` the build fetches.

This repo ships no third-party code, so the clean SBOM lists only GoogleTest,
marked as test-only. Seeded defect 5 adds mbedTLS 2.16.0 to the SBOM, which
has known critical CVEs such as CVE-2021-44732. No mbedTLS code is in the
repo; only the SBOM entry is added.

A CVE that does not affect your firmware, for example because the vulnerable
code is not compiled in, goes in `.grype.yaml` with a comment giving the
reason. The CVE scan also runs in the nightly pipeline, because new CVEs are
published against code that has not changed. grype downloads its
vulnerability database on each run, which takes about a minute.

### Unit tests and coverage

GoogleTest on the host, pulled in via `FetchContent` with `FIND_PACKAGE_ARGS`
so a system install is used when one exists.

Coverage is reported but does not gate the build. It shows which lines the
tests executed, not whether those lines are correct. The clean build sits at
98%. The one uncovered line is line 77 of `frame_parser.c`, the length check,
which is where seeded defect 1 lives. A high coverage number can still leave
the most important line untested, which is why this repo does not use a
coverage threshold.

### Dynamic analysis

ASan and UBSan run on the existing host test binary, enabled with compiler
flags:

```cmake
-fsanitize=address,undefined -fno-sanitize-recover=all
```

For code with no `malloc` calls, UBSan finds more than ASan: signed overflow,
shifts past the width of the type, misaligned access. Seeded defect 2 is a
byte-assembly expression that gives the right answer on a typical host and
passes every unit test, but is undefined behavior that a future compiler
optimization could break. No other tool in this repo reports it.

Valgrind is not used. For allocation-free code the host sanitizers cover the
same ground, run faster, and support targets that valgrind does not.

### Fuzzing

`fuzz/fuzz_frame_parser.c` is a twenty-line libFuzzer harness around the
function that parses untrusted input. Pull requests fuzz for 60 seconds and
the nightly job fuzzes for 30 minutes.

The fuzz target compiles the firmware sources into itself instead of linking
the static library. libFuzzer needs coverage instrumentation in the code under
test to guide mutation, and ASan only checks the loads and stores it has
instrumented. If the library is linked without instrumentation, the fuzzer
runs at full speed but cannot find anything, and a passing run gives false
assurance. This repo had that problem during development.

## Running it in CI

The repo includes pipeline definitions for three platforms:

| Platform | File |
|---|---|
| GitHub Actions | `.github/workflows/ci.yml` |
| GitLab CI | `.gitlab-ci.yml` |
| Azure DevOps | `azure-pipelines.yml` |

Each one installs the toolchain with `tools/install-deps.sh` and then uses the
same CMake presets that `tools/check.sh` uses locally. cppcheck needs no build
integration, so it is invoked directly, with the same flags in every file.
Because no stage is reimplemented per platform, the gate behaves the same on
every CI system, and a developer can reproduce any CI failure locally with
one command.

The job graph is the same on all three:

```
warnings (compiler -Werror)
    |
    +-- static analysis: cppcheck | clang-tidy | gcc -fanalyzer   (parallel)
    +-- unit tests
    +-- sanitizers (ASan + UBSan)
    +-- coverage
    +-- fuzz (60s on a PR, 30min nightly)

sbom + cve scan (needs no build, starts immediately)

after all of the above:
    seeded-defects: 0 | 1 | 2 | 3 | 4 | 5   (parallel, 0 = clean build)
```

The warnings job runs first because nothing downstream is meaningful if the
code does not compile cleanly. The `seeded-defects` jobs run last. Each one
compiles in a known defect and runs `tools/verify-seeded-defect.sh`, which
encodes the table above. Every stage the table marks as catching the defect
must report a finding, and every stage marked as missing it must pass. Job 0
runs the clean build through `tools/check.sh` and requires every stage to
pass.

Checking only that the gate failed is not sufficient. While this repo was
being written, the toolchain install left out the libFuzzer runtime, so the
fuzz target failed to link, and a check that only looked at the overall
result reported all four defects as caught. `check.sh` therefore records a
stage that could not run (a build failure, a missing runtime, or a fuzzer that
exits without writing a reproducer) as `error`, and the verifier never counts
an `error` as a catch.

### Platform reporting features

| | GitHub Actions | GitLab CI | Azure DevOps |
|---|---|---|---|
| Test results | artifact upload | `reports:junit` | `PublishTestResults@2` |
| Coverage | artifact upload | `reports:coverage_report`, MR badge | `PublishCodeCoverageResults@2` |
| Parallel defect matrix | `strategy.matrix` | `parallel:matrix` | `strategy.matrix` |
| Nightly fuzz | `schedule` trigger | pipeline schedule + `rules` | `schedules` block |
| SBOM | artifact upload | `reports:cyclonedx` | pipeline artifact |

`ctest --output-junit` writes test results as JUnit XML and `gcovr
--cobertura` writes coverage as Cobertura XML. All three platforms read both
formats. GitLab and Azure display them in the UI; GitHub stores them as
artifacts unless you add a reporting action.

### Adapting to your setup

**Self-hosted runners.** Embedded teams often build the toolchain into a
container image instead of installing it in every job. Build an image from
`tools/install-deps.sh`, then set `DEPS_PREINSTALLED=1` in GitLab or remove
the install step in the other two. This usually saves several minutes per
job.

**Cross-compiling.** Everything here runs on the host, because sanitizers and
fuzzing only work in host builds. Add your target build as a separate job that
compiles with the vendor toolchain and checks binary size. Do not try to run
ASan on the target.

**Fuzz duration.** The 60-second pull request run catches regressions. New
findings usually come from the nightly 30-minute run. If you keep a corpus
between runs, cache it; reusing a corpus helps more than running longer from
the seed inputs.

## Repository layout

```
include/            public headers
src/                the firmware under test
tests/              GoogleTest host tests
fuzz/               libFuzzer harness and seed corpus
cmake/              Warnings, Sanitizers, Coverage, StaticAnalysis modules
CMakePresets.json   one preset per stage, shared by check.sh and all CI
sbom/components.toml   third-party components, the input to the SBOM
tools/check.sh      runs every stage locally, in CI order
tools/gen-sbom.py   writes the CycloneDX SBOM
tools/verify-seeded-defect.sh   checks the defect table above
tools/install-deps.sh   toolchain install, shared by all CI
.clang-tidy         check selection, with a reason for each exclusion
.grype.yaml         grype settings and accepted CVEs
.github/workflows/  GitHub Actions pipeline
.gitlab-ci.yml      GitLab CI pipeline
azure-pipelines.yml Azure DevOps pipeline
```

## Notes for regulated work

This pipeline produces the analysis and test evidence an assessor will ask
for. It is not a compliance program. Assessors generally want to see that
the checks run on every change, that the build fails on new findings, and that
the results are retained. Which tools you use matters less than that.

The EU Cyber Resilience Act requires a machine-readable SBOM covering at
least the top-level dependencies, which `tools/gen-sbom.py` produces. The CI
scan covers the code being built now. For firmware already in the field, load
each released version's SBOM into a tool such as Dependency-Track, which
alerts when a new CVE affects it.

Not included here, but usually required: a MISRA C checker (cppcheck has a
MISRA addon, though the rule text is licensed separately), a documented
vulnerability disclosure process, and hardware-in-the-loop testing for
anything the host cannot exercise.

### Medical device software (IEC 62304 and FDA)

This repo is not a medical device and has no software safety classification.
If you adapt it for device software, the stages produce evidence for some of
the activities IEC 62304:2006+A1:2015 and FDA ask about. The activities below
are paraphrased. Check them against your licensed copy of the standard.

| What the pipeline produces | Typically used as evidence for |
|---|---|
| Unit test results, sanitizer runs, coverage report | Software unit verification |
| Compiler warning and static analysis results, with a written reason for each suppression | Unit acceptance criteria and coding rules you define in your development plan |
| `sbom/components.toml` and the generated CycloneDX SBOM | Identifying SOUP, and the SBOM FDA expects for cyber devices |
| grype results and the reasons recorded in `.grype.yaml` | Input to evaluating published SOUP anomaly lists. The evaluation itself is an engineering decision; the scan only tells you what to evaluate |
| The seeded-defect jobs | Objective evidence that each gate detects what it claims, one input to validating the pipeline as quality system software |

Not included here, and usually required for device software:
- Requirements and risk control traceability to tests
- Integration testing and system testing on target hardware, including
  hardware-in-the-loop tests
- Links to the ISO 14971 risk management file
- Software release activities
- Your own validation of these tools, proportionate to their risk. See FDA's
  guidance "Computer Software Assurance for Production and Quality Management
  System Software."

## Adapting it to your project

1. Replace `src/` and `include/` with your modules.
2. Keep `cmake/Warnings.cmake` and remove only the flags your toolchain
   rejects. Keep `-Wconversion` if at all possible.
3. Write a fuzz harness for each function that parses external input. That is
   usually a small number of functions.
4. List every third-party component in `sbom/components.toml`, with its CPE,
   and remove the seeded mbedTLS entry if you drop defect 5.
5. Keep the `seeded-defects` CI job, and seed defects that resemble bugs your
   team has actually shipped. Update the table in
   `tools/verify-seeded-defect.sh` when you change them. Without a test against
   known defects, there is no evidence that the gate detects anything.

## License

Copyright 2026 Dojo Five. Licensed under Apache-2.0. See `LICENSE` and
`NOTICE`.
