# Unified CI Justfile for Self VM — builds and tests both vm64 and vm32
#
# Usage:
#   just SELFSRC=self64@current fullrun-all       Run all platforms
#   just SELFSRC=self64@current vm64-macos-native Build and test vm64 on macOS
#   just SELFSRC=self64@current vm32-ubuntu-amd64 Build and test vm32 on Ubuntu
#   just provision-all                            Download and provision VM images
#   just check-env                                Verify tools and source trees
#
# Source trees live in src/ (e.g. src/self64@current). Specify which to
# build via the SELFSRC variable or environment variable.
#
# Requirements: qemu, sshpass, rsync, cmake, expect (for FreeBSD provisioning)

export SELFSRC := env('SELFSRC', '')
SRCDIR := if SELFSRC == '' { '' } else { justfile_directory() + '/src/' + SELFSRC }
BUILD_MACOS := justfile_directory() + '/build/macos-native'
NCPU := `sysctl -n hw.ncpu 2>/dev/null || echo 4`

# ─── Images ─────────────────────────────────────────────

# vm64 platforms
UBUNTU_ARM64_QCOW  := 'images/ubuntu-arm64.qcow2'
UBUNTU_AMD64_QCOW  := 'images/ubuntu-amd64.qcow2'
FREEBSD_ARM64_QCOW := 'images/freebsd-arm64.qcow2'
FREEBSD_AMD64_QCOW := 'images/freebsd-amd64.qcow2'
NETBSD_AMD64_QCOW  := 'images/netbsd-amd64.qcow2'

# vm platforms (32-bit, AMD64 host with multilib support)
UBUNTU_MULTILIB_QCOW  := 'images/ubuntu-amd64-multilib.qcow2'
FREEBSD_LIB32_QCOW := 'images/freebsd-amd64-lib32.qcow2'
NETBSD_I386_QCOW   := 'images/netbsd-i386.qcow2'

# ─── Download URLs ────────────────────────────────────────

UBUNTU_ARM64_URL   := 'https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img'
UBUNTU_AMD64_URL   := 'https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img'
FREEBSD_AMD64_URL  := 'https://download.freebsd.org/releases/VM-IMAGES/15.0-RELEASE/amd64/Latest/FreeBSD-15.0-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2.xz'
FREEBSD_ARM64_URL  := 'https://download.freebsd.org/releases/VM-IMAGES/15.0-RELEASE/aarch64/Latest/FreeBSD-15.0-RELEASE-arm64-aarch64-BASIC-CLOUDINIT-ufs.qcow2.xz'
NETBSD_I386_URL    := 'http://ftp.netbsd.org/pub/NetBSD/NetBSD-10.1/i386/'
NETBSD_AMD64_URL   := 'http://ftp.netbsd.org/pub/NetBSD/NetBSD-10.1/amd64/'

# ─── Default ──────────────────────────────────────────────

[private]
default:
    @just help

# Show usage and available recipes
[group('Environment')]
help:
    #!/usr/bin/env bash
    echo "$(tput bold)Self CI$(tput sgr0) — build and test the Self VM across platforms"
    echo ""
    echo "$(tput bold)Quick start:$(tput sgr0)"
    echo "  1. Add a source tree:    git clone <url> src/self64@current"
    echo "  2. Provision VMs:        just provision-all"
    echo "  3. Run all builds:       just SELFSRC=self64@current fullrun-all"
    echo ""
    echo "$(tput bold)Source trees:$(tput sgr0)"
    if [ -d "{{justfile_directory()}}/src" ]; then
        trees=$(ls -1 "{{justfile_directory()}}/src" 2>/dev/null)
        if [ -n "$trees" ]; then
            echo "$trees" | sed 's/^/  /'
        else
            echo "  (none — add a source tree to src/)"
        fi
    else
        echo "  (no src/ directory — create it and add a source tree)"
    fi
    echo ""
    echo "$(tput bold)Recipes:$(tput sgr0)"
    just --list --list-heading ''

_check-src:
    #!/usr/bin/env bash
    if [ -z "{{SELFSRC}}" ]; then
        echo "ERROR: SELFSRC is not set."
        echo "Usage: just SELFSRC=<name> <recipe>"
        echo ""
        if [ -d "{{justfile_directory()}}/src" ]; then
            echo "Available source trees in src/:"
            ls -1 "{{justfile_directory()}}/src" 2>/dev/null | sed 's/^/  /' || echo "  (none)"
        else
            echo "No src/ directory found. Create one and add a source tree:"
            echo "  git clone <url> src/self64@current"
        fi
        exit 1
    fi
    if [ ! -d "{{SRCDIR}}" ]; then
        echo "ERROR: Source tree not found: {{SRCDIR}}"
        echo ""
        echo "Available source trees in src/:"
        ls -1 "{{justfile_directory()}}/src" 2>/dev/null | sed 's/^/  /' || echo "  (none)"
        exit 1
    fi

# ═══════════════════════════════════════════════════════════
#  Full Runs
# ═══════════════════════════════════════════════════════════

# Run all active platforms for both vm64 and vm32
[group('Full Runs')]
fullrun-all:
    #!/usr/bin/env bash
    just _check-src
    RESULTS=()
    FAILS=0
    START=$SECONDS

    just fullrun-vm64 && RESULTS+=("fullrun-vm64: PASS") || { RESULTS+=("fullrun-vm64: FAIL"); FAILS=$((FAILS + 1)); }
    just fullrun-vm32 && RESULTS+=("fullrun-vm32: PASS") || { RESULTS+=("fullrun-vm32: FAIL"); FAILS=$((FAILS + 1)); }

    ELAPSED=$((SECONDS - START))
    echo ""
    echo "============================="
    printf '=== Results (%dm %ds) ===\n' $((ELAPSED / 60)) $((ELAPSED % 60))
    echo "============================="
    for r in "${RESULTS[@]}"; do
        if [[ "$r" == *PASS ]]; then
            echo "$(tput setaf 2)  $r$(tput sgr0)"
        else
            echo "$(tput setaf 1)  $r$(tput sgr0)"
        fi
    done
    echo ""
    if [ $FAILS -gt 0 ]; then
        just _fail "$FAILS suite(s) failed"
        exit 1
    else
        just _pass "All suites passed"
    fi

# Run all vm64 platforms
[group('Full Runs')]
fullrun-vm64:
    #!/usr/bin/env bash
    just _check-src
    RESULTS=()
    FAILS=0
    START=$SECONDS

    just vm64-macos-native && RESULTS+=("vm64-macos-native: PASS") || { RESULTS+=("vm64-macos-native: FAIL"); FAILS=$((FAILS + 1)); }
    just vm64-ubuntu-arm64 && RESULTS+=("vm64-ubuntu-arm64: PASS") || { RESULTS+=("vm64-ubuntu-arm64: FAIL"); FAILS=$((FAILS + 1)); }
    just vm64-ubuntu-amd64 && RESULTS+=("vm64-ubuntu-amd64: PASS") || { RESULTS+=("vm64-ubuntu-amd64: FAIL"); FAILS=$((FAILS + 1)); }
    just vm64-freebsd-arm64 && RESULTS+=("vm64-freebsd-arm64: PASS") || { RESULTS+=("vm64-freebsd-arm64: FAIL"); FAILS=$((FAILS + 1)); }
    just vm64-freebsd-amd64 && RESULTS+=("vm64-freebsd-amd64: PASS") || { RESULTS+=("vm64-freebsd-amd64: FAIL"); FAILS=$((FAILS + 1)); }
    just vm64-netbsd-amd64 && RESULTS+=("vm64-netbsd-amd64: PASS") || { RESULTS+=("vm64-netbsd-amd64: FAIL"); FAILS=$((FAILS + 1)); }

    ELAPSED=$((SECONDS - START))
    echo ""
    echo "============================="
    printf '=== Results (%dm %ds) ===\n' $((ELAPSED / 60)) $((ELAPSED % 60))
    echo "============================="
    for r in "${RESULTS[@]}"; do
        if [[ "$r" == *PASS ]]; then
            echo "$(tput setaf 2)  $r$(tput sgr0)"
        else
            echo "$(tput setaf 1)  $r$(tput sgr0)"
        fi
    done
    echo ""
    if [ $FAILS -gt 0 ]; then
        just _fail "$FAILS platform(s) failed"
        exit 1
    else
        just _pass "All platforms passed"
    fi

