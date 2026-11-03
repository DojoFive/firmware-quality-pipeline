#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Installs everything the gate needs. All three CI definitions call this
# script, so CI runners and developer machines use the same toolchain.
#
# Tested on Ubuntu 24.04 and Debian 13. Ubuntu 22.04 is too old: its cmake is
# 3.22 and the build needs 3.24. Adapt the package manager for other bases.
set -euo pipefail

PACKAGES=(
    build-essential     # gcc 11+, needed for -fanalyzer
    cmake               # 3.24+, needed for FetchContent FIND_PACKAGE_ARGS
    ninja-build         # the generator every CMake preset uses
    clang
    libclang-rt-dev     # libFuzzer and the clang sanitizer runtimes. Only a
                        # Recommends of clang, so --no-install-recommends drops
                        # it and the fuzz target fails to link.
    clang-tidy
    cppcheck
    gcovr
    python3             # tools/gen-sbom.py
    curl                # downloads grype
    git
    ca-certificates
)

# grype is not packaged for apt. Install a pinned release and check it against
# the SHA-256 published in that release's checksums.txt.
GRYPE_VERSION="0.120.1"
case "$(uname -m)" in
    x86_64)  GRYPE_ARCH="amd64"
             GRYPE_SHA256="0a9ee97ef5ae2ee953b0a80098105052e846cdbe319a57d808b519c33cd1343d" ;;
    aarch64) GRYPE_ARCH="arm64"
             GRYPE_SHA256="29f47391dc283aa79fcc38e65224cd61f64dec0ecfd0db7074128ebf8ff23514" ;;
    *)       echo "ERROR: no pinned grype build for $(uname -m)" >&2; exit 1 ;;
esac

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -qq
$SUDO apt-get install -y --no-install-recommends "${PACKAGES[@]}"

if ! grype version 2>/dev/null | grep -qE "^Version: +${GRYPE_VERSION}$"; then
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/grype.tar.gz" \
        "https://github.com/anchore/grype/releases/download/v${GRYPE_VERSION}/grype_${GRYPE_VERSION}_linux_${GRYPE_ARCH}.tar.gz"
    echo "${GRYPE_SHA256}  $tmp/grype.tar.gz" | sha256sum -c --quiet -
    tar -xzf "$tmp/grype.tar.gz" -C "$tmp" grype
    $SUDO install -m 0755 "$tmp/grype" /usr/local/bin/grype
    rm -rf "$tmp"
fi

echo "--- toolchain ---"
gcc --version | head -1
clang --version | head -1
cmake --version | head -1
cppcheck --version
clang-tidy --version | grep -i version | head -1
gcovr --version | head -1
grype version | grep '^Version'

# gcc 9 and older do not support -fanalyzer. Fail here rather than later in
# the analyzer job.
GCC_MAJOR="$(gcc -dumpversion | cut -d. -f1)"
if [ "$GCC_MAJOR" -lt 10 ]; then
    echo "ERROR: gcc $GCC_MAJOR is too old for -fanalyzer (need 10 or newer)" >&2
    exit 1
fi
echo "--- ok ---"