# Run all vm32 platforms
[group('Full Runs')]
fullrun-vm32:
    #!/usr/bin/env bash
    just _check-src
    RESULTS=()
    FAILS=0
    START=$SECONDS

    just vm32-ubuntu-amd64 && RESULTS+=("vm32-ubuntu-amd64: PASS") || { RESULTS+=("vm32-ubuntu-amd64: FAIL"); FAILS=$((FAILS + 1)); }
    just vm32-freebsd-amd64-lib32 && RESULTS+=("vm32-freebsd-amd64-lib32: PASS") || { RESULTS+=("vm32-freebsd-amd64-lib32: FAIL"); FAILS=$((FAILS + 1)); }
    just vm32-netbsd-i386 && RESULTS+=("vm32-netbsd-i386: PASS") || { RESULTS+=("vm32-netbsd-i386: FAIL"); FAILS=$((FAILS + 1)); }

    ELAPSED=$((SECONDS - START))
    echo ""
    echo "============================="
    printf '=== Results (%dm %ds) ===\n' $((ELAPSED / 60)) $((ELAPSED % 60))
    echo "============================="
    for r in "${RESULTS[@]}"; do
        if [[ "$r" == *PASS ]]; then
            echo "$(tput setaf 2)  $r$(tput sgr0)"
        else
            echo "$(tput setaf 1)  $r$(tput sgr0)"
        fi
    done
    echo ""
    if [ $FAILS -gt 0 ]; then
        just _fail "$FAILS platform(s) failed"
        exit 1
    else
        just _pass "All platforms passed"
    fi

# ═══════════════════════════════════════════════════════════
#  vm64 Build + Test
# ═══════════════════════════════════════════════════════════

# Build and test vm64 natively on macOS
[group('vm64')]
vm64-macos-native:
    #!/usr/bin/env bash
    set -uo pipefail
    just _check-src
    result=0
    just _vm64-compile-macos-native || result=$?
    if [ $result -eq 0 ]; then
        BUILD_DIR="{{BUILD_MACOS}}"
        mkdir -p "{{justfile_directory()}}/artifacts"
        cp -R "$BUILD_DIR/Self.app" "{{justfile_directory()}}/artifacts/Self-vm64-macos-arm64.app"
        just _pass "vm64-macos-native"
    else
        just _fail "vm64-macos-native"
    fi
    exit $result

# Build and test vm64 on Ubuntu ARM64
[group('vm64')]
vm64-ubuntu-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    just _check-src
    just start-ubuntu-arm64
    PORT=$(cat ubuntu-arm64.port)
    result=0
    just _vm64-compile-ubuntu-arm64 "$PORT" || result=$?
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-vm64-ubuntu-arm64"
    fi
    just stop-ubuntu-arm64
    if [ $result -eq 0 ]; then
        just _pass "vm64-ubuntu-arm64"
    else
        just _fail "vm64-ubuntu-arm64"
    fi
    exit $result

# Build and test vm64 on Ubuntu AMD64
[group('vm64')]
vm64-ubuntu-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    just _check-src
    just start-ubuntu-amd64
    PORT=$(cat ubuntu-amd64.port)
    result=0
    just _vm64-compile-ubuntu-amd64 "$PORT" || result=$?
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-vm64-ubuntu-amd64"
    fi
    just stop-ubuntu-amd64
    if [ $result -eq 0 ]; then
        just _pass "vm64-ubuntu-amd64"
    else
        just _fail "vm64-ubuntu-amd64"
    fi
    exit $result

# Build and test vm64 on FreeBSD ARM64
[group('vm64')]
vm64-freebsd-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    just _check-src
    just start-freebsd-arm64
    PORT=$(cat freebsd-arm64.port)
    result=0
    just _vm64-compile-freebsd-arm64 "$PORT" || result=$?
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-vm64-freebsd-arm64"
    fi
    just stop-freebsd-arm64
    if [ $result -eq 0 ]; then
        just _pass "vm64-freebsd-arm64"
    else
        just _fail "vm64-freebsd-arm64"
    fi
    exit $result

# Build and test vm64 on FreeBSD AMD64 (TCG-emulated)
[group('vm64')]
vm64-freebsd-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    just _check-src
    just start-freebsd-amd64
    PORT=$(cat freebsd-amd64.port)
    result=0
    just _vm64-compile-freebsd-amd64 "$PORT" || result=$?
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-vm64-freebsd-amd64"
    fi
    just stop-freebsd-amd64
    if [ $result -eq 0 ]; then
        just _pass "vm64-freebsd-amd64"
    else
        just _fail "vm64-freebsd-amd64"
    fi
    exit $result

# Build and test vm64 on NetBSD AMD64 (TCG-emulated)
[group('vm64')]
vm64-netbsd-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    just _check-src
    just start-netbsd-amd64
    PORT=$(cat netbsd-amd64.port)
    result=0
    just _vm64-compile-netbsd-amd64 "$PORT" || result=$?
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-vm64-netbsd-amd64"
    fi
    just stop-netbsd-amd64
    if [ $result -eq 0 ]; then
        just _pass "vm64-netbsd-amd64"
    else
        just _fail "vm64-netbsd-amd64"
    fi
    exit $result

# ═══════════════════════════════════════════════════════════
#  vm32 Build + Test
# ═══════════════════════════════════════════════════════════

# Build and test vm32 on Ubuntu AMD64
[group('vm32')]
vm32-ubuntu-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    just _check-src
    just start-ubuntu-amd64-multilib
    PORT=$(cat ubuntu-amd64-multilib.port)
    result=0
    just _vm32-compile-ubuntu-amd64 "$PORT" || result=$?
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-vm32-ubuntu-amd64"
    fi
    just stop-ubuntu-amd64-multilib
    if [ $result -eq 0 ]; then
        just _pass "vm32-ubuntu-amd64"
    else
        just _fail "vm32-ubuntu-amd64"
    fi
    exit $result

# Build and test vm32 on FreeBSD AMD64 lib32
[group('vm32')]
vm32-freebsd-amd64-lib32:
    #!/usr/bin/env bash
    set -euo pipefail
    just _check-src
    just start-freebsd-amd64-lib32
    PORT=$(cat freebsd-amd64-lib32.port)
    result=0
    just _vm32-compile-freebsd-amd64-lib32 "$PORT" || result=$?
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-vm32-freebsd-amd64-lib32"
    fi
    just stop-freebsd-amd64-lib32
    if [ $result -eq 0 ]; then
        just _pass "vm32-freebsd-amd64-lib32"
    else
        just _fail "vm32-freebsd-amd64-lib32"
    fi
    exit $result

# Build and test vm32 on NetBSD i386
[group('vm32')]
vm32-netbsd-i386:
    #!/usr/bin/env bash
    set -euo pipefail
    just _check-src
    just start-netbsd-i386
    PORT=$(cat netbsd-i386.port)
    result=0
    just _vm32-compile-netbsd-i386 "$PORT" || result=$?
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-vm32-netbsd-i386"
    fi
    just stop-netbsd-i386
    if [ $result -eq 0 ]; then
        just _pass "vm32-netbsd-i386"
    else
        just _fail "vm32-netbsd-i386"
    fi
    exit $result

# ═══════════════════════════════════════════════════════════
#  vm64 Compile (internal)
# ═══════════════════════════════════════════════════════════

_vm64-compile-macos-native:
    #!/usr/bin/env bash
    set -euo pipefail
    just _action "Building vm64 natively on macOS"
    BUILD_DIR="{{BUILD_MACOS}}"
    mkdir -p "$BUILD_DIR"
    cmake -S "{{SRCDIR}}/vm64" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release
    rm -f "$BUILD_DIR/incls/_precompiled.hh.gch"
    cmake --build "$BUILD_DIR" -j{{NCPU}}
    SELFVM="$BUILD_DIR/Self.app/Contents/MacOS/Self"
    $SELFVM --vm-run-tests
    (cd "{{SRCDIR}}/objects" && echo "saveAs: 'auto.snap64'. _Quit" | $SELFVM -f worldbuilder.self -o morphic)
    $SELFVM -s "{{SRCDIR}}/objects/auto.snap64" --runAutomaticTests --headless

_vm64-compile-ubuntu-arm64 port:
    @just _action "Compiling vm64 on Ubuntu ARM64"
    @just _rsync {{port}}
    @just do {{port}} 'cd /tmp/self-build && cmake -S vm64 -B build -DCMAKE_BUILD_TYPE=Release -DSELF_QUARTZ=OFF && rm -f build/incls/_precompiled.hh.gch && cmake --build build -j$(nproc)'
    @just do {{port}} 'cd /tmp/self-build && build/Self --vm-run-tests'
    @just do {{port}} 'cd /tmp/self-build/objects && echo "saveAs: '"'"'auto.snap64'"'"'. _Quit" | ../build/Self -f worldBuilder.self -o morphic'
    @just do {{port}} 'cd /tmp/self-build && echo "_Quit" | build/Self -s objects/auto.snap64'
    @just do {{port}} 'cd /tmp/self-build && build/Self -s objects/auto.snap64 --runAutomaticTests --headless'
    @just _banner "Finished vm64 on Ubuntu ARM64"

_vm64-compile-ubuntu-amd64 port:
    @just _action "Compiling vm64 on Ubuntu AMD64"
    @just _rsync {{port}}
    @just do {{port}} 'cd /tmp/self-build && cmake -S vm64 -B build -DCMAKE_BUILD_TYPE=Release -DSELF_QUARTZ=OFF && rm -f build/incls/_precompiled.hh.gch && cmake --build build -j$(nproc)'
    @just do {{port}} 'cd /tmp/self-build && build/Self --vm-run-tests'
    @just do {{port}} 'cd /tmp/self-build/objects && echo "saveAs: '"'"'auto.snap64'"'"'. _Quit" | ../build/Self -f worldBuilder.self -o morphic'
    @just do {{port}} 'cd /tmp/self-build && echo "_Quit" | build/Self -s objects/auto.snap64'
    @just do {{port}} 'cd /tmp/self-build && build/Self -s objects/auto.snap64 --runAutomaticTests --headless'
    @just _banner "Finished vm64 on Ubuntu AMD64"

_vm64-compile-freebsd-arm64 port:
    @just _action "Compiling vm64 on FreeBSD ARM64"
    @just _rsync {{port}}
    @just do {{port}} 'cd /tmp/self-build && cmake -S vm64 -B build -DCMAKE_BUILD_TYPE=Release -DSELF_QUARTZ=OFF && rm -f build/incls/_precompiled.hh.gch && cmake --build build -j$(sysctl -n hw.ncpu)'
    @just do {{port}} 'cd /tmp/self-build && build/Self --vm-run-tests'
    @just do {{port}} 'cd /tmp/self-build/objects && echo "saveAs: '"'"'auto.snap64'"'"'. _Quit" | ../build/Self -f worldBuilder.self -o morphic'
    @just do {{port}} 'cd /tmp/self-build && echo "_Quit" | build/Self -s objects/auto.snap64'
    @just do {{port}} 'cd /tmp/self-build && build/Self -s objects/auto.snap64 --runAutomaticTests --headless'
    @just _banner "Finished vm64 on FreeBSD ARM64"

_vm64-compile-freebsd-amd64 port:
    @just _action "Compiling vm64 on FreeBSD AMD64"
    @just _rsync {{port}}
    @just do {{port}} 'cd /tmp/self-build && cmake -S vm64 -B build -DCMAKE_BUILD_TYPE=Release -DSELF_QUARTZ=OFF && rm -f build/incls/_precompiled.hh.gch && cmake --build build -j$(sysctl -n hw.ncpu)'
    @just do {{port}} 'cd /tmp/self-build && build/Self --vm-run-tests'
    @just do {{port}} 'cd /tmp/self-build/objects && echo "saveAs: '"'"'auto.snap64'"'"'. _Quit" | ../build/Self -f worldBuilder.self -o morphic'
    @just do {{port}} 'cd /tmp/self-build && echo "_Quit" | build/Self -s objects/auto.snap64'
    @just do {{port}} 'cd /tmp/self-build && build/Self -s objects/auto.snap64 --runAutomaticTests --headless'
    @just _banner "Finished vm64 on FreeBSD AMD64"

_vm64-compile-netbsd-amd64 port:
    @just _action "Compiling vm64 on NetBSD AMD64"
    @just _rsync {{port}}
    @just do {{port}} 'cd /tmp/self-build && cmake -S vm64 -B build -DCMAKE_BUILD_TYPE=Release -DSELF_QUARTZ=OFF && rm -f build/incls/_precompiled.hh.gch && cmake --build build -j$(sysctl -n hw.ncpu)'
    @just do {{port}} 'cd /tmp/self-build && build/Self --vm-run-tests'
    @just do {{port}} 'cd /tmp/self-build/objects && echo "saveAs: '"'"'auto.snap64'"'"'. _Quit" | ../build/Self -f worldBuilder.self -o morphic'
    @just do {{port}} 'cd /tmp/self-build && echo "_Quit" | build/Self -s objects/auto.snap64'
    @just do {{port}} 'cd /tmp/self-build && build/Self -s objects/auto.snap64 --runAutomaticTests --headless'
    @just _banner "Finished vm64 on NetBSD AMD64"

# ═══════════════════════════════════════════════════════════
#  vm32 Compile (internal)
# ═══════════════════════════════════════════════════════════

_vm32-compile-ubuntu-amd64 port:
    @just _action "Compiling vm32 on Ubuntu AMD64"
    @just _rsync {{port}}
    @just do {{port}} 'cd /tmp/self-build && PKG_CONFIG_LIBDIR=/usr/lib/i386-linux-gnu/pkgconfig:/usr/share/pkgconfig cmake -S vm -B build -DCMAKE_BUILD_TYPE=Release -DSELF_QUARTZ=OFF && cmake --build build -j$(nproc)'
    @just do {{port}} 'cd /tmp/self-build/objects && echo "saveAs: '"'"'auto.snap'"'"'. _Quit" | ../build/Self -f worldBuilder.self -o morphic'
    @just do {{port}} 'cd /tmp/self-build && echo "_Quit" | build/Self -s objects/auto.snap'
    @just do {{port}} 'cd /tmp/self-build && build/Self -s objects/auto.snap --runAutomaticTests --headless'
    @just _banner "Finished vm32 on Ubuntu AMD64"

_vm32-compile-freebsd-amd64-lib32 port:
    @just _action "Compiling vm32 on FreeBSD i386 chroot"
    @just _rsync {{port}}
    @just do {{port}} 'sudo chroot /compat/i386 /bin/sh -c "cd /tmp/self-build && cmake -S vm -B build -DCMAKE_BUILD_TYPE=Release -DSELF_QUARTZ=OFF -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ && cmake --build build -j$(sysctl -n hw.ncpu)"'
    @just do {{port}} 'sudo chroot /compat/i386 /bin/sh -c "cd /tmp/self-build/objects && echo \"saveAs: '"'"'auto.snap'"'"'. _Quit\" | ../build/Self -f worldBuilder.self -o morphic"'
    @just do {{port}} 'sudo chroot /compat/i386 /bin/sh -c "cd /tmp/self-build && echo _Quit | build/Self -s objects/auto.snap"'
    @just do {{port}} 'sudo chroot /compat/i386 /bin/sh -c "cd /tmp/self-build && build/Self -s objects/auto.snap --runAutomaticTests --headless"'
    @just _banner "Finished vm32 on FreeBSD i386 chroot"

_vm32-compile-netbsd-i386 port:
    @just _action "Compiling vm32 on NetBSD i386"
    @just _rsync {{port}}
    @just do {{port}} 'cd /tmp/self-build && cmake -S vm -B build -DCMAKE_BUILD_TYPE=Release -DSELF_QUARTZ=OFF && cmake --build build -j$(sysctl -n hw.ncpu)'
    @just do {{port}} 'cd /tmp/self-build/objects && echo "saveAs: '"'"'auto.snap'"'"'. _Quit" | ../build/Self -f worldBuilder.self -o morphic'
    @just do {{port}} 'cd /tmp/self-build && echo "_Quit" | build/Self -s objects/auto.snap'
    @just do {{port}} 'cd /tmp/self-build && build/Self -s objects/auto.snap --runAutomaticTests --headless'
    @just _banner "Finished vm32 on NetBSD i386"

# ═══════════════════════════════════════════════════════════
#  Provision — Download and provision VM images
# ═══════════════════════════════════════════════════════════

# Download and provision all VM images
[group('Provision')]
provision-all: provision-ubuntu-arm64 provision-ubuntu-amd64 provision-ubuntu-amd64-multilib provision-freebsd-amd64-lib32 provision-freebsd-arm64 provision-freebsd-amd64 provision-netbsd-i386 provision-netbsd-amd64
    @just _banner "All images ready"

# Download and provision Ubuntu ARM64
[group('Provision')]
provision-ubuntu-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images
    if [ ! -f "{{UBUNTU_ARM64_QCOW}}" ]; then
        just _action "Downloading Ubuntu ARM64 cloud image"
        curl -L -o "{{UBUNTU_ARM64_QCOW}}" "{{UBUNTU_ARM64_URL}}"
        qemu-img resize "{{UBUNTU_ARM64_QCOW}}" 20G
    else
        echo "Image already exists: {{UBUNTU_ARM64_QCOW}}"
    fi
    just _create-cloud-init-arm64
    just _action "Provisioning Ubuntu ARM64 via cloud-init (will shut down automatically when done)"
    PORT=$(just _free-port)
    qemu-system-aarch64 \
        -machine virt -accel hvf -cpu host \
        -m 4G -smp 4 \
        -drive file={{UBUNTU_ARM64_QCOW}},if=virtio \
        -drive file=images/cloud-init-arm64.iso,if=virtio,media=cdrom \
        -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -nographic
    just _banner "Ubuntu ARM64 image ready"

# Download and provision Ubuntu AMD64 (vm64 only)
[group('Provision')]
provision-ubuntu-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images
    if [ ! -f "{{UBUNTU_AMD64_QCOW}}" ]; then
        just _action "Downloading Ubuntu AMD64 cloud image"
        curl -L -o "{{UBUNTU_AMD64_QCOW}}" "{{UBUNTU_AMD64_URL}}"
        qemu-img resize "{{UBUNTU_AMD64_QCOW}}" 20G
    else
        echo "Image already exists: {{UBUNTU_AMD64_QCOW}}"
    fi
    just _create-cloud-init-amd64
    just _action "Provisioning Ubuntu AMD64 via cloud-init (will shut down automatically when done)"
    PORT=$(just _free-port)
    qemu-system-x86_64 \
        -machine q35 -cpu qemu64 \
        -m 4G -smp 2 \
        -drive file={{UBUNTU_AMD64_QCOW}},if=virtio \
        -drive file=images/cloud-init-amd64.iso,if=virtio,media=cdrom \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -nographic
    just _banner "Ubuntu AMD64 image ready"

# Download and provision Ubuntu AMD64 multilib (vm 32-bit builds)
[group('Provision')]
provision-ubuntu-amd64-multilib:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images
    if [ ! -f "{{UBUNTU_MULTILIB_QCOW}}" ]; then
        just _action "Downloading Ubuntu AMD64 cloud image (for multilib)"
        curl -L -o "{{UBUNTU_MULTILIB_QCOW}}" "{{UBUNTU_AMD64_URL}}"
        qemu-img resize "{{UBUNTU_MULTILIB_QCOW}}" 20G
    else
        echo "Image already exists: {{UBUNTU_MULTILIB_QCOW}}"
    fi
    just _create-cloud-init-amd64-multilib
    just _action "Provisioning Ubuntu AMD64 multilib via cloud-init (will shut down automatically when done)"
    PORT=$(just _free-port)
    qemu-system-x86_64 \
        -machine q35 -cpu qemu64 \
        -m 4G -smp 2 \
        -drive file={{UBUNTU_MULTILIB_QCOW}},if=virtio \
        -drive file=images/cloud-init-amd64-multilib.iso,if=virtio,media=cdrom \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -nographic
    just _banner "Ubuntu AMD64 multilib image ready"

# Download and provision FreeBSD AMD64 lib32 (vm 32-bit builds)
#
# nuageinit only runs on first boot of a fresh image — it has no concept of
# re-running for a new instance-id like Python cloud-init does. So provision
# always starts from a pristine qcow2 by re-extracting the cached .xz.
[group('Provision')]
provision-freebsd-amd64-lib32:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images
    xz_cache="images/freebsd-amd64.qcow2.xz"
    if [ ! -f "$xz_cache" ]; then
        just _action "Downloading FreeBSD AMD64 cloud-init image"
        curl -L -o "$xz_cache" "{{FREEBSD_AMD64_URL}}"
    else
        echo "Cached download already exists: $xz_cache"
    fi
    just _action "Extracting fresh qcow2 from cached download"
    rm -f "{{FREEBSD_LIB32_QCOW}}"
    xz -dk -c "$xz_cache" > "{{FREEBSD_LIB32_QCOW}}"
    qemu-img resize "{{FREEBSD_LIB32_QCOW}}" 20G
    just _create-cloud-init-freebsd-amd64-lib32
    just _action "Provisioning FreeBSD AMD64 lib32 via cloud-init"
    PORT=$(just _free-port)
    qemu-system-x86_64 \
        -machine q35 -cpu qemu64 \
        -m 4G -smp 2 \
        -drive file={{FREEBSD_LIB32_QCOW}},if=virtio \
        -drive file=images/cloud-init-freebsd-amd64-lib32.iso,if=ide,media=cdrom \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -pidfile freebsd-amd64-lib32-provision.pid \
        -display none -daemonize
    just _action "Waiting for nuageinit to finish (sshd will come up when done)"
    just _wait-for-ssh "$PORT"
    just _action "Provisioning complete — shutting down VM via SSH"
    just _stop-vm freebsd-amd64-lib32-provision.pid "$PORT"
    just _banner "FreeBSD AMD64 lib32 image ready"

# Download and provision FreeBSD ARM64 (vm64; hvf-accelerated on Apple Silicon)
#
# Same nuageinit-on-first-boot constraint as the amd64 image: always re-extract
# a pristine qcow2 from the cached .xz.
[group('Provision')]
provision-freebsd-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images
    xz_cache="images/freebsd-arm64.qcow2.xz"
    if [ ! -f "$xz_cache" ]; then
        just _action "Downloading FreeBSD ARM64 cloud-init image"
        curl -L -o "$xz_cache" "{{FREEBSD_ARM64_URL}}"
    else
        echo "Cached download already exists: $xz_cache"
    fi
    just _action "Extracting fresh qcow2 from cached download"
    rm -f "{{FREEBSD_ARM64_QCOW}}"
    xz -dk -c "$xz_cache" > "{{FREEBSD_ARM64_QCOW}}"
    qemu-img resize "{{FREEBSD_ARM64_QCOW}}" 20G
    just _create-cloud-init-freebsd-arm64
    just _action "Provisioning FreeBSD ARM64 via cloud-init"
    PORT=$(just _free-port)
    qemu-system-aarch64 \
        -machine virt -accel hvf -cpu host \
        -m 4G -smp 4 \
        -drive file={{FREEBSD_ARM64_QCOW}},if=virtio \
        -drive file=images/cloud-init-freebsd-arm64.iso,if=virtio,media=cdrom \
        -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -pidfile freebsd-arm64-provision.pid \
        -display none -daemonize
    just _action "Waiting for nuageinit to finish (sshd will come up when done)"
    just _wait-for-ssh "$PORT"
    just _action "Provisioning complete — shutting down VM via SSH"
    just _stop-vm freebsd-arm64-provision.pid "$PORT"
    just _banner "FreeBSD ARM64 image ready"

# Download and provision FreeBSD AMD64 (vm64; TCG-emulated)
#
# Shares the cached freebsd-amd64.qcow2.xz with provision-freebsd-amd64-lib32
# but extracts into its own qcow2 with vm64-only cloud-init (no chroot).
[group('Provision')]
provision-freebsd-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images
    xz_cache="images/freebsd-amd64.qcow2.xz"
    if [ ! -f "$xz_cache" ]; then
        just _action "Downloading FreeBSD AMD64 cloud-init image"
        curl -L -o "$xz_cache" "{{FREEBSD_AMD64_URL}}"
    else
        echo "Cached download already exists: $xz_cache"
    fi
    just _action "Extracting fresh qcow2 from cached download"
    rm -f "{{FREEBSD_AMD64_QCOW}}"
    xz -dk -c "$xz_cache" > "{{FREEBSD_AMD64_QCOW}}"
    qemu-img resize "{{FREEBSD_AMD64_QCOW}}" 20G
    just _create-cloud-init-freebsd-amd64
    just _action "Provisioning FreeBSD AMD64 via cloud-init"
    PORT=$(just _free-port)
    qemu-system-x86_64 \
        -machine q35 -cpu qemu64 \
        -m 4G -smp 2 \
        -drive file={{FREEBSD_AMD64_QCOW}},if=virtio \
        -drive file=images/cloud-init-freebsd-amd64.iso,if=ide,media=cdrom \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -pidfile freebsd-amd64-provision.pid \
        -display none -daemonize
    just _action "Waiting for nuageinit to finish (sshd will come up when done)"
    just _wait-for-ssh "$PORT"
    just _action "Provisioning complete — shutting down VM via SSH"
    just _stop-vm freebsd-amd64-provision.pid "$PORT"
    just _banner "FreeBSD AMD64 image ready"

# Download and provision NetBSD i386 (vm 32-bit, via Anita run through uvx)
#
# NetBSD doesn't publish a qcow2 or cloud-init image. Anita
# (https://github.com/gson1703/anita) is the NetBSD community's
# automated-installation tool: it drives sysinst over the serial console,
# then runs our --run pipeline to configure the ci user and install build
# deps. Output is a raw wd0.img that we convert to qcow2 for snapshot boots.
#
# We invoke anita via `uvx --from git+...` — uv fetches anita into an
# ephemeral venv and runs it in one shot, so the only host-side dependency
# is uv itself (brew install uv). No persistent pipx/uv install required.
[group('Provision')]
provision-netbsd-i386:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images
    workdir="images/netbsd-i386-anita"
    #
    # Phase A: anita install + minimal --run (user, root pw, sshd, network, keygen).
    # No pkgin here — pkgsrc mirror stalls during anita's expect-driven boot kill
    # the whole install.
    #
    just _action "Phase A: anita install (minimal --run)"
    uvx --from git+https://github.com/gson1703/anita.git --with pexpect anita \
        --workdir "$workdir" \
        --disk-size 20G \
        --memory-size 2G \
        --persist \
        --sets kern-GENERIC,modules,base,etc,comp,xbase,xcomp \
        --run '{ (useradd -m -G wheel -s /bin/sh -p "$(openssl passwd -1 ci)" ci || true) && echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && echo sshd=YES >> /etc/rc.conf && echo dhcpcd=YES >> /etc/rc.conf && echo ifconfig_wm0=dhcp >> /etc/rc.conf && ssh-keygen -A && dhcpcd wm0 && export PKG_PATH=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/i386/10.0/All && pkg_add sudo && mkdir -p /usr/pkg/etc && echo "ci ALL=(ALL) NOPASSWD: ALL" > /usr/pkg/etc/sudoers && echo "ci ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers; }; echo PROVISION_EXIT=$?' \
        boot \
        "{{NETBSD_I386_URL}}"
    just _action "Converting wd0.img → qcow2"
    rm -f "{{NETBSD_I386_QCOW}}"
    qemu-img convert -f raw -O qcow2 "$workdir/wd0.img" "{{NETBSD_I386_QCOW}}"
    #
    # Phase B: boot the qcow2 normally (persistent writes), ssh in as root, run
    # pkgin install. If this fails, re-run this recipe — anita is skipped
    # because its workdir cache is intact, and only Phase B repeats.
    #
    just _action "Phase B: booting qcow2 to install pkgsrc packages"
    PORT=$(just _free-port)
    # Always clean up Phase B qemu on exit (success or failure) so a mid-run
    # error doesn't leave a daemonized qemu locking the pidfile.
    trap '[ -f netbsd-i386-provision.pid ] && kill "$(cat netbsd-i386-provision.pid)" 2>/dev/null; rm -f netbsd-i386-provision.pid' EXIT
    qemu-system-x86_64 \
        -machine q35 -cpu qemu64 \
        -m 2G -smp 2 \
        -drive file={{NETBSD_I386_QCOW}},if=virtio \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -pidfile netbsd-i386-provision.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _action "Installing pkgsrc packages via SSH as root"
    sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -p "$PORT" ci@localhost \
        'export PATH=/usr/sbin:/sbin:/usr/bin:/bin:/usr/pkg/sbin:/usr/pkg/bin && export PKG_PATH=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/i386/10.0/All && (ifconfig wm0 | grep -q "inet " || sudo dhcpcd wm0) && sudo env PKG_PATH=$PKG_PATH pkg_add pkgin && echo "$PKG_PATH" | sudo tee /usr/pkg/etc/pkgin/repositories.conf > /dev/null && sudo env PKG_PATH=$PKG_PATH pkgin -y update && sudo env PKG_PATH=$PKG_PATH pkgin -y install cmake gcc12 rsync jemalloc bash vim-share'
    just _action "Shutting down VM"
    just _stop-vm netbsd-i386-provision.pid "$PORT"
    just _banner "NetBSD i386 image ready"

# Download and provision NetBSD AMD64 (vm64, via Anita run through uvx)
#
# Same two-phase approach as netbsd-i386: anita drives sysinst over the serial
# console for Phase A (user, sshd, network, sudo); Phase B SSHes in to run
# pkgin and install build deps. Re-running this recipe re-uses anita's workdir
# cache and only repeats Phase B if Phase A already completed.
[group('Provision')]
provision-netbsd-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images
    workdir="images/netbsd-amd64-anita"
    #
    # Phase A: anita install + minimal --run (user, root pw, sshd, network, keygen).
    # No pkgin here — pkgsrc mirror stalls during anita's expect-driven boot kill
    # the whole install.
    #
    just _action "Phase A: anita install (minimal --run)"
    uvx --from git+https://github.com/gson1703/anita.git --with pexpect anita \
        --workdir "$workdir" \
        --disk-size 20G \
        --memory-size 2G \
        --persist \
        --sets kern-GENERIC,modules,base,etc,comp,xbase,xcomp \
        --run '{ (useradd -m -G wheel -s /bin/sh -p "$(openssl passwd -1 ci)" ci || true) && echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && echo sshd=YES >> /etc/rc.conf && echo dhcpcd=YES >> /etc/rc.conf && echo ifconfig_wm0=dhcp >> /etc/rc.conf && ssh-keygen -A && dhcpcd wm0 && export PKG_PATH=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/amd64/10.0/All && pkg_add sudo && mkdir -p /usr/pkg/etc && echo "ci ALL=(ALL) NOPASSWD: ALL" > /usr/pkg/etc/sudoers && echo "ci ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers; }; echo PROVISION_EXIT=$?' \
        boot \
        "{{NETBSD_AMD64_URL}}"
    just _action "Converting wd0.img → qcow2"
    rm -f "{{NETBSD_AMD64_QCOW}}"
    qemu-img convert -f raw -O qcow2 "$workdir/wd0.img" "{{NETBSD_AMD64_QCOW}}"
    #
    # Phase B: boot the qcow2 normally (persistent writes), ssh in as root, run
    # pkgin install. If this fails, re-run this recipe — anita is skipped
    # because its workdir cache is intact, and only Phase B repeats.
    #
    just _action "Phase B: booting qcow2 to install pkgsrc packages"
    PORT=$(just _free-port)
    # Always clean up Phase B qemu on exit (success or failure) so a mid-run
    # error doesn't leave a daemonized qemu locking the pidfile.
    trap '[ -f netbsd-amd64-provision.pid ] && kill "$(cat netbsd-amd64-provision.pid)" 2>/dev/null; rm -f netbsd-amd64-provision.pid' EXIT
    qemu-system-x86_64 \
        -machine q35 -cpu qemu64 \
        -m 4G -smp 2 \
        -drive file={{NETBSD_AMD64_QCOW}},if=virtio \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -pidfile netbsd-amd64-provision.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _action "Installing pkgsrc packages via SSH as root"
    sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -p "$PORT" ci@localhost \
        'export PATH=/usr/sbin:/sbin:/usr/bin:/bin:/usr/pkg/sbin:/usr/pkg/bin && export PKG_PATH=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/amd64/10.0/All && (ifconfig wm0 | grep -q "inet " || sudo dhcpcd wm0) && sudo env PKG_PATH=$PKG_PATH pkg_add pkgin && echo "$PKG_PATH" | sudo tee /usr/pkg/etc/pkgin/repositories.conf > /dev/null && sudo env PKG_PATH=$PKG_PATH pkgin -y update && sudo env PKG_PATH=$PKG_PATH pkgin -y install cmake gcc12 rsync jemalloc bash vim-share'
    just _action "Shutting down VM"
    just _stop-vm netbsd-amd64-provision.pid "$PORT"
    just _banner "NetBSD AMD64 image ready"

# ═══════════════════════════════════════════════════════════
#  Environment
# ═══════════════════════════════════════════════════════════

# Verify required tools are installed
[group('Environment')]
check-env:
    #!/usr/bin/env bash
    set -euo pipefail
    just _action "Checking required tools"
    ok=true

    hint() {
        case "$1" in
            cmake)                echo "brew install cmake" ;;
            curl)                 echo "brew install curl" ;;
            expect)               echo "brew install expect" ;;
            gunzip)               echo "included with gzip — brew install gzip" ;;
            python3)              echo "brew install python3" ;;
            qemu-img)             echo "brew install qemu" ;;
            qemu-system-aarch64)  echo "brew install qemu" ;;
            qemu-system-x86_64)   echo "brew install qemu" ;;
            rsync)                echo "brew install rsync" ;;
            ssh)                  echo "should be pre-installed on macOS" ;;
            sshpass)              echo "brew install esolitos/ipa/sshpass" ;;
            uv)                   echo "brew install uv  (used to run anita for NetBSD provisioning)" ;;
            xxd)                  echo "included with vim — brew install vim" ;;
            xz)                   echo "brew install xz" ;;
        esac
    }

    for cmd in cmake curl expect gunzip python3 qemu-img qemu-system-aarch64 qemu-system-x86_64 rsync ssh sshpass uv xxd xz; do
        if command -v "$cmd" &>/dev/null; then
            printf "  %-30s %s\n" "$cmd" "$(command -v "$cmd")"
        else
            printf "  %-30s MISSING  (%s)\n" "$cmd" "$(hint "$cmd")"
            ok=false
        fi
    done

    echo ""
    echo "Checking firmware files:"
    EFI="/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
    if [ -f "$EFI" ]; then
        printf "  %-30s OK\n" "edk2-aarch64-code.fd"
    else
        printf "  %-30s MISSING  (brew install qemu)\n" "edk2-aarch64-code.fd"
        ok=false
    fi

    echo ""
    echo "Host CPUs: {{NCPU}}"
    if [ -n "{{SELFSRC}}" ]; then
        echo "SELFSRC: {{SELFSRC}}"
        if [ -d "{{SRCDIR}}" ]; then
            echo "Source tree: {{SRCDIR}} (OK)"
        else
            echo "Source tree: {{SRCDIR}} (NOT FOUND)"
        fi
    else
        echo "SELFSRC: (not set)"
    fi
    echo ""
    echo "Available source trees in src/:"
    ls -1 "{{justfile_directory()}}/src" 2>/dev/null | sed 's/^/  /' || echo "  (none — create src/ and add a source tree)"
    if $ok; then
        just _pass "Environment OK"
    else
        just _fail "Some required tools are missing"
        exit 1
    fi

# ═══════════════════════════════════════════════════════════
#  Advanced — Start/Stop individual VMs
# ═══════════════════════════════════════════════════════════

# Boot Ubuntu ARM64 VM (snapshot mode)
[group('Advanced')]
start-ubuntu-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    just _action "Starting Ubuntu ARM64 VM"
    PORT=$(just _free-port)
    echo "$PORT" > ubuntu-arm64.port
    qemu-system-aarch64 \
        -machine virt -accel hvf -cpu host \
        -m 4G -smp 4 \
        -drive file={{UBUNTU_ARM64_QCOW}},if=virtio,snapshot=on \
        -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -pidfile ubuntu-arm64.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _banner "Ubuntu ARM64 VM running on port $PORT"

# Shut down Ubuntu ARM64 VM
[group('Advanced')]
stop-ubuntu-arm64:
    #!/usr/bin/env bash
    port=$(cat ubuntu-arm64.port 2>/dev/null || echo "0")
    just _stop-vm ubuntu-arm64.pid "$port"
    rm -f ubuntu-arm64.port

# Boot Ubuntu AMD64 VM (snapshot mode)
[group('Advanced')]
start-ubuntu-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    just _action "Starting Ubuntu AMD64 VM"
    PORT=$(just _free-port)
    echo "$PORT" > ubuntu-amd64.port
    qemu-system-x86_64 \
        -machine q35 -cpu qemu64 \
        -m 4G -smp 2 \
        -drive file={{UBUNTU_AMD64_QCOW}},if=virtio,snapshot=on \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -pidfile ubuntu-amd64.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _banner "Ubuntu AMD64 VM running on port $PORT"

# Shut down Ubuntu AMD64 VM
[group('Advanced')]
stop-ubuntu-amd64:
    #!/usr/bin/env bash
    port=$(cat ubuntu-amd64.port 2>/dev/null || echo "0")
    just _stop-vm ubuntu-amd64.pid "$port"
    rm -f ubuntu-amd64.port

# Boot Ubuntu AMD64 multilib VM (snapshot mode, for 32-bit vm builds)
[group('Advanced')]
start-ubuntu-amd64-multilib:
    #!/usr/bin/env bash
    set -euo pipefail
    just _action "Starting Ubuntu AMD64 multilib VM"
    PORT=$(just _free-port)
    echo "$PORT" > ubuntu-amd64-multilib.port
    qemu-system-x86_64 \
        -machine q35 -cpu qemu64 \
        -m 4G -smp 2 \
        -drive file={{UBUNTU_MULTILIB_QCOW}},if=virtio,snapshot=on \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -pidfile ubuntu-amd64-multilib.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _banner "Ubuntu AMD64 multilib VM running on port $PORT"

# Shut down Ubuntu AMD64 multilib VM
[group('Advanced')]
stop-ubuntu-amd64-multilib:
    #!/usr/bin/env bash
    port=$(cat ubuntu-amd64-multilib.port 2>/dev/null || echo "0")
    just _stop-vm ubuntu-amd64-multilib.pid "$port"
    rm -f ubuntu-amd64-multilib.port

# Boot FreeBSD AMD64 lib32 VM (snapshot mode, for 32-bit vm builds)
[group('Advanced')]
start-freebsd-amd64-lib32:
    #!/usr/bin/env bash
    set -euo pipefail
    just _action "Starting FreeBSD AMD64 lib32 VM"
    PORT=$(just _free-port)
    echo "$PORT" > freebsd-amd64-lib32.port
    qemu-system-x86_64 \
        -machine q35 -cpu qemu64 \
        -m 4G -smp 2 \
        -drive file={{FREEBSD_LIB32_QCOW}},if=virtio,snapshot=on \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -pidfile freebsd-amd64-lib32.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _banner "FreeBSD AMD64 lib32 VM running on port $PORT"

# Shut down FreeBSD AMD64 lib32 VM
[group('Advanced')]
stop-freebsd-amd64-lib32:
    #!/usr/bin/env bash
    port=$(cat freebsd-amd64-lib32.port 2>/dev/null || echo "0")
    just _stop-vm freebsd-amd64-lib32.pid "$port"
    rm -f freebsd-amd64-lib32.port

# Boot FreeBSD ARM64 VM (snapshot mode, hvf-accelerated)
[group('Advanced')]
start-freebsd-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    just _action "Starting FreeBSD ARM64 VM"
    PORT=$(just _free-port)
    echo "$PORT" > freebsd-arm64.port
    qemu-system-aarch64 \
        -machine virt -accel hvf -cpu host \
        -m 4G -smp 4 \
        -drive file={{FREEBSD_ARM64_QCOW}},if=virtio,snapshot=on \
        -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -pidfile freebsd-arm64.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _banner "FreeBSD ARM64 VM running on port $PORT"

# Shut down FreeBSD ARM64 VM
[group('Advanced')]
stop-freebsd-arm64:
    #!/usr/bin/env bash
    port=$(cat freebsd-arm64.port 2>/dev/null || echo "0")
    just _stop-vm freebsd-arm64.pid "$port"
    rm -f freebsd-arm64.port

# Boot FreeBSD AMD64 VM (snapshot mode, TCG-emulated, for vm64)
[group('Advanced')]
start-freebsd-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    just _action "Starting FreeBSD AMD64 VM"
    PORT=$(just _free-port)
    echo "$PORT" > freebsd-amd64.port
    qemu-system-x86_64 \
        -machine q35 -cpu qemu64 \
        -m 4G -smp 2 \
        -drive file={{FREEBSD_AMD64_QCOW}},if=virtio,snapshot=on \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -pidfile freebsd-amd64.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _banner "FreeBSD AMD64 VM running on port $PORT"

# Shut down FreeBSD AMD64 VM
[group('Advanced')]
stop-freebsd-amd64:
    #!/usr/bin/env bash
    port=$(cat freebsd-amd64.port 2>/dev/null || echo "0")
    just _stop-vm freebsd-amd64.pid "$port"
    rm -f freebsd-amd64.port

# Boot NetBSD i386 VM (snapshot mode, TCG-emulated, for vm32)
[group('Advanced')]
start-netbsd-i386:
    #!/usr/bin/env bash
    set -euo pipefail
    just _action "Starting NetBSD i386 VM"
    PORT=$(just _free-port)
    echo "$PORT" > netbsd-i386.port
    qemu-system-x86_64 \
        -machine q35 -cpu qemu64 \
        -m 2G -smp 2 \
        -drive file={{NETBSD_I386_QCOW}},if=virtio,snapshot=on \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -pidfile netbsd-i386.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _banner "NetBSD i386 VM running on port $PORT"

# Shut down NetBSD i386 VM
[group('Advanced')]
stop-netbsd-i386:
    #!/usr/bin/env bash
    port=$(cat netbsd-i386.port 2>/dev/null || echo "0")
    just _stop-vm netbsd-i386.pid "$port"
    rm -f netbsd-i386.port

# Boot NetBSD AMD64 VM (snapshot mode, TCG-emulated, for vm64)
[group('Advanced')]
start-netbsd-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    just _action "Starting NetBSD AMD64 VM"
    PORT=$(just _free-port)
    echo "$PORT" > netbsd-amd64.port
    qemu-system-x86_64 \
        -machine q35 -cpu qemu64 \
        -m 4G -smp 2 \
        -drive file={{NETBSD_AMD64_QCOW}},if=virtio,snapshot=on \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -pidfile netbsd-amd64.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _banner "NetBSD AMD64 VM running on port $PORT"

# Shut down NetBSD AMD64 VM
[group('Advanced')]
stop-netbsd-amd64:
    #!/usr/bin/env bash
    port=$(cat netbsd-amd64.port 2>/dev/null || echo "0")
    just _stop-vm netbsd-amd64.pid "$port"
    rm -f netbsd-amd64.port

# Execute command on a running VM via SSH
[group('Advanced')]
do port *ARGS:
    #!/usr/bin/env bash
    cat <<'JUSTEOF'
    > {{ARGS}}
    JUSTEOF
    hex_string=$(xxd -p <<'JUSTEOF' | tr -d '\n'
    {{ARGS}}
    JUSTEOF
    )
    CMD="echo $hex_string | xxd -r -p > /tmp/qemu_cmd ; bash --login /tmp/qemu_cmd"
    sshpass -p ci ssh ci@localhost -p {{port}} \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR "($CMD) 2>&1"

# Attach an interactive terminal to a running VM via SSH
[group('Advanced')]
term port:
    sshpass -p ci ssh -t ci@localhost -p {{port}} \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR

# Delete all images and logs
[group('Advanced')]
reset-everything:
    rm -rf images/ logs/ build/
    rm -f *.pid *.port
    @just _banner "All images, logs, and builds deleted"

# ═══════════════════════════════════════════════════════════
#  Support recipes (internal)
# ═══════════════════════════════════════════════════════════

_free-port:
    @python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()'

_rsync port:
    #!/usr/bin/env bash
    just _check-src
    unset DISPLAY SSH_ASKPASS
    rsync -az --copy-unsafe-links --delete \
        -e "sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p {{port}}" \
        --exclude='build-*/' --exclude='build/' \
        --exclude='*.o' --exclude='*.snap' --exclude='*.snap64' \
        "{{SRCDIR}}/" ci@localhost:/tmp/self-build/

_wait-for-ssh port:
    #!/usr/bin/env bash
    for i in $(seq 1 180); do
        if sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 -o LogLevel=ERROR -p {{port}} ci@localhost "echo ready" 2>/dev/null; then
            exit 0
        fi
        sleep 2
    done
    echo "ERROR: SSH not available on port {{port}} after 360 seconds"
    exit 1

_stop-vm pidfile port:
    #!/usr/bin/env bash
    sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -p {{port}} ci@localhost "sudo sync; sudo sync; sudo poweroff" 2>/dev/null || true
    if [ -f {{pidfile}} ]; then
        pid=$(cat {{pidfile}})
        for i in $(seq 1 120); do
            ps -p "$pid" > /dev/null 2>&1 || break
            sleep 1
        done
        kill "$pid" 2>/dev/null || true
        rm -f {{pidfile}}
    fi

_create-cloud-init-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    iso="images/cloud-init-arm64.iso"
    [ -f "$iso" ] && exit 0
    mkdir -p images
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    cat > "$tmpdir/meta-data" <<'EOF'
    instance-id: ci-vm-arm64
    local-hostname: ci-vm-arm64
    EOF
    cat > "$tmpdir/user-data" <<'EOF'
    #cloud-config
    users:
      - name: ci
        plain_text_passwd: ci
        lock_passwd: false
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        ssh_authorized_keys: []

    ssh_pwauth: true

    package_update: true
    packages:
      - cmake
      - g++
      - libx11-dev
      - libxext-dev
      - libncurses-dev
      - rsync

    runcmd:
      - systemctl enable ssh
      - systemctl start ssh

    power_state:
      mode: poweroff
      message: "Provisioning complete, shutting down"
      condition: true
    EOF
    if command -v mkisofs &>/dev/null; then
        mkisofs -output "$iso" -volid cidata -joliet -rock "$tmpdir/user-data" "$tmpdir/meta-data"
    elif command -v hdiutil &>/dev/null; then
        mkdir -p "$tmpdir/iso_root"
        cp "$tmpdir/user-data" "$tmpdir/meta-data" "$tmpdir/iso_root/"
        hdiutil makehybrid -iso -joliet -iso-volume-name cidata -o "$iso" "$tmpdir/iso_root/"
        [ -f "${iso}.iso" ] && mv "${iso}.iso" "$iso"
    else
        echo "ERROR: Cannot create cloud-init ISO (no mkisofs or hdiutil)"
        echo "Install cdrtools: brew install cdrtools"
        exit 1
    fi
    echo "Created cloud-init ISO: $iso"

_create-cloud-init-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    iso="images/cloud-init-amd64.iso"
    [ -f "$iso" ] && exit 0
    mkdir -p images
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    cat > "$tmpdir/meta-data" <<'EOF'
    instance-id: ci-vm-amd64
    local-hostname: ci-vm-amd64
    EOF
    cat > "$tmpdir/user-data" <<'EOF'
    #cloud-config
    users:
      - name: ci
        plain_text_passwd: ci
        lock_passwd: false
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        ssh_authorized_keys: []

    ssh_pwauth: true

    package_update: true
    packages:
      - cmake
      - g++
      - libx11-dev
      - libxext-dev
      - libncurses-dev
      - rsync

    runcmd:
      - systemctl enable ssh
      - systemctl start ssh

    power_state:
      mode: poweroff
      message: "Provisioning complete, shutting down"
      condition: true
    EOF
    if command -v mkisofs &>/dev/null; then
        mkisofs -output "$iso" -volid cidata -joliet -rock "$tmpdir/user-data" "$tmpdir/meta-data"
    elif command -v hdiutil &>/dev/null; then
        mkdir -p "$tmpdir/iso_root"
        cp "$tmpdir/user-data" "$tmpdir/meta-data" "$tmpdir/iso_root/"
        hdiutil makehybrid -iso -joliet -iso-volume-name cidata -o "$iso" "$tmpdir/iso_root/"
        [ -f "${iso}.iso" ] && mv "${iso}.iso" "$iso"
    else
        echo "ERROR: Cannot create cloud-init ISO (no mkisofs or hdiutil)"
        echo "Install cdrtools: brew install cdrtools"
        exit 1
    fi
    echo "Created cloud-init ISO: $iso"

_create-cloud-init-amd64-multilib:
    #!/usr/bin/env bash
    set -euo pipefail
    iso="images/cloud-init-amd64-multilib.iso"
    [ -f "$iso" ] && exit 0
    mkdir -p images
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    cat > "$tmpdir/meta-data" <<'EOF'
    instance-id: ci-vm-amd64-multilib
    local-hostname: ci-vm-amd64-multilib
    EOF
    cat > "$tmpdir/user-data" <<'EOF'
    #cloud-config
    users:
      - name: ci
        plain_text_passwd: ci
        lock_passwd: false
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        ssh_authorized_keys: []

    ssh_pwauth: true

    bootcmd:
      - dpkg --add-architecture i386

    package_update: true
    packages:
      - cmake
      - g++
      - pkg-config
      - rsync
      - gcc-multilib
      - g++-multilib

    runcmd:
      - apt-get install -y libx11-dev:i386 libxext-dev:i386 libncurses-dev:i386
      - systemctl enable ssh
      - systemctl start ssh

    power_state:
      mode: poweroff
      message: "Provisioning complete, shutting down"
      condition: true
    EOF
    if command -v mkisofs &>/dev/null; then
        mkisofs -output "$iso" -volid cidata -joliet -rock "$tmpdir/user-data" "$tmpdir/meta-data"
    elif command -v hdiutil &>/dev/null; then
        mkdir -p "$tmpdir/iso_root"
        cp "$tmpdir/user-data" "$tmpdir/meta-data" "$tmpdir/iso_root/"
        hdiutil makehybrid -iso -joliet -iso-volume-name cidata -o "$iso" "$tmpdir/iso_root/"
        [ -f "${iso}.iso" ] && mv "${iso}.iso" "$iso"
    else
        echo "ERROR: Cannot create cloud-init ISO (no mkisofs or hdiutil)"
        echo "Install cdrtools: brew install cdrtools"
        exit 1
    fi
    echo "Created cloud-init ISO: $iso"

_create-cloud-init-freebsd-amd64-lib32:
    #!/usr/bin/env bash
    set -euo pipefail
    iso="images/cloud-init-freebsd-amd64-lib32.iso"
    rm -f "$iso"
    mkdir -p images
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    instance_id="ci-vm-freebsd-amd64-lib32-$(date +%s)"
    cat > "$tmpdir/meta-data" <<EOF
    instance-id: $instance_id
    local-hostname: ci-vm-freebsd-amd64-lib32
    EOF
    cat > "$tmpdir/user-data" <<'EOF'
    #cloud-config
    users:
      - name: ci
        plain_text_passwd: ci
        lock_passwd: false
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/sh
        ssh_authorized_keys: []

    ssh_pwauth: true

    package_update: true
    packages:
      - rsync
      - bash
      - xxd
      - sudo

    runcmd:
      - ssh-keygen -A
      - sed -i '' 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
      - sysrc sshd_enable=YES
      - fetch -o /tmp/base.txz https://download.freebsd.org/releases/i386/14.4-RELEASE/base.txz
      - mkdir -p /compat/i386
      - tar -xf /tmp/base.txz -C /compat/i386
      - rm /tmp/base.txz
      - cp /etc/resolv.conf /compat/i386/etc/resolv.conf
      - echo 'devfs /compat/i386/dev devfs rw 0 0' >> /etc/fstab
      - echo '/tmp /compat/i386/tmp nullfs rw 0 0' >> /etc/fstab
      - mount /compat/i386/dev
      - mount /compat/i386/tmp
      - env IGNORE_OSVERSION=yes chroot /compat/i386 /bin/sh -c 'env ASSUME_ALWAYS_YES=yes IGNORE_OSVERSION=yes pkg bootstrap -y'
      - env IGNORE_OSVERSION=yes chroot /compat/i386 /bin/sh -c 'env ASSUME_ALWAYS_YES=yes IGNORE_OSVERSION=yes pkg install -y gcc cmake pkgconf rsync libX11 libXext xorgproto'
      - service sshd start
    EOF
    if command -v mkisofs &>/dev/null; then
        mkisofs -output "$iso" -volid cidata -joliet -rock "$tmpdir/user-data" "$tmpdir/meta-data"
    elif command -v hdiutil &>/dev/null; then
        mkdir -p "$tmpdir/iso_root"
        cp "$tmpdir/user-data" "$tmpdir/meta-data" "$tmpdir/iso_root/"
        hdiutil makehybrid -iso -joliet -iso-volume-name cidata -o "$iso" "$tmpdir/iso_root/"
        [ -f "${iso}.iso" ] && mv "${iso}.iso" "$iso"
    else
        echo "ERROR: Cannot create cloud-init ISO (no mkisofs or hdiutil)"
        echo "Install cdrtools: brew install cdrtools"
        exit 1
    fi
    echo "Created cloud-init ISO: $iso"

_create-cloud-init-freebsd-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    iso="images/cloud-init-freebsd-amd64.iso"
    rm -f "$iso"
    mkdir -p images
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    instance_id="ci-vm-freebsd-amd64-$(date +%s)"
    cat > "$tmpdir/meta-data" <<EOF
    instance-id: $instance_id
    local-hostname: ci-vm-freebsd-amd64
    EOF
    cat > "$tmpdir/user-data" <<'EOF'
    #cloud-config
    users:
      - name: ci
        plain_text_passwd: ci
        lock_passwd: false
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/sh
        ssh_authorized_keys: []

    ssh_pwauth: true

    package_update: true
    packages:
      - cmake
      - rsync
      - bash
      - xxd
      - pkgconf
      - sudo
      - libX11
      - libXext
      - ncurses

    runcmd:
      - ssh-keygen -A
      - sed -i '' 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
      - sysrc sshd_enable=YES
      - service sshd start
    EOF
    if command -v mkisofs &>/dev/null; then
        mkisofs -output "$iso" -volid cidata -joliet -rock "$tmpdir/user-data" "$tmpdir/meta-data"
    elif command -v hdiutil &>/dev/null; then
        mkdir -p "$tmpdir/iso_root"
        cp "$tmpdir/user-data" "$tmpdir/meta-data" "$tmpdir/iso_root/"
        hdiutil makehybrid -iso -joliet -iso-volume-name cidata -o "$iso" "$tmpdir/iso_root/"
        [ -f "${iso}.iso" ] && mv "${iso}.iso" "$iso"
    else
        echo "ERROR: Cannot create cloud-init ISO (no mkisofs or hdiutil)"
        echo "Install cdrtools: brew install cdrtools"
        exit 1
    fi
    echo "Created cloud-init ISO: $iso"

_create-cloud-init-freebsd-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    iso="images/cloud-init-freebsd-arm64.iso"
    rm -f "$iso"
    mkdir -p images
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    instance_id="ci-vm-freebsd-arm64-$(date +%s)"
    cat > "$tmpdir/meta-data" <<EOF
    instance-id: $instance_id
    local-hostname: ci-vm-freebsd-arm64
    EOF
    cat > "$tmpdir/user-data" <<'EOF'
    #cloud-config
    users:
      - name: ci
        plain_text_passwd: ci
        lock_passwd: false
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/sh
        ssh_authorized_keys: []

    ssh_pwauth: true

    package_update: true
    packages:
      - cmake
      - rsync
      - bash
      - xxd
      - pkgconf
      - sudo
      - libX11
      - libXext
      - ncurses

    runcmd:
      - ssh-keygen -A
      - sed -i '' 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
      - sysrc sshd_enable=YES
      - service sshd start
    EOF
    if command -v mkisofs &>/dev/null; then
        mkisofs -output "$iso" -volid cidata -joliet -rock "$tmpdir/user-data" "$tmpdir/meta-data"
    elif command -v hdiutil &>/dev/null; then
        mkdir -p "$tmpdir/iso_root"
        cp "$tmpdir/user-data" "$tmpdir/meta-data" "$tmpdir/iso_root/"
        hdiutil makehybrid -iso -joliet -iso-volume-name cidata -o "$iso" "$tmpdir/iso_root/"
        [ -f "${iso}.iso" ] && mv "${iso}.iso" "$iso"
    else
        echo "ERROR: Cannot create cloud-init ISO (no mkisofs or hdiutil)"
        echo "Install cdrtools: brew install cdrtools"
        exit 1
    fi
    echo "Created cloud-init ISO: $iso"

_pass *ARGS:
    @echo "$(tput setaf 2)$(tput bold)[$(date +%H:%M:%S)] PASS: {{ARGS}}$(tput sgr0)"

_fail *ARGS:
    @echo "$(tput setaf 1)$(tput bold)[$(date +%H:%M:%S)] FAIL: {{ARGS}}$(tput sgr0)"

_banner *ARGS:
    @echo "$(tput setaf 2)$(tput bold)[$(date +%H:%M:%S)] {{ARGS}}$(tput sgr0)"

_action *ARGS:
    @echo "$(tput setaf 208)$(tput bold)[$(date +%H:%M:%S)] {{ARGS}}$(tput sgr0)"
