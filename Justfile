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

# Never let ssh/scp fall back to an X11 askpass helper (XQuartz sets DISPLAY;
# the fallback bypasses sshpass and fails auth with "Permission denied").
export SSH_ASKPASS_REQUIRE := 'never'
SRCDIR := if SELFSRC == '' { '' } else { justfile_directory() + '/src/' + SELFSRC }
BUILD_MACOS := justfile_directory() + '/build/macos-native'
NCPU := `sysctl -n hw.ncpu 2>/dev/null || echo 4`

# Per-platform wall-clock timeout. Override via env, e.g. RUN_TIMEOUT_SECS=7200 just vm64-ubuntu-amd64
RUN_TIMEOUT_SECS := env('RUN_TIMEOUT_SECS', '7200')

# ─── Images ─────────────────────────────────────────────

# vm64 platforms
UBUNTU_ARM64_QCOW  := 'images/ubuntu-arm64.qcow2'
UBUNTU_AMD64_QCOW  := 'images/ubuntu-amd64.qcow2'
FREEBSD_ARM64_QCOW := 'images/freebsd-arm64.qcow2'
FREEBSD_AMD64_QCOW := 'images/freebsd-amd64.qcow2'
NETBSD_AMD64_QCOW  := 'images/netbsd-amd64.qcow2'
NETBSD_ARM64_QCOW  := 'images/netbsd-arm64.qcow2'
ALPINE_AMD64_QCOW  := 'images/alpine-amd64.qcow2'
ALPINE_ARM64_QCOW  := 'images/alpine-arm64.qcow2'

# vm platforms (32-bit, usually 64 bit host with multilib support)
UBUNTU_MULTILIB_QCOW  := 'images/ubuntu-amd64-multilib.qcow2'
FREEBSD_LIB32_QCOW := 'images/freebsd-amd64-lib32.qcow2'
NETBSD_I386_QCOW   := 'images/netbsd-i386.qcow2'
NETBSD_MACPPC_QCOW  := 'images/netbsd-macppc.qcow2'
NETBSD_SPARC64_QCOW := 'images/netbsd-sparc64.qcow2'
ALPINE_X86_QCOW     := 'images/alpine-x86.qcow2'

# ─── Download URLs ────────────────────────────────────────

UBUNTU_ARM64_URL   := 'https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img'
UBUNTU_AMD64_URL   := 'https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img'
FREEBSD_AMD64_URL  := 'https://download.freebsd.org/releases/VM-IMAGES/15.0-RELEASE/amd64/Latest/FreeBSD-15.0-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2.xz'
FREEBSD_ARM64_URL  := 'https://download.freebsd.org/releases/VM-IMAGES/15.0-RELEASE/aarch64/Latest/FreeBSD-15.0-RELEASE-arm64-aarch64-BASIC-CLOUDINIT-ufs.qcow2.xz'
NETBSD_I386_URL    := 'http://ftp.netbsd.org/pub/NetBSD/NetBSD-10.1/i386/'
NETBSD_AMD64_URL   := 'http://ftp.netbsd.org/pub/NetBSD/NetBSD-10.1/amd64/'
NETBSD_ARM64_URL   := 'http://ftp.netbsd.org/pub/NetBSD/NetBSD-10.1/evbarm-aarch64/'
NETBSD_MACPPC_URL   := 'http://ftp.netbsd.org/pub/NetBSD/NetBSD-10.1/macppc/'
NETBSD_SPARC64_URL  := 'http://ftp.netbsd.org/pub/NetBSD/NetBSD-10.1/images/NetBSD-10.1-sparc64.iso'
# Alpine ships no 32-bit cloud images (cloud/ is x86_64+aarch64 only), so x86
# is installed from the virt ISO by an expect script — see provision-alpine-x86.
ALPINE_X86_ISO_URL       := 'https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/x86/alpine-virt-3.24.1-x86.iso'
ALPINE_X86_COMMUNITY_URL := 'https://dl-cdn.alpinelinux.org/alpine/v3.24/community'
# 64-bit Alpine does have cloud images: the generic_* cloudinit qcow2s ship
# cloud-init with the default datasource list, so the NoCloud seed-ISO
# approach used for Ubuntu works as-is (see provision-alpine-amd64/-arm64).
ALPINE_AMD64_URL   := 'https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/cloud/generic_alpine-3.24.1-x86_64-bios-cloudinit-r0.qcow2'
ALPINE_ARM64_URL   := 'https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/cloud/generic_alpine-3.24.1-aarch64-uefi-cloudinit-r0.qcow2'

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

# Show the latest build report (artifacts/index.html) in the terminal
[group('Environment')]
status:
    #!/usr/bin/env bash
    set -euo pipefail
    just _generate-report >/dev/null
    report="{{justfile_directory()}}/artifacts/index.html"
    cols=$(tput cols 2>/dev/null || echo 120)
    if command -v links >/dev/null 2>&1; then
        links -dump -width "$cols" "$report"
    elif command -v lynx >/dev/null 2>&1; then
        lynx -dump -nolist -width "$cols" "$report"
    elif command -v w3m >/dev/null 2>&1; then
        w3m -dump -cols "$cols" "$report"
    else
        echo "No text browser found to render the report."
        echo "Install one (brew install links) or open it directly:"
        echo "  open $report"
        exit 1
    fi

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
    just vm64-alpine-arm64 && RESULTS+=("vm64-alpine-arm64: PASS") || { RESULTS+=("vm64-alpine-arm64: FAIL"); FAILS=$((FAILS + 1)); }

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
    just vm32-netbsd-macppc && RESULTS+=("vm32-netbsd-macppc: PASS") || { RESULTS+=("vm32-netbsd-macppc: FAIL"); FAILS=$((FAILS + 1)); }
    just vm32-netbsd-sparc64 && RESULTS+=("vm32-netbsd-sparc64: PASS") || { RESULTS+=("vm32-netbsd-sparc64: FAIL"); FAILS=$((FAILS + 1)); }

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
    set -euo pipefail
    NAME=vm64-macos-native
    mkdir -p "{{justfile_directory()}}/artifacts/logs"
    LOG="{{justfile_directory()}}/artifacts/logs/$NAME.log"
    : > "$LOG"
    START=$SECONDS
    TIMEOUT_MARK="{{justfile_directory()}}/artifacts/logs/$NAME.timeout"
    rm -f "$TIMEOUT_MARK"
    ( sleep {{RUN_TIMEOUT_SECS}}
      touch "$TIMEOUT_MARK"
      pkill -TERM -P $$ 2>/dev/null || true
      sleep 10
      pkill -KILL -P $$ 2>/dev/null || true
    ) &
    WATCHDOG=$!
    finalize() {
        local code=$?
        kill $WATCHDOG 2>/dev/null || true
        wait $WATCHDOG 2>/dev/null || true
        local elapsed=$((SECONDS - START))
        local label=FAIL
        if [ -f "$TIMEOUT_MARK" ]; then
            label=TIMEOUT
            rm -f "$TIMEOUT_MARK"
            echo "[$NAME] aborted after {{RUN_TIMEOUT_SECS}}s timeout" | tee -a "$LOG"
        fi
        if [ $code -eq 0 ]; then
            just _record-status "$NAME" PASS $elapsed Self-vm64-macos-arm64.app
            just _pass "$NAME"
        else
            just _record-status "$NAME" "$label" $elapsed ""
            just _fail "$NAME ($label)"
        fi
        just _generate-report
    }
    trap finalize EXIT
    just _check-src
    set +o pipefail
    just _vm64-compile-macos-native 2>&1 | tee -a "$LOG"
    result=${PIPESTATUS[0]}
    set -o pipefail
    if [ $result -eq 0 ]; then
        BUILD_DIR="{{BUILD_MACOS}}"
        mkdir -p "{{justfile_directory()}}/artifacts"
        cp -R "$BUILD_DIR/Self.app" "{{justfile_directory()}}/artifacts/Self-vm64-macos-arm64.app" || result=$?
    fi
    exit $result

# Build and test vm64 on Ubuntu ARM64
[group('vm64')]
vm64-ubuntu-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    NAME=vm64-ubuntu-arm64
    mkdir -p "{{justfile_directory()}}/artifacts/logs"
    LOG="{{justfile_directory()}}/artifacts/logs/$NAME.log"
    : > "$LOG"
    START=$SECONDS
    VM_UP=0
    TIMEOUT_MARK="{{justfile_directory()}}/artifacts/logs/$NAME.timeout"
    rm -f "$TIMEOUT_MARK"
    ( sleep {{RUN_TIMEOUT_SECS}}
      touch "$TIMEOUT_MARK"
      pkill -TERM -P $$ 2>/dev/null || true
      sleep 10
      pkill -KILL -P $$ 2>/dev/null || true
    ) &
    WATCHDOG=$!
    finalize() {
        local code=$?
        kill $WATCHDOG 2>/dev/null || true
        wait $WATCHDOG 2>/dev/null || true
        [ $VM_UP -eq 1 ] && just stop-ubuntu-arm64 2>/dev/null || true
        local elapsed=$((SECONDS - START))
        local label=FAIL
        if [ -f "$TIMEOUT_MARK" ]; then
            label=TIMEOUT
            rm -f "$TIMEOUT_MARK"
            echo "[$NAME] aborted after {{RUN_TIMEOUT_SECS}}s timeout" | tee -a "$LOG"
        fi
        if [ $code -eq 0 ]; then
            just _record-status "$NAME" PASS $elapsed "Self-$NAME"
            just _pass "$NAME"
        else
            just _record-status "$NAME" "$label" $elapsed ""
            just _fail "$NAME ($label)"
        fi
        just _generate-report
    }
    trap finalize EXIT
    just _check-src
    just start-ubuntu-arm64 2>&1 | tee -a "$LOG"
    VM_UP=1
    PORT=$(cat ubuntu-arm64.port)
    set +o pipefail
    just _vm64-compile-ubuntu-arm64 "$PORT" 2>&1 | tee -a "$LOG"
    result=${PIPESTATUS[0]}
    set -o pipefail
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-$NAME" || result=$?
    fi
    exit $result

# Build and test vm64 on Ubuntu AMD64
[group('vm64')]
vm64-ubuntu-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    NAME=vm64-ubuntu-amd64
    mkdir -p "{{justfile_directory()}}/artifacts/logs"
    LOG="{{justfile_directory()}}/artifacts/logs/$NAME.log"
    : > "$LOG"
    START=$SECONDS
    VM_UP=0
    TIMEOUT_MARK="{{justfile_directory()}}/artifacts/logs/$NAME.timeout"
    rm -f "$TIMEOUT_MARK"
    ( sleep {{RUN_TIMEOUT_SECS}}
      touch "$TIMEOUT_MARK"
      pkill -TERM -P $$ 2>/dev/null || true
      sleep 10
      pkill -KILL -P $$ 2>/dev/null || true
    ) &
    WATCHDOG=$!
    finalize() {
        local code=$?
        kill $WATCHDOG 2>/dev/null || true
        wait $WATCHDOG 2>/dev/null || true
        [ $VM_UP -eq 1 ] && just stop-ubuntu-amd64 2>/dev/null || true
        local elapsed=$((SECONDS - START))
        local label=FAIL
        if [ -f "$TIMEOUT_MARK" ]; then
            label=TIMEOUT
            rm -f "$TIMEOUT_MARK"
            echo "[$NAME] aborted after {{RUN_TIMEOUT_SECS}}s timeout" | tee -a "$LOG"
        fi
        if [ $code -eq 0 ]; then
            just _record-status "$NAME" PASS $elapsed "Self-$NAME"
            just _pass "$NAME"
        else
            just _record-status "$NAME" "$label" $elapsed ""
            just _fail "$NAME ($label)"
        fi
        just _generate-report
    }
    trap finalize EXIT
    just _check-src
    just start-ubuntu-amd64 2>&1 | tee -a "$LOG"
    VM_UP=1
    PORT=$(cat ubuntu-amd64.port)
    set +o pipefail
    just _vm64-compile-ubuntu-amd64 "$PORT" 2>&1 | tee -a "$LOG"
    result=${PIPESTATUS[0]}
    set -o pipefail
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-$NAME" || result=$?
    fi
    exit $result

# Build and test vm64 on FreeBSD ARM64
[group('vm64')]
vm64-freebsd-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    NAME=vm64-freebsd-arm64
    mkdir -p "{{justfile_directory()}}/artifacts/logs"
    LOG="{{justfile_directory()}}/artifacts/logs/$NAME.log"
    : > "$LOG"
    START=$SECONDS
    VM_UP=0
    TIMEOUT_MARK="{{justfile_directory()}}/artifacts/logs/$NAME.timeout"
    rm -f "$TIMEOUT_MARK"
    ( sleep {{RUN_TIMEOUT_SECS}}
      touch "$TIMEOUT_MARK"
      pkill -TERM -P $$ 2>/dev/null || true
      sleep 10
      pkill -KILL -P $$ 2>/dev/null || true
    ) &
    WATCHDOG=$!
    finalize() {
        local code=$?
        kill $WATCHDOG 2>/dev/null || true
        wait $WATCHDOG 2>/dev/null || true
        [ $VM_UP -eq 1 ] && just stop-freebsd-arm64 2>/dev/null || true
        local elapsed=$((SECONDS - START))
        local label=FAIL
        if [ -f "$TIMEOUT_MARK" ]; then
            label=TIMEOUT
            rm -f "$TIMEOUT_MARK"
            echo "[$NAME] aborted after {{RUN_TIMEOUT_SECS}}s timeout" | tee -a "$LOG"
        fi
        if [ $code -eq 0 ]; then
            just _record-status "$NAME" PASS $elapsed "Self-$NAME"
            just _pass "$NAME"
        else
            just _record-status "$NAME" "$label" $elapsed ""
            just _fail "$NAME ($label)"
        fi
        just _generate-report
    }
    trap finalize EXIT
    just _check-src
    just start-freebsd-arm64 2>&1 | tee -a "$LOG"
    VM_UP=1
    PORT=$(cat freebsd-arm64.port)
    set +o pipefail
    just _vm64-compile-freebsd-arm64 "$PORT" 2>&1 | tee -a "$LOG"
    result=${PIPESTATUS[0]}
    set -o pipefail
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-$NAME" || result=$?
    fi
    exit $result

# Build and test vm64 on FreeBSD AMD64 (TCG-emulated)
[group('vm64')]
vm64-freebsd-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    NAME=vm64-freebsd-amd64
    mkdir -p "{{justfile_directory()}}/artifacts/logs"
    LOG="{{justfile_directory()}}/artifacts/logs/$NAME.log"
    : > "$LOG"
    START=$SECONDS
    VM_UP=0
    TIMEOUT_MARK="{{justfile_directory()}}/artifacts/logs/$NAME.timeout"
    rm -f "$TIMEOUT_MARK"
    ( sleep {{RUN_TIMEOUT_SECS}}
      touch "$TIMEOUT_MARK"
      pkill -TERM -P $$ 2>/dev/null || true
      sleep 10
      pkill -KILL -P $$ 2>/dev/null || true
    ) &
    WATCHDOG=$!
    finalize() {
        local code=$?
        kill $WATCHDOG 2>/dev/null || true
        wait $WATCHDOG 2>/dev/null || true
        [ $VM_UP -eq 1 ] && just stop-freebsd-amd64 2>/dev/null || true
        local elapsed=$((SECONDS - START))
        local label=FAIL
        if [ -f "$TIMEOUT_MARK" ]; then
            label=TIMEOUT
            rm -f "$TIMEOUT_MARK"
            echo "[$NAME] aborted after {{RUN_TIMEOUT_SECS}}s timeout" | tee -a "$LOG"
        fi
        if [ $code -eq 0 ]; then
            just _record-status "$NAME" PASS $elapsed "Self-$NAME"
            just _pass "$NAME"
        else
            just _record-status "$NAME" "$label" $elapsed ""
            just _fail "$NAME ($label)"
        fi
        just _generate-report
    }
    trap finalize EXIT
    just _check-src
    just start-freebsd-amd64 2>&1 | tee -a "$LOG"
    VM_UP=1
    PORT=$(cat freebsd-amd64.port)
    set +o pipefail
    just _vm64-compile-freebsd-amd64 "$PORT" 2>&1 | tee -a "$LOG"
    result=${PIPESTATUS[0]}
    set -o pipefail
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-$NAME" || result=$?
    fi
    exit $result

# Build and test vm64 on NetBSD AMD64 (TCG-emulated)
[group('vm64')]
vm64-netbsd-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    NAME=vm64-netbsd-amd64
    mkdir -p "{{justfile_directory()}}/artifacts/logs"
    LOG="{{justfile_directory()}}/artifacts/logs/$NAME.log"
    : > "$LOG"
    START=$SECONDS
    VM_UP=0
    TIMEOUT_MARK="{{justfile_directory()}}/artifacts/logs/$NAME.timeout"
    rm -f "$TIMEOUT_MARK"
    ( sleep {{RUN_TIMEOUT_SECS}}
      touch "$TIMEOUT_MARK"
      pkill -TERM -P $$ 2>/dev/null || true
      sleep 10
      pkill -KILL -P $$ 2>/dev/null || true
    ) &
    WATCHDOG=$!
    finalize() {
        local code=$?
        kill $WATCHDOG 2>/dev/null || true
        wait $WATCHDOG 2>/dev/null || true
        [ $VM_UP -eq 1 ] && just stop-netbsd-amd64 2>/dev/null || true
        local elapsed=$((SECONDS - START))
        local label=FAIL
        if [ -f "$TIMEOUT_MARK" ]; then
            label=TIMEOUT
            rm -f "$TIMEOUT_MARK"
            echo "[$NAME] aborted after {{RUN_TIMEOUT_SECS}}s timeout" | tee -a "$LOG"
        fi
        if [ $code -eq 0 ]; then
            just _record-status "$NAME" PASS $elapsed "Self-$NAME"
            just _pass "$NAME"
        else
            just _record-status "$NAME" "$label" $elapsed ""
            just _fail "$NAME ($label)"
        fi
        just _generate-report
    }
    trap finalize EXIT
    just _check-src
    just start-netbsd-amd64 2>&1 | tee -a "$LOG"
    VM_UP=1
    PORT=$(cat netbsd-amd64.port)
    set +o pipefail
    just _vm64-compile-netbsd-amd64 "$PORT" 2>&1 | tee -a "$LOG"
    result=${PIPESTATUS[0]}
    set -o pipefail
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-$NAME" || result=$?
    fi
    exit $result

# Build and test vm64 on NetBSD ARM64 (TCG-emulated)
[group('vm64')]
vm64-netbsd-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    NAME=vm64-netbsd-arm64
    mkdir -p "{{justfile_directory()}}/artifacts/logs"
    LOG="{{justfile_directory()}}/artifacts/logs/$NAME.log"
    : > "$LOG"
    START=$SECONDS
    VM_UP=0
    TIMEOUT_MARK="{{justfile_directory()}}/artifacts/logs/$NAME.timeout"
    rm -f "$TIMEOUT_MARK"
    ( sleep {{RUN_TIMEOUT_SECS}}
      touch "$TIMEOUT_MARK"
      pkill -TERM -P $$ 2>/dev/null || true
      sleep 10
      pkill -KILL -P $$ 2>/dev/null || true
    ) &
    WATCHDOG=$!
    finalize() {
        local code=$?
        kill $WATCHDOG 2>/dev/null || true
        wait $WATCHDOG 2>/dev/null || true
        [ $VM_UP -eq 1 ] && just stop-netbsd-arm64 2>/dev/null || true
        local elapsed=$((SECONDS - START))
        local label=FAIL
        if [ -f "$TIMEOUT_MARK" ]; then
            label=TIMEOUT
            rm -f "$TIMEOUT_MARK"
            echo "[$NAME] aborted after {{RUN_TIMEOUT_SECS}}s timeout" | tee -a "$LOG"
        fi
        if [ $code -eq 0 ]; then
            just _record-status "$NAME" PASS $elapsed "Self-$NAME"
            just _pass "$NAME"
        else
            just _record-status "$NAME" "$label" $elapsed ""
            just _fail "$NAME ($label)"
        fi
        just _generate-report
    }
    trap finalize EXIT
    just _check-src
    just start-netbsd-arm64 2>&1 | tee -a "$LOG"
    VM_UP=1
    PORT=$(cat netbsd-arm64.port)
    set +o pipefail
    just _vm64-compile-netbsd-arm64 "$PORT" 2>&1 | tee -a "$LOG"
    result=${PIPESTATUS[0]}
    set -o pipefail
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-$NAME" || result=$?
    fi
    exit $result

# Build and test vm64 on Alpine AMD64 (musl, TCG-emulated)
[group('vm64')]
vm64-alpine-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    NAME=vm64-alpine-amd64
    mkdir -p "{{justfile_directory()}}/artifacts/logs"
    LOG="{{justfile_directory()}}/artifacts/logs/$NAME.log"
    : > "$LOG"
    START=$SECONDS
    VM_UP=0
    TIMEOUT_MARK="{{justfile_directory()}}/artifacts/logs/$NAME.timeout"
    rm -f "$TIMEOUT_MARK"
    ( sleep {{RUN_TIMEOUT_SECS}}
      touch "$TIMEOUT_MARK"
      pkill -TERM -P $$ 2>/dev/null || true
      sleep 10
      pkill -KILL -P $$ 2>/dev/null || true
    ) &
    WATCHDOG=$!
    finalize() {
        local code=$?
        kill $WATCHDOG 2>/dev/null || true
        wait $WATCHDOG 2>/dev/null || true
        [ $VM_UP -eq 1 ] && just stop-alpine-amd64 2>/dev/null || true
        local elapsed=$((SECONDS - START))
        local label=FAIL
        if [ -f "$TIMEOUT_MARK" ]; then
            label=TIMEOUT
            rm -f "$TIMEOUT_MARK"
            echo "[$NAME] aborted after {{RUN_TIMEOUT_SECS}}s timeout" | tee -a "$LOG"
        fi
        if [ $code -eq 0 ]; then
            just _record-status "$NAME" PASS $elapsed "Self-$NAME"
            just _pass "$NAME"
        else
            just _record-status "$NAME" "$label" $elapsed ""
            just _fail "$NAME ($label)"
        fi
        just _generate-report
    }
    trap finalize EXIT
    just _check-src
    just start-alpine-amd64 2>&1 | tee -a "$LOG"
    VM_UP=1
    PORT=$(cat alpine-amd64.port)
    set +o pipefail
    just _vm64-compile-alpine-amd64 "$PORT" 2>&1 | tee -a "$LOG"
    result=${PIPESTATUS[0]}
    set -o pipefail
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-$NAME" || result=$?
    fi
    exit $result

# Build and test vm64 on Alpine ARM64 (musl, hvf-accelerated)
[group('vm64')]
vm64-alpine-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    NAME=vm64-alpine-arm64
    mkdir -p "{{justfile_directory()}}/artifacts/logs"
    LOG="{{justfile_directory()}}/artifacts/logs/$NAME.log"
    : > "$LOG"
    START=$SECONDS
    VM_UP=0
    TIMEOUT_MARK="{{justfile_directory()}}/artifacts/logs/$NAME.timeout"
    rm -f "$TIMEOUT_MARK"
    ( sleep {{RUN_TIMEOUT_SECS}}
      touch "$TIMEOUT_MARK"
      pkill -TERM -P $$ 2>/dev/null || true
      sleep 10
      pkill -KILL -P $$ 2>/dev/null || true
    ) &
    WATCHDOG=$!
    finalize() {
        local code=$?
        kill $WATCHDOG 2>/dev/null || true
        wait $WATCHDOG 2>/dev/null || true
        [ $VM_UP -eq 1 ] && just stop-alpine-arm64 2>/dev/null || true
        local elapsed=$((SECONDS - START))
        local label=FAIL
        if [ -f "$TIMEOUT_MARK" ]; then
            label=TIMEOUT
            rm -f "$TIMEOUT_MARK"
            echo "[$NAME] aborted after {{RUN_TIMEOUT_SECS}}s timeout" | tee -a "$LOG"
        fi
        if [ $code -eq 0 ]; then
            just _record-status "$NAME" PASS $elapsed "Self-$NAME"
            just _pass "$NAME"
        else
            just _record-status "$NAME" "$label" $elapsed ""
            just _fail "$NAME ($label)"
        fi
        just _generate-report
    }
    trap finalize EXIT
    just _check-src
    just start-alpine-arm64 2>&1 | tee -a "$LOG"
    VM_UP=1
    PORT=$(cat alpine-arm64.port)
    set +o pipefail
    just _vm64-compile-alpine-arm64 "$PORT" 2>&1 | tee -a "$LOG"
    result=${PIPESTATUS[0]}
    set -o pipefail
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-$NAME" || result=$?
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
    NAME=vm32-ubuntu-amd64
    mkdir -p "{{justfile_directory()}}/artifacts/logs"
    LOG="{{justfile_directory()}}/artifacts/logs/$NAME.log"
    : > "$LOG"
    START=$SECONDS
    VM_UP=0
    TIMEOUT_MARK="{{justfile_directory()}}/artifacts/logs/$NAME.timeout"
    rm -f "$TIMEOUT_MARK"
    ( sleep {{RUN_TIMEOUT_SECS}}
      touch "$TIMEOUT_MARK"
      pkill -TERM -P $$ 2>/dev/null || true
      sleep 10
      pkill -KILL -P $$ 2>/dev/null || true
    ) &
    WATCHDOG=$!
    finalize() {
        local code=$?
        kill $WATCHDOG 2>/dev/null || true
        wait $WATCHDOG 2>/dev/null || true
        [ $VM_UP -eq 1 ] && just stop-ubuntu-amd64-multilib 2>/dev/null || true
        local elapsed=$((SECONDS - START))
        local label=FAIL
        if [ -f "$TIMEOUT_MARK" ]; then
            label=TIMEOUT
            rm -f "$TIMEOUT_MARK"
            echo "[$NAME] aborted after {{RUN_TIMEOUT_SECS}}s timeout" | tee -a "$LOG"
        fi
        if [ $code -eq 0 ]; then
            just _record-status "$NAME" PASS $elapsed "Self-$NAME"
            just _pass "$NAME"
        else
            just _record-status "$NAME" "$label" $elapsed ""
            just _fail "$NAME ($label)"
        fi
        just _generate-report
    }
    trap finalize EXIT
    just _check-src
    just start-ubuntu-amd64-multilib 2>&1 | tee -a "$LOG"
    VM_UP=1
    PORT=$(cat ubuntu-amd64-multilib.port)
    set +o pipefail
    just _vm32-compile-ubuntu-amd64 "$PORT" 2>&1 | tee -a "$LOG"
    result=${PIPESTATUS[0]}
    set -o pipefail
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-$NAME" || result=$?
    fi
    exit $result

# Build and test vm32 on FreeBSD AMD64 lib32
[group('vm32')]
vm32-freebsd-amd64-lib32:
    #!/usr/bin/env bash
    set -euo pipefail
    NAME=vm32-freebsd-amd64-lib32
    mkdir -p "{{justfile_directory()}}/artifacts/logs"
    LOG="{{justfile_directory()}}/artifacts/logs/$NAME.log"
    : > "$LOG"
    START=$SECONDS
    VM_UP=0
    TIMEOUT_MARK="{{justfile_directory()}}/artifacts/logs/$NAME.timeout"
    rm -f "$TIMEOUT_MARK"
    ( sleep {{RUN_TIMEOUT_SECS}}
      touch "$TIMEOUT_MARK"
      pkill -TERM -P $$ 2>/dev/null || true
      sleep 10
      pkill -KILL -P $$ 2>/dev/null || true
    ) &
    WATCHDOG=$!
    finalize() {
        local code=$?
        kill $WATCHDOG 2>/dev/null || true
        wait $WATCHDOG 2>/dev/null || true
        [ $VM_UP -eq 1 ] && just stop-freebsd-amd64-lib32 2>/dev/null || true
        local elapsed=$((SECONDS - START))
        local label=FAIL
        if [ -f "$TIMEOUT_MARK" ]; then
            label=TIMEOUT
            rm -f "$TIMEOUT_MARK"
            echo "[$NAME] aborted after {{RUN_TIMEOUT_SECS}}s timeout" | tee -a "$LOG"
        fi
        if [ $code -eq 0 ]; then
            just _record-status "$NAME" PASS $elapsed "Self-$NAME"
            just _pass "$NAME"
        else
            just _record-status "$NAME" "$label" $elapsed ""
            just _fail "$NAME ($label)"
        fi
        just _generate-report
    }
    trap finalize EXIT
    just _check-src
    just start-freebsd-amd64-lib32 2>&1 | tee -a "$LOG"
    VM_UP=1
    PORT=$(cat freebsd-amd64-lib32.port)
    set +o pipefail
    just _vm32-compile-freebsd-amd64-lib32 "$PORT" 2>&1 | tee -a "$LOG"
    result=${PIPESTATUS[0]}
    set -o pipefail
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-$NAME" || result=$?
    fi
    exit $result

# Build and test vm32 on NetBSD i386
[group('vm32')]
vm32-netbsd-i386:
    #!/usr/bin/env bash
    set -euo pipefail
    NAME=vm32-netbsd-i386
    mkdir -p "{{justfile_directory()}}/artifacts/logs"
    LOG="{{justfile_directory()}}/artifacts/logs/$NAME.log"
    : > "$LOG"
    START=$SECONDS
    VM_UP=0
    TIMEOUT_MARK="{{justfile_directory()}}/artifacts/logs/$NAME.timeout"
    rm -f "$TIMEOUT_MARK"
    ( sleep {{RUN_TIMEOUT_SECS}}
      touch "$TIMEOUT_MARK"
      pkill -TERM -P $$ 2>/dev/null || true
      sleep 10
      pkill -KILL -P $$ 2>/dev/null || true
    ) &
    WATCHDOG=$!
    finalize() {
        local code=$?
        kill $WATCHDOG 2>/dev/null || true
        wait $WATCHDOG 2>/dev/null || true
        [ $VM_UP -eq 1 ] && just stop-netbsd-i386 2>/dev/null || true
        local elapsed=$((SECONDS - START))
        local label=FAIL
        if [ -f "$TIMEOUT_MARK" ]; then
            label=TIMEOUT
            rm -f "$TIMEOUT_MARK"
            echo "[$NAME] aborted after {{RUN_TIMEOUT_SECS}}s timeout" | tee -a "$LOG"
        fi
        if [ $code -eq 0 ]; then
            just _record-status "$NAME" PASS $elapsed "Self-$NAME"
            just _pass "$NAME"
        else
            just _record-status "$NAME" "$label" $elapsed ""
            just _fail "$NAME ($label)"
        fi
        just _generate-report
    }
    trap finalize EXIT
    just _check-src
    just start-netbsd-i386 2>&1 | tee -a "$LOG"
    VM_UP=1
    PORT=$(cat netbsd-i386.port)
    set +o pipefail
    just _vm32-compile-netbsd-i386 "$PORT" 2>&1 | tee -a "$LOG"
    result=${PIPESTATUS[0]}
    set -o pipefail
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-$NAME" || result=$?
    fi
    exit $result

# Build and test vm32 on NetBSD macppc (PowerPC, big-endian)
[group('vm32')]
vm32-netbsd-macppc:
    #!/usr/bin/env bash
    set -euo pipefail
    NAME=vm32-netbsd-macppc
    mkdir -p "{{justfile_directory()}}/artifacts/logs"
    LOG="{{justfile_directory()}}/artifacts/logs/$NAME.log"
    : > "$LOG"
    START=$SECONDS
    VM_UP=0
    TIMEOUT_MARK="{{justfile_directory()}}/artifacts/logs/$NAME.timeout"
    rm -f "$TIMEOUT_MARK"
    ( sleep {{RUN_TIMEOUT_SECS}}
      touch "$TIMEOUT_MARK"
      pkill -TERM -P $$ 2>/dev/null || true
      sleep 10
      pkill -KILL -P $$ 2>/dev/null || true
    ) &
    WATCHDOG=$!
    finalize() {
        local code=$?
        kill $WATCHDOG 2>/dev/null || true
        wait $WATCHDOG 2>/dev/null || true
        [ $VM_UP -eq 1 ] && just stop-netbsd-macppc 2>/dev/null || true
        local elapsed=$((SECONDS - START))
        local label=FAIL
        if [ -f "$TIMEOUT_MARK" ]; then
            label=TIMEOUT
            rm -f "$TIMEOUT_MARK"
            echo "[$NAME] aborted after {{RUN_TIMEOUT_SECS}}s timeout" | tee -a "$LOG"
        fi
        if [ $code -eq 0 ]; then
            just _record-status "$NAME" PASS $elapsed "Self-$NAME"
            just _pass "$NAME"
        else
            just _record-status "$NAME" "$label" $elapsed ""
            just _fail "$NAME ($label)"
        fi
        just _generate-report
    }
    trap finalize EXIT
    just _check-src
    just start-netbsd-macppc 2>&1 | tee -a "$LOG"
    VM_UP=1
    PORT=$(cat netbsd-macppc.port)
    set +o pipefail
    just _vm32-compile-netbsd-macppc "$PORT" 2>&1 | tee -a "$LOG"
    result=${PIPESTATUS[0]}
    set -o pipefail
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-$NAME" || result=$?
    fi
    exit $result

# Build and test vm32 on NetBSD sparc64 (32-bit SPARC binaries via gcc -m32,
# run on a sparc64 host through COMPAT_NETBSD32)
[group('vm32')]
vm32-netbsd-sparc64:
    #!/usr/bin/env bash
    set -euo pipefail
    NAME=vm32-netbsd-sparc64
    mkdir -p "{{justfile_directory()}}/artifacts/logs"
    LOG="{{justfile_directory()}}/artifacts/logs/$NAME.log"
    : > "$LOG"
    START=$SECONDS
    VM_UP=0
    TIMEOUT_MARK="{{justfile_directory()}}/artifacts/logs/$NAME.timeout"
    rm -f "$TIMEOUT_MARK"
    ( sleep {{RUN_TIMEOUT_SECS}}
      touch "$TIMEOUT_MARK"
      pkill -TERM -P $$ 2>/dev/null || true
      sleep 10
      pkill -KILL -P $$ 2>/dev/null || true
    ) &
    WATCHDOG=$!
    finalize() {
        local code=$?
        kill $WATCHDOG 2>/dev/null || true
        wait $WATCHDOG 2>/dev/null || true
        [ $VM_UP -eq 1 ] && just stop-netbsd-sparc64 2>/dev/null || true
        local elapsed=$((SECONDS - START))
        local label=FAIL
        if [ -f "$TIMEOUT_MARK" ]; then
            label=TIMEOUT
            rm -f "$TIMEOUT_MARK"
            echo "[$NAME] aborted after {{RUN_TIMEOUT_SECS}}s timeout" | tee -a "$LOG"
        fi
        if [ $code -eq 0 ]; then
            just _record-status "$NAME" PASS $elapsed "Self-$NAME"
            just _pass "$NAME"
        else
            just _record-status "$NAME" "$label" $elapsed ""
            just _fail "$NAME ($label)"
        fi
        just _generate-report
    }
    trap finalize EXIT
    just _check-src
    just start-netbsd-sparc64 2>&1 | tee -a "$LOG"
    VM_UP=1
    PORT=$(cat netbsd-sparc64.port)
    set +o pipefail
    just _vm32-compile-netbsd-sparc64 "$PORT" 2>&1 | tee -a "$LOG"
    result=${PIPESTATUS[0]}
    set -o pipefail
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-$NAME" || result=$?
    fi
    exit $result

# Build and test vm32 on Alpine x86 (native 32-bit, musl)
[group('vm32')]
vm32-alpine-x86:
    #!/usr/bin/env bash
    set -euo pipefail
    NAME=vm32-alpine-x86
    mkdir -p "{{justfile_directory()}}/artifacts/logs"
    LOG="{{justfile_directory()}}/artifacts/logs/$NAME.log"
    : > "$LOG"
    START=$SECONDS
    VM_UP=0
    TIMEOUT_MARK="{{justfile_directory()}}/artifacts/logs/$NAME.timeout"
    rm -f "$TIMEOUT_MARK"
    ( sleep {{RUN_TIMEOUT_SECS}}
      touch "$TIMEOUT_MARK"
      pkill -TERM -P $$ 2>/dev/null || true
      sleep 10
      pkill -KILL -P $$ 2>/dev/null || true
    ) &
    WATCHDOG=$!
    finalize() {
        local code=$?
        kill $WATCHDOG 2>/dev/null || true
        wait $WATCHDOG 2>/dev/null || true
        [ $VM_UP -eq 1 ] && just stop-alpine-x86 2>/dev/null || true
        local elapsed=$((SECONDS - START))
        local label=FAIL
        if [ -f "$TIMEOUT_MARK" ]; then
            label=TIMEOUT
            rm -f "$TIMEOUT_MARK"
            echo "[$NAME] aborted after {{RUN_TIMEOUT_SECS}}s timeout" | tee -a "$LOG"
        fi
        if [ $code -eq 0 ]; then
            just _record-status "$NAME" PASS $elapsed "Self-$NAME"
            just _pass "$NAME"
        else
            just _record-status "$NAME" "$label" $elapsed ""
            just _fail "$NAME ($label)"
        fi
        just _generate-report
    }
    trap finalize EXIT
    just _check-src
    just start-alpine-x86 2>&1 | tee -a "$LOG"
    VM_UP=1
    PORT=$(cat alpine-x86.port)
    set +o pipefail
    just _vm32-compile-alpine-x86 "$PORT" 2>&1 | tee -a "$LOG"
    result=${PIPESTATUS[0]}
    set -o pipefail
    if [ $result -eq 0 ]; then
        mkdir -p artifacts
        sshpass -p ci scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -P "$PORT" \
            ci@localhost:/tmp/self-build/build/Self "artifacts/Self-$NAME" || result=$?
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

# FreeBSD recipes use gcc14 (installed via cloud-init) instead of the system
# clang. Stock LLVM clang on aarch64 generates a bytecode interpreter whose
# recursive cycle (interpret_method -> interpret -> try_pic_entry -> send ->
# ... -> interpret_method) consumes ~10× the C++ stack of gcc/Apple-Clang for
# the same Self code, blowing the 5 MB SelfStackLimit during world boot.
# amd64 is included too — same toolchain, same risk, and gcc14 builds cleanly.
# Linker rpath needed because gcc14's libstdc++ depends on gcc14's libgcc_s,
# not the older system one.
FREEBSD_GCC_CMAKE := '-DCMAKE_C_COMPILER=/usr/local/bin/gcc14 -DCMAKE_CXX_COMPILER=/usr/local/bin/g++14 -DCMAKE_EXE_LINKER_FLAGS=-Wl,-rpath=/usr/local/lib/gcc14'

_vm64-compile-freebsd-arm64 port:
    @just _action "Compiling vm64 on FreeBSD ARM64 (gcc14)"
    @just _rsync {{port}}
    @just do {{port}} 'cd /tmp/self-build && cmake -S vm64 -B build -DCMAKE_BUILD_TYPE=Release -DSELF_QUARTZ=OFF {{FREEBSD_GCC_CMAKE}} && rm -f build/incls/_precompiled.hh.gch && cmake --build build -j$(sysctl -n hw.ncpu)'
    @just do {{port}} 'cd /tmp/self-build && build/Self --vm-run-tests'
    @just do {{port}} 'cd /tmp/self-build/objects && echo "saveAs: '"'"'auto.snap64'"'"'. _Quit" | ../build/Self -f worldBuilder.self -o morphic'
    @just do {{port}} 'cd /tmp/self-build && echo "_Quit" | build/Self -s objects/auto.snap64'
    @just do {{port}} 'cd /tmp/self-build && build/Self -s objects/auto.snap64 --runAutomaticTests --headless'
    @just _banner "Finished vm64 on FreeBSD ARM64"

_vm64-compile-freebsd-amd64 port:
    @just _action "Compiling vm64 on FreeBSD AMD64 (gcc14)"
    @just _rsync {{port}}
    @just do {{port}} 'cd /tmp/self-build && cmake -S vm64 -B build -DCMAKE_BUILD_TYPE=Release -DSELF_QUARTZ=OFF {{FREEBSD_GCC_CMAKE}} && rm -f build/incls/_precompiled.hh.gch && cmake --build build -j$(sysctl -n hw.ncpu)'
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

_vm64-compile-netbsd-arm64 port:
    @just _action "Compiling vm64 on NetBSD ARM64"
    @just _rsync {{port}}
    @just do {{port}} 'cd /tmp/self-build && cmake -S vm64 -B build -DCMAKE_BUILD_TYPE=Release -DSELF_QUARTZ=OFF && rm -f build/incls/_precompiled.hh.gch && cmake --build build -j$(sysctl -n hw.ncpu)'
    @just do {{port}} 'cd /tmp/self-build && build/Self --vm-run-tests'
    @just do {{port}} 'cd /tmp/self-build/objects && echo "saveAs: '"'"'auto.snap64'"'"'. _Quit" | ../build/Self -f worldBuilder.self -o morphic'
    @just do {{port}} 'cd /tmp/self-build && echo "_Quit" | build/Self -s objects/auto.snap64'
    @just do {{port}} 'cd /tmp/self-build && build/Self -s objects/auto.snap64 --runAutomaticTests --headless'
    @just _banner "Finished vm64 on NetBSD ARM64"

# The Alpine vm64 builds are the musl-libc counterparts of the Ubuntu ones.
# Unlike vm32 on Alpine x86 there is no phkmalloc interposer: 64-bit oop
# tagging places no address-range constraint on the C heap (macOS and the
# BSDs already run vm64 with high malloc addresses).
_vm64-compile-alpine-amd64 port:
    @just _action "Compiling vm64 on Alpine AMD64"
    @just _rsync {{port}}
    @just do {{port}} 'cd /tmp/self-build && cmake -S vm64 -B build -DCMAKE_BUILD_TYPE=Release -DSELF_QUARTZ=OFF && rm -f build/incls/_precompiled.hh.gch && cmake --build build -j$(nproc)'
    @just do {{port}} 'cd /tmp/self-build && build/Self --vm-run-tests'
    @just do {{port}} 'cd /tmp/self-build/objects && echo "saveAs: '"'"'auto.snap64'"'"'. _Quit" | ../build/Self -f worldBuilder.self -o morphic'
    @just do {{port}} 'cd /tmp/self-build && echo "_Quit" | build/Self -s objects/auto.snap64'
    @just do {{port}} 'cd /tmp/self-build && build/Self -s objects/auto.snap64 --runAutomaticTests --headless'
    @just _banner "Finished vm64 on Alpine AMD64"

_vm64-compile-alpine-arm64 port:
    @just _action "Compiling vm64 on Alpine ARM64"
    @just _rsync {{port}}
    @just do {{port}} 'cd /tmp/self-build && cmake -S vm64 -B build -DCMAKE_BUILD_TYPE=Release -DSELF_QUARTZ=OFF && rm -f build/incls/_precompiled.hh.gch && cmake --build build -j$(nproc)'
    @just do {{port}} 'cd /tmp/self-build && build/Self --vm-run-tests'
    @just do {{port}} 'cd /tmp/self-build/objects && echo "saveAs: '"'"'auto.snap64'"'"'. _Quit" | ../build/Self -f worldBuilder.self -o morphic'
    @just do {{port}} 'cd /tmp/self-build && echo "_Quit" | build/Self -s objects/auto.snap64'
    @just do {{port}} 'cd /tmp/self-build && build/Self -s objects/auto.snap64 --runAutomaticTests --headless'
    @just _banner "Finished vm64 on Alpine ARM64"

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

_vm32-compile-netbsd-macppc port:
    @just _action "Compiling vm32 on NetBSD macppc"
    @just _rsync {{port}}
    @just do {{port}} 'cd /tmp/self-build && cmake -S vm -B build -DCMAKE_BUILD_TYPE=Release -DSELF_QUARTZ=OFF && cmake --build build -j$(sysctl -n hw.ncpu)'
    @just do {{port}} 'cd /tmp/self-build/objects && echo "saveAs: '"'"'auto.snap'"'"'. _Quit" | ../build/Self -f worldBuilder.self -o morphic'
    @just do {{port}} 'cd /tmp/self-build && echo "_Quit" | build/Self -s objects/auto.snap'
    @just do {{port}} 'cd /tmp/self-build && build/Self -s objects/auto.snap --runAutomaticTests --headless'
    @just _banner "Finished vm32 on NetBSD macppc"

_vm32-compile-netbsd-sparc64 port:
    @just _action "Compiling vm32 (sparc -m32) on NetBSD sparc64"
    @just _rsync {{port}}
    # /usr/lib/sparc/libphkmalloc.a is added to the link line (installed by
    # provision-netbsd-sparc64) to override libc's TLS-using malloc — Self's
    # SPARC JIT clobbers %g7. See upstream issue russellallen/self#149.
    @just do {{port}} 'cd /tmp/self-build && cmake -S vm -B build -DCMAKE_BUILD_TYPE=Release -DSELF_QUARTZ=OFF -DCMAKE_C_FLAGS=-m32 -DCMAKE_CXX_FLAGS=-m32 -DCMAKE_EXE_LINKER_FLAGS="-m32 -Wl,-rpath,/usr/X11R7/lib/sparc:/usr/lib/sparc /usr/lib/sparc/libphkmalloc.a" -DCMAKE_LIBRARY_PATH="/usr/lib/sparc;/usr/X11R7/lib/sparc" -DCMAKE_INCLUDE_PATH="/usr/X11R7/include" && cmake --build build -j$(sysctl -n hw.ncpu)'
    @just do {{port}} 'cd /tmp/self-build/objects && echo "saveAs: '"'"'auto.snap'"'"'. _Quit" | ../build/Self -f worldBuilder.self -o morphic'
    @just do {{port}} 'cd /tmp/self-build && echo "_Quit" | build/Self -s objects/auto.snap'
    @just do {{port}} 'cd /tmp/self-build && build/Self -s objects/auto.snap --runAutomaticTests --headless'
    @just _banner "Finished vm32 on NetBSD sparc64"

# Alpine x86 is natively 32-bit (no multilib/PKG_CONFIG_LIBDIR gymnastics
# needed) and the first musl-libc platform in this CI. phkmalloc (built at
# provision time) is linked --whole-archive so its malloc/free interpose over
# musl's for the whole process, keeping C-heap pointers below the oop-tag
# bit — the musl equivalent of the glibc mallopt/__morecore trick.
_vm32-compile-alpine-x86 port:
    @just _action "Compiling vm32 on Alpine x86"
    @just _rsync {{port}}
    @just do {{port}} 'cd /tmp/self-build && cmake -S vm -B build -DCMAKE_BUILD_TYPE=Release -DSELF_QUARTZ=OFF -DCMAKE_EXE_LINKER_FLAGS="-Wl,--whole-archive /usr/lib/libphkmalloc.a -Wl,--no-whole-archive" && cmake --build build -j$(nproc)'
    @just do {{port}} 'cd /tmp/self-build/objects && echo "saveAs: '"'"'auto.snap'"'"'. _Quit" | ../build/Self -f worldBuilder.self -o morphic'
    @just do {{port}} 'cd /tmp/self-build && echo "_Quit" | build/Self -s objects/auto.snap'
    @just do {{port}} 'cd /tmp/self-build && build/Self -s objects/auto.snap --runAutomaticTests --headless'
    @just _banner "Finished vm32 on Alpine x86"

# ═══════════════════════════════════════════════════════════
#  Provision — Download and provision VM images
# ═══════════════════════════════════════════════════════════

# Download and provision all VM images
[group('Provision')]
provision-all: provision-ubuntu-arm64 provision-ubuntu-amd64 provision-ubuntu-amd64-multilib provision-freebsd-amd64-lib32 provision-freebsd-arm64 provision-freebsd-amd64 provision-netbsd-i386 provision-netbsd-amd64 provision-netbsd-macppc provision-netbsd-sparc64 provision-alpine-x86 provision-alpine-amd64 provision-alpine-arm64
    @just _banner "All images ready"

# Download and provision Ubuntu ARM64
[group('Provision')]
provision-ubuntu-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images
    if [ -f "{{UBUNTU_ARM64_QCOW}}" ]; then
        just _action "Image already exists: {{UBUNTU_ARM64_QCOW}} (delete to force re-provision)"
    else
        just _action "Downloading Ubuntu ARM64 cloud image"
        curl -L -o "{{UBUNTU_ARM64_QCOW}}" "{{UBUNTU_ARM64_URL}}"
        qemu-img resize "{{UBUNTU_ARM64_QCOW}}" 20G
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
    fi
    just _banner "Ubuntu ARM64 image ready"

# Download and provision Ubuntu AMD64 (vm64 only)
[group('Provision')]
provision-ubuntu-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images
    if [ -f "{{UBUNTU_AMD64_QCOW}}" ]; then
        just _action "Image already exists: {{UBUNTU_AMD64_QCOW}} (delete to force re-provision)"
    else
        just _action "Downloading Ubuntu AMD64 cloud image"
        curl -L -o "{{UBUNTU_AMD64_QCOW}}" "{{UBUNTU_AMD64_URL}}"
        qemu-img resize "{{UBUNTU_AMD64_QCOW}}" 20G
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
    fi
    just _banner "Ubuntu AMD64 image ready"

# Download and provision Ubuntu AMD64 multilib (vm 32-bit builds)
[group('Provision')]
provision-ubuntu-amd64-multilib:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images
    if [ -f "{{UBUNTU_MULTILIB_QCOW}}" ]; then
        just _action "Image already exists: {{UBUNTU_MULTILIB_QCOW}} (delete to force re-provision)"
    else
        just _action "Downloading Ubuntu AMD64 cloud image (for multilib)"
        curl -L -o "{{UBUNTU_MULTILIB_QCOW}}" "{{UBUNTU_AMD64_URL}}"
        qemu-img resize "{{UBUNTU_MULTILIB_QCOW}}" 20G
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
    fi
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
    # Always shut the VM down, even if provisioning fails — leaving the
    # qemu process around locks the pidfile and blocks the next attempt.
    cleanup() { just _stop-vm freebsd-arm64-provision.pid "$PORT" 2>/dev/null || true; }
    trap cleanup EXIT
    just _action "Waiting for nuageinit to finish (sshd will come up when done)"
    just _wait-for-ssh "$PORT"
    just _action "Provisioning complete — shutting down VM via SSH"
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
    # Always shut the VM down, even if provisioning fails — leaving the
    # qemu process around locks the pidfile and blocks the next attempt.
    cleanup() { just _stop-vm freebsd-amd64-provision.pid "$PORT" 2>/dev/null || true; }
    trap cleanup EXIT
    just _action "Waiting for nuageinit to finish (sshd will come up when done)"
    # TCG-emulated x86_64 + cloud-init + gcc14 install is slow — give it ~30 min.
    just _wait-for-ssh "$PORT" 900
    # sshd may come up before nuageinit's runcmd finishes installing packages.
    # The cloud-init writes /var/run/self-ci-provisioned only on successful
    # `pkg install`, so poll for it (up to ~10 min).
    just _action "Verifying cloud-init package install succeeded"
    # nuageinit installs the requested packages one at a time. Each is a pkg
    # bootstrap → fetch → install cycle, and TCG-emulated x86 is slow, so the
    # full sequence often takes 15-20+ minutes after sshd comes up. Poll up to
    # ~30 minutes; report progress every ~30 s so it doesn't look hung.
    PKGS="cmake rsync bash xxd pkgconf sudo libX11 libXext ncurses fusefs-sshfs gcc14"
    TOTAL=$(echo "$PKGS" | wc -w | tr -d ' ')
    FOUND_MARKER=no
    for i in $(seq 1 600); do
        if sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -p "$PORT" ci@localhost \
            'test -f /var/run/self-ci-provisioned' 2>/dev/null; then
            FOUND_MARKER=yes
            break
        fi
        if [ $(( i % 10 )) -eq 0 ]; then
            INSTALLED=$(sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                -o LogLevel=ERROR -p "$PORT" ci@localhost \
                "n=0; for p in $PKGS; do pkg info -e \$p 2>/dev/null && n=\$((n+1)); done; echo \$n" 2>/dev/null || echo "?")
            printf '  [%3ds] %s/%s packages installed\n' $(( i * 3 )) "$INSTALLED" "$TOTAL"
        fi
        sleep 3
    done
    if [ "$FOUND_MARKER" != yes ]; then
        echo "ERROR: cloud-init pkg install did not complete (no /var/run/self-ci-provisioned marker)."
        echo "       --- /var/log/nuageinit.log ---"
        sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -p "$PORT" ci@localhost \
            'sudo cat /var/log/nuageinit.log' 2>&1 || true
        echo "       --- end of log ---"
        exit 1
    fi
    just _action "Provisioning complete — shutting down VM via SSH"
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
        --disk-size 8G \
        --memory-size 2G \
        --persist \
        --sets kern-GENERIC,modules,base,etc,comp,xbase,xcomp \
        --run '{ (useradd -m -G wheel -s /bin/sh -p "$(openssl passwd -1 ci)" ci || true) && echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && echo sshd=YES >> /etc/rc.conf && echo dhcpcd=YES >> /etc/rc.conf && echo ifconfig_wm0=dhcp >> /etc/rc.conf && ssh-keygen -A && echo noipv6rs >> /etc/dhcpcd.conf && dhcpcd wm0 && export PKG_PATH=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/i386/10.0/All && pkg_add sudo && mkdir -p /usr/pkg/etc && echo "ci ALL=(ALL) NOPASSWD: ALL" > /usr/pkg/etc/sudoers && echo "ci ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers; }; echo PROVISION_EXIT=$?' \
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
        --disk-size 8G \
        --memory-size 2G \
        --persist \
        --sets kern-GENERIC,modules,base,etc,comp,xbase,xcomp \
        --run '{ (useradd -m -G wheel -s /bin/sh -p "$(openssl passwd -1 ci)" ci || true) && echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && echo sshd=YES >> /etc/rc.conf && echo dhcpcd=YES >> /etc/rc.conf && echo ifconfig_wm0=dhcp >> /etc/rc.conf && ssh-keygen -A && echo noipv6rs >> /etc/dhcpcd.conf && dhcpcd wm0 && export PKG_PATH=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/amd64/10.0/All && pkg_add sudo && mkdir -p /usr/pkg/etc && echo "ci ALL=(ALL) NOPASSWD: ALL" > /usr/pkg/etc/sudoers && echo "ci ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers; }; echo PROVISION_EXIT=$?' \
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

# Download and provision NetBSD ARM64 (vm64 + vm32 share the same image)
#
# Unlike the i386/amd64/macppc/sparc64 NetBSD ports, evbarm-aarch64 has no
# sysinst installer in NetBSD 10.1 — the standard distribution path is the
# pre-built `binary/gzimg/arm64.img.gz`. Anita knows about this: for archs
# with `image_name` set (evbarm-aarch64, evbarm-earmv7hf, riscv64), it
# short-circuits download() and boots the gzimg directly instead of running
# sysinst. The --sets list is still validated by anita up front, so we pass
# the minimum it accepts (`base,etc,kern-GENERIC`) — those names are not
# actually used at install time for an image-based arch.
#
# qemu's virtio-net appears as vioif0 in NetBSD (not wm0).
#
# Phase A boot is via -kernel (not UEFI/edk2) since anita uses that path and
# the gzimg's EFI partition isn't relied on. We re-use the same boot model in
# start-netbsd-arm64 and in Phase B.
#
# Phase A is skipped if the qcow already exists — re-running this recipe to
# retry Phase B is fast. Delete the qcow to force a full reinstall.
[group('Provision')]
provision-netbsd-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images
    workdir="images/netbsd-arm64-anita"
    if [ ! -f "{{NETBSD_ARM64_QCOW}}" ]; then
        #
        # Phase A: anita boots the pre-built gzimg + minimal --run (user,
        # sshd, network, sudo, sudoers). No sysinst — the image is already
        # installed. qemu's default user-mode networking gives anita a NIC
        # implicitly, so dhcpcd vioif0 + pkg_add sudo work inside --run.
        #
        just _action "Phase A: anita boots gzimg (minimal --run)"
        uvx --from git+https://github.com/gson1703/anita.git --with pexpect anita \
            --workdir "$workdir" \
            --disk-size 8G \
            --memory-size 4G \
            --persist \
            --sets base,etc,kern-GENERIC \
            --run '{ (useradd -m -G wheel -s /bin/sh -p "$(openssl passwd -1 ci)" ci || true) && echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && echo sshd=YES >> /etc/rc.conf && echo dhcpcd=YES >> /etc/rc.conf && echo ifconfig_vioif0=dhcp >> /etc/rc.conf && ssh-keygen -A && echo noipv6rs >> /etc/dhcpcd.conf && dhcpcd vioif0 && export PKG_PATH=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/aarch64/10.0/All && pkg_add sudo && mkdir -p /usr/pkg/etc && echo "ci ALL=(ALL) NOPASSWD: ALL" > /usr/pkg/etc/sudoers && echo "ci ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers; }; echo PROVISION_EXIT=$?' \
            boot \
            "{{NETBSD_ARM64_URL}}"
        just _action "Converting wd0.img → qcow2"
        qemu-img convert -f raw -O qcow2 "$workdir/wd0.img" "{{NETBSD_ARM64_QCOW}}"
        cp "$workdir/download/evbarm-aarch64/binary/kernel/netbsd-GENERIC64.img.gz" \
            images/netbsd-arm64-kernel.img.gz
    else
        just _action "Phase A: skipping (qcow exists at {{NETBSD_ARM64_QCOW}}; delete to force reinstall)"
    fi
    #
    # Phase B: boot the qcow2 normally (persistent writes), ssh in as ci, run
    # pkgin install. Re-runs of this recipe pick up here.
    #
    just _action "Phase B: booting qcow2 to install pkgsrc packages"
    PORT=$(just _free-port)
    trap '[ -f netbsd-arm64-provision.pid ] && kill "$(cat netbsd-arm64-provision.pid)" 2>/dev/null; rm -f netbsd-arm64-provision.pid' EXIT
    qemu-system-aarch64 \
        -M virt,gic-version=3 -accel hvf -cpu host \
        -m 4G -smp 4 \
        -drive file={{NETBSD_ARM64_QCOW}},if=none,id=hd0 \
        -device virtio-blk-device,drive=hd0 \
        -kernel images/netbsd-arm64-kernel.img.gz \
        -append 'root=NAME=netbsd-root' \
        -netdev user,id=net0,hostfwd=tcp::${PORT}-:22 \
        -device virtio-net-pci,netdev=net0 \
        -pidfile netbsd-arm64-provision.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    #
    # Phase B is split into one SSH call per step so the host-side log shows
    # progress, and uses ServerAliveInterval to keep long-running ops from
    # appearing hung due to silent pkgin output.
    #
    # qemu's slirp advertises a fec0::/64 prefix via RA, and dhcpcd's IPv6
    # stack SLAACs a fec0:: address onto vioif0. Slirp doesn't actually route
    # IPv6 outbound, but NetBSD's resolver + libfetch see a global-looking
    # IPv6 source addr and prefer AAAA records → pkgin hangs in SYN_SENT
    # against the CDN's IPv6 endpoint. We bake `noipv6rs` into
    # /etc/dhcpcd.conf so dhcpcd ignores future RAs, then strip the address
    # already configured on this boot. After this, only fe80:: link-local
    # remains; AI_ADDRCONFIG suppresses AAAA returns, and libfetch uses IPv4.
    # The fix is persistent — `start-netbsd-arm64` snapshot boots inherit it.
    #
    SSH="sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ServerAliveInterval=30 -o ServerAliveCountMax=20 -p $PORT ci@localhost"
    P="export PATH=/usr/sbin:/sbin:/usr/bin:/bin:/usr/pkg/sbin:/usr/pkg/bin"
    PKG="export PKG_PATH=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/aarch64/10.0/All"
    just _action "Step 1/7: persisting noipv6rs in /etc/dhcpcd.conf and stripping current fec0:: from vioif0"
    $SSH "$P && (grep -q '^noipv6rs' /etc/dhcpcd.conf || echo noipv6rs | sudo tee -a /etc/dhcpcd.conf) && for a in \$(ifconfig vioif0 | awk '/inet6/ && !/fe80/{print \$2}' | sed 's/%.*//'); do echo \"removing \$a\"; sudo ifconfig vioif0 inet6 -alias \"\$a\"; done && echo 'inet6 disable: ok'"
    just _action "Step 2/7: verifying network state (vioif0 should have only fe80:: link-local IPv6)"
    $SSH "$P && ifconfig vioif0 | sed 's/^/  /' && echo 'DNS lookup:' && host cdn.NetBSD.org 2>&1 | sed 's/^/  /' | head -8"
    just _action "Step 3/7: pkg_add pkgin"
    $SSH "$P && $PKG && sudo env PKG_PATH=\$PKG_PATH pkg_add pkgin"
    just _action "Step 4/7: configuring pkgin repositories.conf"
    $SSH "$P && $PKG && echo \"\$PKG_PATH\" | sudo tee /usr/pkg/etc/pkgin/repositories.conf"
    # pkgin uses -v for "show version and exit" (not verbose); -V is verbose.
    # We use plain pkgin update/install for moderate output that won't drown
    # the terminal under TCG.
    just _action "Step 5/7: pkgin -y update (TCG-emulated SQLite parse — slow but should not stall)"
    $SSH "$P && $PKG && sudo env PKG_PATH=\$PKG_PATH pkgin -y update"
    just _action "Step 6/7: pkgin -y install cmake gcc12 rsync jemalloc bash vim-share"
    $SSH "$P && $PKG && sudo env PKG_PATH=\$PKG_PATH pkgin -y install cmake gcc12 rsync jemalloc bash vim-share"
    just _action "Step 7/7: shutting down VM"
    just _stop-vm netbsd-arm64-provision.pid "$PORT"
    just _banner "NetBSD ARM64 image ready"

# Download and provision NetBSD macppc (vm 32-bit, PowerPC, via Anita run through uvx)
#
# Same two-phase approach as netbsd-i386: anita drives sysinst over the serial
# console for Phase A; Phase B SSHes in to run pkgin and install build deps.
# macppc is PowerPC 32-bit big-endian, emulated on amd64/arm64 hosts via
# qemu-system-ppc with the mac99 (PowerMac G4) machine. The on-board NIC is
# sungem, exposed as gem0 in NetBSD, and the disk is IDE (mac99 has no virtio).
[group('Provision')]
provision-netbsd-macppc:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images
    workdir="images/netbsd-macppc-anita"
    #
    # Phase A: anita install + minimal --run (user, root pw, sshd, network, keygen).
    #
    just _action "Phase A: anita install (minimal --run)"
    # macppc memory sensitivity: NetBSD/macppc on qemu is finicky about RAM
    # — 1G traps early in the kernel (silent hang right after OpenBIOS hands
    # off), 3G fails part-way through install. 2G is the documented sweet
    # spot. See port-macppc list, riastradh, 2021-04-04:
    # http://mail-index.netbsd.org/port-macppc/2021/04/04/msg002856.html
    # Also override the default `mac99` (cuda) → `mac99,via=pmu` for stability.
    uvx --from git+https://github.com/gson1703/anita.git --with pexpect anita \
        --workdir "$workdir" \
        --disk-size 8G \
        --memory-size 2G \
        --persist \
        --sets kern-GENERIC,modules,base,etc,comp \
        --machine "mac99,via=pmu" \
        --run '{ (useradd -m -G wheel -s /bin/sh -p "$(openssl passwd -1 ci)" ci || true) && echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && echo sshd=YES >> /etc/rc.conf && echo dhcpcd=YES >> /etc/rc.conf && echo ifconfig_gem0=dhcp >> /etc/rc.conf && ssh-keygen -A && echo noipv6rs >> /etc/dhcpcd.conf && dhcpcd gem0 && export PKG_PATH=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/macppc/10.0/All && pkg_add sudo && mkdir -p /usr/pkg/etc && echo "ci ALL=(ALL) NOPASSWD: ALL" > /usr/pkg/etc/sudoers && echo "ci ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers; }; echo PROVISION_EXIT=$?' \
        boot \
        "{{NETBSD_MACPPC_URL}}"
    just _action "Converting wd0.img → qcow2"
    rm -f "{{NETBSD_MACPPC_QCOW}}"
    qemu-img convert -f raw -O qcow2 "$workdir/wd0.img" "{{NETBSD_MACPPC_QCOW}}"
    #
    # Phase B: boot the qcow2 normally (persistent writes), ssh in as root, run
    # pkgin install. If this fails, re-run this recipe — anita is skipped
    # because its workdir cache is intact, and only Phase B repeats.
    #
    just _action "Phase B: booting qcow2 to install pkgsrc packages"
    PORT=$(just _free-port)
    trap '[ -f netbsd-macppc-provision.pid ] && kill "$(cat netbsd-macppc-provision.pid)" 2>/dev/null; rm -f netbsd-macppc-provision.pid' EXIT
    qemu-system-ppc \
        -M mac99,via=pmu -cpu G4 \
        -m 2G \
        -drive file={{NETBSD_MACPPC_QCOW}},if=ide \
        -nic user,model=sungem,hostfwd=tcp::${PORT}-:22 \
        -prom-env "auto-boot?=true" \
        -prom-env "boot-device=hd:,\\ofwboot.xcf" \
        -prom-env "boot-file=netbsd" \
        -pidfile netbsd-macppc-provision.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _action "Installing pkgsrc packages via SSH as root"
    sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -p "$PORT" ci@localhost \
        'export PATH=/usr/sbin:/sbin:/usr/bin:/bin:/usr/pkg/sbin:/usr/pkg/bin && export PKG_PATH=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/macppc/10.0/All && (ifconfig gem0 | grep -q "inet " || sudo dhcpcd gem0) && sudo env PKG_PATH=$PKG_PATH pkg_add pkgin && echo "$PKG_PATH" | sudo tee /usr/pkg/etc/pkgin/repositories.conf > /dev/null && sudo env PKG_PATH=$PKG_PATH pkgin -y update && sudo env PKG_PATH=$PKG_PATH pkgin -y install cmake gcc12 rsync jemalloc bash vim-share'
    just _action "Shutting down VM"
    just _stop-vm netbsd-macppc-provision.pid "$PORT"
    just _banner "NetBSD macppc image ready"

# Download and provision NetBSD sparc64 (vm 32-bit via gcc -m32, via Anita run
# through uvx)
#
# Same two-phase approach as netbsd-i386: anita drives sysinst over the serial
# console for Phase A; Phase B SSHes in to run pkgin and install build deps.
# sparc64 is 64-bit SPARC big-endian, emulated via qemu-system-sparc64 with
# the default sun4u (UltraSPARC) machine. The on-board NIC is sunhme (hme0 in
# NetBSD) and the disk is IDE on the sun4u south bridge. The system gcc in
# base/comp ships with sparc/sparc64 multilib, so we build vm32 with -m32 and
# run the resulting 32-bit binary directly via the kernel's COMPAT_NETBSD32.
[group('Provision')]
provision-netbsd-sparc64:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images
    workdir="images/netbsd-sparc64-anita"
    #
    # Phase A: anita install + minimal --run (user, root pw, sshd, network, keygen).
    # anita requires an ISO for sparc64 (not a release tree); see check_arch_supported
    # in anita.py.
    #
    just _action "Phase A: anita install (minimal --run)"
    uvx --from git+https://github.com/gson1703/anita.git --with pexpect anita \
        --workdir "$workdir" \
        --disk-size 8G \
        --memory-size 2G \
        --persist \
        --sets kern-GENERIC,modules,base,etc,comp,xbase,xcomp \
        --run '{ (useradd -m -G wheel -s /bin/sh -p "$(openssl passwd -1 ci)" ci || true) && echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && echo sshd=YES >> /etc/rc.conf && echo dhcpcd=YES >> /etc/rc.conf && echo ifconfig_hme0=dhcp >> /etc/rc.conf && ssh-keygen -A && echo noipv6rs >> /etc/dhcpcd.conf && dhcpcd hme0 && export PKG_PATH=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/sparc64/10.1/All && pkg_add sudo && mkdir -p /usr/pkg/etc && echo "ci ALL=(ALL) NOPASSWD: ALL" > /usr/pkg/etc/sudoers && echo "ci ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers; }; echo PROVISION_EXIT=$?' \
        boot \
        "{{NETBSD_SPARC64_URL}}"
    just _action "Converting wd0.img → qcow2"
    rm -f "{{NETBSD_SPARC64_QCOW}}"
    qemu-img convert -f raw -O qcow2 "$workdir/wd0.img" "{{NETBSD_SPARC64_QCOW}}"
    #
    # Phase B: boot the qcow2 normally (persistent writes), ssh in as root, run
    # pkgin install. If this fails, re-run this recipe — anita is skipped
    # because its workdir cache is intact, and only Phase B repeats. Note: we
    # install cmake/rsync/jemalloc/bash but NOT pkgsrc gcc — the system gcc
    # from comp.tar.xz is what supports -m32 multilib for the vm32 build.
    #
    just _action "Phase B: booting qcow2 to install pkgsrc packages"
    PORT=$(just _free-port)
    trap '[ -f netbsd-sparc64-provision.pid ] && kill "$(cat netbsd-sparc64-provision.pid)" 2>/dev/null; rm -f netbsd-sparc64-provision.pid' EXIT
    qemu-system-sparc64 \
        -M sun4u \
        -m 2G \
        -drive file={{NETBSD_SPARC64_QCOW}},if=ide,bus=0,unit=0,media=disk \
        -nic user,model=sunhme,hostfwd=tcp::${PORT}-:22 \
        -pidfile netbsd-sparc64-provision.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _action "Installing pkgsrc packages via SSH as root"
    sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -p "$PORT" ci@localhost \
        'export PATH=/usr/sbin:/sbin:/usr/bin:/bin:/usr/pkg/sbin:/usr/pkg/bin && export PKG_PATH=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/sparc64/10.1/All && (ifconfig hme0 | grep -q "inet " || sudo dhcpcd hme0) && sudo env PKG_PATH=$PKG_PATH pkg_add pkgin && echo "$PKG_PATH" | sudo tee /usr/pkg/etc/pkgin/repositories.conf > /dev/null && sudo env PKG_PATH=$PKG_PATH pkgin -y update && sudo env PKG_PATH=$PKG_PATH pkgin -y install cmake rsync jemalloc bash vim-share'
    #
    # Install 32-bit X11 libraries from the NetBSD/sparc release sets. sparc64
    # xbase ships only 64-bit X11; the kernel runs 32-bit sparc binaries via
    # COMPAT_NETBSD32, but we need 32-bit libX11/libXext/etc. to link against.
    #
    # The .so files in sparc xbase are super-stripped (e_shstrndx zeroed,
    # truncated section header table) — usable by the dynamic loader at
    # runtime but not by ld(1) at link time. So we pull both xbase (for the
    # .so symlink chain that cmake's find_package(X11) keys off of) AND
    # xcomp (for the .a static archives), then replace the broken libX11.so
    # / libXext.so files with linker scripts that GROUP-include the static
    # archives and their transitive deps. The final Self binary has X11
    # statically linked.
    #
    # Replaces each super-stripped lib*.so symlink with a GNU ld linker script
    # that GROUPs every X11 .a archive we have plus xcb/Xau/Xdmcp and dynamic
    # system libs (expat, z). ld pulls in only archive members that resolve
    # undefined symbols, so this universal script works for any -l<X11lib>.
    just _action "Installing 32-bit X11 libs from NetBSD/sparc xbase + xcomp"
    sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -p "$PORT" ci@localhost \
        'set -e; cd /tmp && ftp -4 -V -o xbase-sparc.tgz http://ftp.netbsd.org/pub/NetBSD/NetBSD-10.1/sparc/binary/sets/xbase.tgz && ftp -4 -V -o xcomp-sparc.tgz http://ftp.netbsd.org/pub/NetBSD/NetBSD-10.1/sparc/binary/sets/xcomp.tgz && sudo rm -rf /tmp/sparc-xbase /tmp/sparc-xcomp && sudo mkdir -p /tmp/sparc-xbase /tmp/sparc-xcomp /usr/X11R7/lib/sparc && sudo tar -xzf /tmp/xbase-sparc.tgz -C /tmp/sparc-xbase && sudo tar -xzf /tmp/xcomp-sparc.tgz -C /tmp/sparc-xcomp && sudo sh -c "cd /tmp/sparc-xbase/usr/X11R7/lib && cp -P lib*.so* /usr/X11R7/lib/sparc/" && sudo sh -c "cd /tmp/sparc-xcomp/usr/X11R7/lib && cp lib*.a /usr/X11R7/lib/sparc/" && SPARC=/usr/X11R7/lib/sparc && LIBS="X11 Xext Xft Xrender fontconfig freetype ICE SM Xt Xmu Xcursor Xfixes Xi Xrandr Xinerama Xpm Xtst" && ALL_A="" && for lib in $LIBS; do [ -f "$SPARC/lib$lib.a" ] && ALL_A="$ALL_A $SPARC/lib$lib.a"; done && COMMON="$SPARC/libxcb.a $SPARC/libXau.a $SPARC/libXdmcp.a -lexpat -lz" && for lib in $LIBS; do if [ -f "$SPARC/lib$lib.a" ]; then sudo rm -f "$SPARC/lib$lib.so" && echo "GROUP ( $ALL_A $COMMON )" | sudo tee "$SPARC/lib$lib.so" > /dev/null; fi; done && sudo rm -rf /tmp/sparc-xbase /tmp/sparc-xcomp /tmp/xbase-sparc.tgz /tmp/xcomp-sparc.tgz'
    #
    # Build a 32-bit phkmalloc to replace libc's jemalloc. Self's SPARC JIT
    # clobbers %g7, which the ELF ABI reserves for TLS — jemalloc reads TLS
    # and crashes. phkmalloc (resurrected from NetBSD's old libc) is TLS-free.
    # See https://github.com/russellallen/self/issues/149. Pinned revision so
    # the image stays reproducible. sbrk.c is intentionally omitted: it's a
    # Linux-only shim that would collide with NetBSD libc's sbrk(2). Empty
    # extern.h / reentrant.h stubs satisfy malloc.c's NetBSD #include block —
    # those are libc-private headers, not in /usr/include, and their content
    # is only referenced under _LIBC / _REENTRANT, neither of which we set.
    #
    just _action "Building 32-bit phkmalloc (per upstream issue #149)"
    sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -p "$PORT" ci@localhost \
        'set -e; cd /tmp && rm -rf phkmalloc-build && mkdir phkmalloc-build && ftp -4 -V -o phkmalloc.tar.gz https://hg.sr.ht/~nbuwe/phkmalloc/archive/2ba4f8a0641ac4e232c252de4ee58879c506878c.tar.gz && tar -xzf phkmalloc.tar.gz -C phkmalloc-build --strip-components=1 && cd phkmalloc-build && : > extern.h && : > reentrant.h && cc -m32 -O2 -fno-strict-aliasing -I. -c malloc.c aligned_alloc.c memalign.c valloc.c && ar cr libphkmalloc.a malloc.o aligned_alloc.o memalign.o valloc.o && sudo cp libphkmalloc.a /usr/lib/sparc/libphkmalloc.a && cd /tmp && rm -rf phkmalloc-build phkmalloc.tar.gz'
    just _action "Shutting down VM"
    just _stop-vm netbsd-sparc64-provision.pid "$PORT"
    just _banner "NetBSD sparc64 image ready"

# Download and provision Alpine x86 (32-bit, musl, for vm32)
#
# Alpine publishes no 32-bit cloud images, so this drives an unattended
# setup-alpine install from the virt ISO over the QEMU serial console with
# expect. Two phases, mirroring the NetBSD recipes:
#
#   Phase A: boot the ISO with a blank disk, run `setup-alpine -e -f answers`
#     (-e = empty root password, so no interactive prompts; USEROPTS=none and
#     ERASE_DISKS are honored non-interactively — verified against
#     alpine-conf's setup-alpine.in/setup-user.in/setup-disk.in). Then chroot
#     into the installed disk to create the ci user, install bash+sudo, and
#     allow ssh password auth. Result: alpine-x86-install.qcow2.
#   Phase B: boot that image, ssh in as ci, apk add the build deps.
#
# Each phase's output file only appears on success, so a re-run resumes at
# the first incomplete phase; the final qcow2 lands atomically at the end.
# Delete images/alpine-x86*.qcow2 to force a full re-provision.
[group('Provision')]
provision-alpine-x86:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images
    if [ -f "{{ALPINE_X86_QCOW}}" ]; then
        just _action "Image already exists: {{ALPINE_X86_QCOW}} (delete to force re-provision)"
        just _banner "Alpine x86 image ready"
        exit 0
    fi
    iso="images/alpine-virt-x86.iso"
    install_img="images/alpine-x86-install.qcow2"
    if [ ! -f "$iso" ]; then
        just _action "Downloading Alpine x86 virt ISO"
        curl -L -o "$iso" "{{ALPINE_X86_ISO_URL}}"
    else
        echo "Cached download already exists: $iso"
    fi
    if [ -f "$install_img" ]; then
        just _action "Phase A already complete ($install_img exists) — skipping to Phase B"
    else
        just _action "Phase A: unattended setup-alpine install via serial console (TCG, ~10-20 min)"
        rm -f "$install_img.tmp"
        qemu-img create -f qcow2 "$install_img.tmp" 8G
        ALPINE_ISO="$iso" ALPINE_DISK="$install_img.tmp" \
        ALPINE_COMMUNITY_URL="{{ALPINE_X86_COMMUNITY_URL}}" \
        expect <<'INSTALL_EXPECT'
        set timeout 420
        log_user 1
        set send_slow {10 .01}

        proc die {msg} { puts "\nPROVISION-FAIL: $msg"; exit 1 }
        proc sends {line} { global send_slow; send -s -- "$line\r" }
        # Run a command and require its success marker. The marker is split in
        # the typed command (CI_"OK_n") so the serial echo of the command
        # itself can never match the expect pattern — only real output can.
        # On eof, report how qemu ended (exit code vs signal) before dying.
        proc die_eof {msg} {
            catch { puts "\nspawn wait status: [wait]" }
            die $msg
        }
        proc run_ok {cmd n} {
            sends "$cmd && echo CI_\"OK_$n\""
            expect {
                "CI_OK_$n" { }
                timeout { die "command failed or timed out: $cmd" }
                eof     { die_eof "qemu exited during: $cmd" }
            }
        }

        spawn qemu-system-x86_64 \
            -machine q35 -cpu max \
            -m 2G -smp 2 \
            -drive file=$env(ALPINE_DISK),if=virtio \
            -cdrom $env(ALPINE_ISO) \
            -boot d \
            -nic user \
            -nographic

        # The live ISO logs root straight in with no password.
        expect {
            "login:" { send "root\r" }
            timeout  { die "no login prompt from live ISO" }
            eof      { die "qemu exited before login prompt" }
        }
        expect {
            -re {~# } { }
            timeout   { die "no root shell on live ISO" }
            eof       { die "qemu exited before root shell" }
        }

        sends "cat > /tmp/answers <<'CI_ANSWERS'"
        sends "KEYMAPOPTS=none"
        sends "HOSTNAMEOPTS=alpine-ci"
        sends "DEVDOPTS=mdev"
        sends "INTERFACESOPTS=\"auto lo"
        sends "iface lo inet loopback"
        sends ""
        sends "auto eth0"
        sends "iface eth0 inet dhcp"
        sends "\""
        sends "DNSOPTS=\"\""
        sends "TIMEZONEOPTS=UTC"
        sends "PROXYOPTS=none"
        sends "APKREPOSOPTS=-1"
        sends "USEROPTS=none"
        sends "SSHDOPTS=openssh"
        sends "NTPOPTS=busybox"
        sends "DISKOPTS=\"-m sys /dev/vda\""
        sends "LBUOPTS=none"
        sends "APKCACHEOPTS=none"
        sends "ERASE_DISKS=/dev/vda"
        sends "CI_ANSWERS"
        expect {
            -re {~# } { }
            timeout   { die "no shell prompt after writing answerfile" }
        }

        # -e leaves the root password empty so nothing prompts; defensive
        # branches below handle prompts anyway in case a future alpine-conf
        # changes behavior. Long timeout: TCG + package download + disk write.
        sends "setup-alpine -e -f /tmp/answers && echo CI_\"SETUP_DONE\""
        set timeout 1500
        expect {
            -re {New [Pp]assword[^\r\n]*: ?}    { send "ci\r"; exp_continue }
            -re {Retype [Pp]assword[^\r\n]*: ?} { send "ci\r"; exp_continue }
            -re {\(y/n\)[^\r\n]*\[n\] $}        { send "y\r"; exp_continue }
            "CI_SETUP_DONE" { }
            timeout { die "setup-alpine did not complete" }
            eof     { die_eof "qemu exited during setup-alpine" }
        }

        # Post-install: customize the installed disk for the CI contracts
        # (ci/ci ssh login, passwordless sudo, bash for the `do` helper).
        # BIOS sys-mode layout: vda1 /boot, vda2 swap, vda3 /.
        set timeout 300
        run_ok "mount /dev/vda3 /mnt" 1
        run_ok "cp /etc/resolv.conf /mnt/etc/resolv.conf" 2
        run_ok "echo $env(ALPINE_COMMUNITY_URL) >> /mnt/etc/apk/repositories" 3
        run_ok "chroot /mnt apk update" 4
        run_ok "chroot /mnt apk add bash sudo" 5
        run_ok "chroot /mnt adduser -D -s /bin/sh ci" 6
        run_ok "echo ci:ci | chroot /mnt chpasswd" 7
        run_ok "mkdir -p /mnt/etc/sudoers.d" 8
        run_ok "echo 'ci ALL=(ALL) NOPASSWD: ALL' > /mnt/etc/sudoers.d/ci" 9
        run_ok "chmod 440 /mnt/etc/sudoers.d/ci" 10
        run_ok "echo 'PasswordAuthentication yes' >> /mnt/etc/ssh/sshd_config" 11
        run_ok "umount /mnt" 12

        sends "poweroff"
        set timeout 120
        expect {
            eof     { }
            timeout { die "guest did not power off" }
        }
    INSTALL_EXPECT
        mv "$install_img.tmp" "$install_img"
    fi
    #
    # Phase B: boot the installed image (persistent writes), ssh in as ci,
    # install build deps. Re-runnable: apk add is idempotent.
    #
    just _action "Phase B: booting installed image to add build packages"
    PORT=$(just _free-port)
    trap '[ -f alpine-x86-provision.pid ] && kill "$(cat alpine-x86-provision.pid)" 2>/dev/null; rm -f alpine-x86-provision.pid' EXIT
    qemu-system-x86_64 \
        -machine q35 -cpu max \
        -m 2G -smp 2 \
        -drive file="$install_img",if=virtio \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -pidfile alpine-x86-provision.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _action "Installing build packages via apk"
    sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -p "$PORT" ci@localhost \
        'sudo apk update && sudo apk add build-base cmake libx11-dev libxext-dev ncurses-dev pkgconf linux-headers rsync sshfs'
    #
    # Build phkmalloc to replace musl's malloc at link time (same trick as the
    # NetBSD sparc64 recipe, same pinned revision). Self stores C-heap
    # pointers in oop-tagged slots, so malloc must stay below 0x80000000;
    # musl's mallocng mmaps at ~0xb7xxxxxx and musl has no mallopt/__morecore
    # to redirect it. Unlike the sparc64 build, sbrk.c IS included here: it
    # calls __NR_brk directly (musl's own sbrk always fails for n>0), and the
    # kernel brk heap sits just above BSS at ~0x08xxxxxx — bit 31 clear.
    #
    just _action "Building 32-bit phkmalloc (keeps malloc below the oop-tag bit)"
    sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -p "$PORT" ci@localhost \
        'set -e; cd /tmp && rm -rf phkmalloc-build && mkdir phkmalloc-build && wget -q -O phkmalloc.tar.gz https://hg.sr.ht/~nbuwe/phkmalloc/archive/2ba4f8a0641ac4e232c252de4ee58879c506878c.tar.gz && tar -xzf phkmalloc.tar.gz -C phkmalloc-build --strip-components=1 && cd phkmalloc-build && : > extern.h && : > reentrant.h && gcc -O2 -fno-strict-aliasing -I. -c malloc.c sbrk.c aligned_alloc.c memalign.c valloc.c && ar cr libphkmalloc.a malloc.o sbrk.o aligned_alloc.o memalign.o valloc.o && sudo cp libphkmalloc.a /usr/lib/libphkmalloc.a && cd /tmp && rm -rf phkmalloc-build phkmalloc.tar.gz'
    just _action "Shutting down VM"
    just _stop-vm alpine-x86-provision.pid "$PORT"
    mv "$install_img" "{{ALPINE_X86_QCOW}}"
    just _banner "Alpine x86 image ready"

# Download and provision Alpine AMD64 (vm64, musl)
#
# Unlike 32-bit x86, Alpine publishes 64-bit cloud images with cloud-init
# baked in, so this is the same one-boot NoCloud seed-ISO flow as Ubuntu.
[group('Provision')]
provision-alpine-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images
    if [ -f "{{ALPINE_AMD64_QCOW}}" ]; then
        just _action "Image already exists: {{ALPINE_AMD64_QCOW}} (delete to force re-provision)"
    else
        just _action "Downloading Alpine AMD64 cloud image"
        curl -L -o "{{ALPINE_AMD64_QCOW}}" "{{ALPINE_AMD64_URL}}"
        qemu-img resize "{{ALPINE_AMD64_QCOW}}" 20G
        just _create-cloud-init-alpine-amd64
        just _action "Provisioning Alpine AMD64 via cloud-init (will shut down automatically when done)"
        PORT=$(just _free-port)
        qemu-system-x86_64 \
            -machine q35 -cpu Nehalem \
            -m 4G -smp 2 \
            -device virtio-rng-pci \
            -drive file={{ALPINE_AMD64_QCOW}},if=virtio \
            -drive file=images/cloud-init-alpine-amd64.iso,if=virtio,media=cdrom \
            -nic user,hostfwd=tcp::${PORT}-:22 \
            -nographic
    fi
    just _banner "Alpine AMD64 image ready"

# Download and provision Alpine ARM64 (vm64, musl; hvf-accelerated on Apple Silicon)
[group('Provision')]
provision-alpine-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images
    if [ -f "{{ALPINE_ARM64_QCOW}}" ]; then
        just _action "Image already exists: {{ALPINE_ARM64_QCOW}} (delete to force re-provision)"
    else
        just _action "Downloading Alpine ARM64 cloud image"
        curl -L -o "{{ALPINE_ARM64_QCOW}}" "{{ALPINE_ARM64_URL}}"
        qemu-img resize "{{ALPINE_ARM64_QCOW}}" 20G
        just _create-cloud-init-alpine-arm64
        just _action "Provisioning Alpine ARM64 via cloud-init (will shut down automatically when done)"
        PORT=$(just _free-port)
        qemu-system-aarch64 \
            -machine virt -accel hvf -cpu host \
            -m 4G -smp 4 \
            -device virtio-rng-pci \
            -drive file={{ALPINE_ARM64_QCOW}},if=virtio \
            -drive file=images/cloud-init-alpine-arm64.iso,if=virtio,media=cdrom \
            -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
            -nic user,hostfwd=tcp::${PORT}-:22 \
            -nographic
    fi
    just _banner "Alpine ARM64 image ready"

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
            qemu-system-ppc)      echo "brew install qemu" ;;
            qemu-system-sparc64)  echo "brew install qemu" ;;
            qemu-system-x86_64)   echo "brew install qemu" ;;
            rsync)                echo "brew install rsync" ;;
            ssh)                  echo "should be pre-installed on macOS" ;;
            sshpass)              echo "brew install esolitos/ipa/sshpass" ;;
            uv)                   echo "brew install uv  (used to run anita for NetBSD provisioning)" ;;
            xxd)                  echo "included with vim — brew install vim" ;;
            xz)                   echo "brew install xz" ;;
        esac
    }

    for cmd in cmake curl expect gunzip python3 qemu-img qemu-system-aarch64 qemu-system-ppc qemu-system-sparc64 qemu-system-x86_64 rsync ssh sshpass uv xxd xz; do
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

# Boot NetBSD ARM64 VM (snapshot mode, for vm64 + vm32)
#
# Boot model matches anita: -M virt with the kernel passed directly via
# -kernel (no UEFI/edk2). Disk is virtio-blk; root is found by GPT label.
# HVF-accelerated on Apple Silicon: GENERIC64 is a generic ARMv8-A kernel, so
# -cpu host works (the cortex-a57 default was only relevant for TCG emulation).
[group('Advanced')]
start-netbsd-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    just _action "Starting NetBSD ARM64 VM"
    PORT=$(just _free-port)
    echo "$PORT" > netbsd-arm64.port
    qemu-system-aarch64 \
        -M virt,gic-version=3 -accel hvf -cpu host \
        -m 4G -smp 4 \
        -drive file={{NETBSD_ARM64_QCOW}},if=none,id=hd0,snapshot=on \
        -device virtio-blk-device,drive=hd0 \
        -kernel images/netbsd-arm64-kernel.img.gz \
        -append 'root=NAME=netbsd-root' \
        -netdev user,id=net0,hostfwd=tcp::${PORT}-:22 \
        -device virtio-net-pci,netdev=net0 \
        -pidfile netbsd-arm64.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _banner "NetBSD ARM64 VM running on port $PORT"

# Shut down NetBSD ARM64 VM
[group('Advanced')]
stop-netbsd-arm64:
    #!/usr/bin/env bash
    port=$(cat netbsd-arm64.port 2>/dev/null || echo "0")
    just _stop-vm netbsd-arm64.pid "$port"
    rm -f netbsd-arm64.port

# Boot NetBSD macppc VM (snapshot mode, TCG-emulated, for vm32)
[group('Advanced')]
start-netbsd-macppc:
    #!/usr/bin/env bash
    set -euo pipefail
    just _action "Starting NetBSD macppc VM"
    PORT=$(just _free-port)
    echo "$PORT" > netbsd-macppc.port
    qemu-system-ppc \
        -M mac99,via=pmu -cpu G4 \
        -m 2G \
        -drive file={{NETBSD_MACPPC_QCOW}},if=ide,snapshot=on \
        -nic user,model=sungem,hostfwd=tcp::${PORT}-:22 \
        -prom-env "auto-boot?=true" \
        -prom-env "boot-device=hd:,\\ofwboot.xcf" \
        -prom-env "boot-file=netbsd" \
        -pidfile netbsd-macppc.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _banner "NetBSD macppc VM running on port $PORT"

# Shut down NetBSD macppc VM
[group('Advanced')]
stop-netbsd-macppc:
    #!/usr/bin/env bash
    port=$(cat netbsd-macppc.port 2>/dev/null || echo "0")
    just _stop-vm netbsd-macppc.pid "$port"
    rm -f netbsd-macppc.port

# Boot NetBSD sparc64 VM (snapshot mode, TCG-emulated, for vm32 via -m32)
[group('Advanced')]
start-netbsd-sparc64:
    #!/usr/bin/env bash
    set -euo pipefail
    just _action "Starting NetBSD sparc64 VM"
    PORT=$(just _free-port)
    echo "$PORT" > netbsd-sparc64.port
    qemu-system-sparc64 \
        -M sun4u \
        -m 2G \
        -drive file={{NETBSD_SPARC64_QCOW}},if=ide,bus=0,unit=0,media=disk,snapshot=on \
        -nic user,model=sunhme,hostfwd=tcp::${PORT}-:22 \
        -pidfile netbsd-sparc64.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _banner "NetBSD sparc64 VM running on port $PORT"

# Shut down NetBSD sparc64 VM
[group('Advanced')]
stop-netbsd-sparc64:
    #!/usr/bin/env bash
    port=$(cat netbsd-sparc64.port 2>/dev/null || echo "0")
    just _stop-vm netbsd-sparc64.pid "$port"
    rm -f netbsd-sparc64.port

# Boot Alpine x86 VM (snapshot mode, TCG-emulated, for vm32)
#
# -cpu max, not qemu64: Alpine's x86 userland uses SSE4.1 unconditionally
# (librhash's pinsrd SIGILLs cmake under qemu64, which stops at SSE3).
[group('Advanced')]
start-alpine-x86:
    #!/usr/bin/env bash
    set -euo pipefail
    just _action "Starting Alpine x86 VM"
    PORT=$(just _free-port)
    echo "$PORT" > alpine-x86.port
    qemu-system-x86_64 \
        -machine q35 -cpu max \
        -m 2G -smp 2 \
        -drive file={{ALPINE_X86_QCOW}},if=virtio,snapshot=on \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -pidfile alpine-x86.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _banner "Alpine x86 VM running on port $PORT"

# Shut down Alpine x86 VM
[group('Advanced')]
stop-alpine-x86:
    #!/usr/bin/env bash
    port=$(cat alpine-x86.port 2>/dev/null || echo "0")
    just _stop-vm alpine-x86.pid "$port"
    rm -f alpine-x86.port

# Boot Alpine AMD64 VM (snapshot mode, TCG-emulated, for vm64)
#
# -cpu Nehalem, not qemu64: Alpine's userland uses SSE4.1 unconditionally
# (see start-alpine-x86). Nehalem is a fixed model with SSE4.2 — unlike
# -cpu max it doesn't drag in every TCG feature flag.
[group('Advanced')]
start-alpine-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    just _action "Starting Alpine AMD64 VM"
    PORT=$(just _free-port)
    echo "$PORT" > alpine-amd64.port
    qemu-system-x86_64 \
        -machine q35 -cpu Nehalem \
        -m 4G -smp 2 \
        -device virtio-rng-pci \
        -drive file={{ALPINE_AMD64_QCOW}},if=virtio,snapshot=on \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -pidfile alpine-amd64.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _banner "Alpine AMD64 VM running on port $PORT"

# Shut down Alpine AMD64 VM
[group('Advanced')]
stop-alpine-amd64:
    #!/usr/bin/env bash
    port=$(cat alpine-amd64.port 2>/dev/null || echo "0")
    just _stop-vm alpine-amd64.pid "$port"
    rm -f alpine-amd64.port

# Boot Alpine ARM64 VM (snapshot mode)
[group('Advanced')]
start-alpine-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    just _action "Starting Alpine ARM64 VM"
    PORT=$(just _free-port)
    echo "$PORT" > alpine-arm64.port
    qemu-system-aarch64 \
        -machine virt -accel hvf -cpu host \
        -m 4G -smp 4 \
        -device virtio-rng-pci \
        -drive file={{ALPINE_ARM64_QCOW}},if=virtio,snapshot=on \
        -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
        -nic user,hostfwd=tcp::${PORT}-:22 \
        -pidfile alpine-arm64.pid \
        -display none -daemonize
    just _wait-for-ssh "$PORT"
    just _banner "Alpine ARM64 VM running on port $PORT"

# Shut down Alpine ARM64 VM
[group('Advanced')]
stop-alpine-arm64:
    #!/usr/bin/env bash
    port=$(cat alpine-arm64.port 2>/dev/null || echo "0")
    just _stop-vm alpine-arm64.pid "$port"
    rm -f alpine-arm64.port

# Execute command on a running VM via SSH.
# `target` may be either a numeric port, a platform short name
# (e.g. freebsd-arm64), or a full recipe name (e.g. vm64-freebsd-arm64).
# Platform names are resolved to <name>.port in the project directory.
[group('Advanced')]
do target *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    target="{{target}}"
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        port="$target"
    else
        name="${target#vm64-}"
        name="${name#vm32-}"
        portfile="{{justfile_directory()}}/${name}.port"
        if [ ! -f "$portfile" ]; then
            echo "ERROR: $portfile not found — is the '$name' VM running?" >&2
            exit 1
        fi
        port=$(cat "$portfile")
    fi
    cat <<'JUSTEOF'
    > {{ARGS}}
    JUSTEOF
    hex_string=$(xxd -p <<'JUSTEOF' | tr -d '\n'
    {{ARGS}}
    JUSTEOF
    )
    CMD="echo $hex_string | xxd -r -p > /tmp/qemu_cmd ; bash --login /tmp/qemu_cmd"
    # With DISPLAY set (e.g. XQuartz), a race can make ssh prompt via the
    # (nonexistent) X11 askpass helper instead of the pty sshpass watches,
    # failing auth with "Permission denied". Same guard as _rsync.
    unset DISPLAY SSH_ASKPASS
    sshpass -p ci ssh ci@localhost -p "$port" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR "($CMD) 2>&1"

# Copy files to/from a running VM via SCP.
# `target` may be a numeric port, platform short name (e.g. freebsd-arm64),
# or full recipe name (e.g. vm64-freebsd-arm64).
# Paths prefixed with `:` are interpreted as remote (ci@localhost) paths.
# Examples:
#   just scp vm64-freebsd-arm64 ./local.txt :/tmp/remote.txt
#   just scp vm64-freebsd-arm64 :/tmp/remote.txt ./local.txt
[group('Advanced')]
scp target src dst:
    #!/usr/bin/env bash
    set -euo pipefail
    target="{{target}}"
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        port="$target"
    else
        name="${target#vm64-}"
        name="${name#vm32-}"
        portfile="{{justfile_directory()}}/${name}.port"
        if [ ! -f "$portfile" ]; then
            echo "ERROR: $portfile not found — is the '$name' VM running?" >&2
            exit 1
        fi
        port=$(cat "$portfile")
    fi
    src="{{src}}"
    dst="{{dst}}"
    [[ "$src" == :* ]] && src="ci@localhost:${src#:}"
    [[ "$dst" == :* ]] && dst="ci@localhost:${dst#:}"
    unset DISPLAY SSH_ASKPASS  # see `do` recipe
    sshpass -p ci scp -P "$port" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR "$src" "$dst"

# Attach an interactive terminal to a running VM via SSH
[group('Advanced')]
term port:
    sshpass -p ci ssh -t ci@localhost -p {{port}} \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR

# Mount a host directory inside a running VM via reverse SSHFS
[group('Advanced')]
mount port host_dir guest_dir='/mnt/host':
    #!/usr/bin/env bash
    set -euo pipefail
    RAW="{{host_dir}}"
    RAW="${RAW/#\~/$HOME}"
    HOST_DIR=$(cd "$RAW" 2>/dev/null && pwd) || { just _fail "host directory not found: {{host_dir}}"; exit 1; }
    just _ensure-mount-key
    just _ensure-mount-sshd
    HOST_USER=$(whoami)
    SSHD_PORT=$(cat mount.sshd.port)
    just _action "Mounting $HOST_DIR → {{guest_dir}} on port {{port}}"
    sshpass -p ci scp -P {{port}} \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        mount.key ci@localhost:/tmp/mount.key
    just do {{port}} "chmod 600 /tmp/mount.key"
    SSHFS_OPTS="allow_other,IdentityFile=/tmp/mount.key,StrictHostKeyChecking=accept-new,UserKnownHostsFile=/dev/null,reconnect,port=${SSHD_PORT}"
    REMOTE="${HOST_USER}@10.0.2.2:${HOST_DIR}"
    SCRIPT=$(cat <<EOF
    set -e
    sudo mkdir -p {{guest_dir}}
    OS=\$(uname -s)
    if [ "\$OS" = Linux ]; then
        command -v sshfs >/dev/null || { echo "ERROR: sshfs missing in guest; re-provision the VM image (rm images/<vm>.qcow2 && just provision-<vm>)" >&2; exit 1; }
        sudo sshfs -o ${SSHFS_OPTS} ${REMOTE} {{guest_dir}}
    elif [ "\$OS" = FreeBSD ]; then
        command -v sshfs >/dev/null || { echo "ERROR: fusefs-sshfs missing in guest; re-provision the VM image (rm images/<vm>.qcow2 && just provision-<vm>)" >&2; exit 1; }
        kldstat -q -m fusefs || { echo "ERROR: fusefs module not loaded; re-provision the VM so /boot/loader.conf has fusefs_load=YES" >&2; exit 1; }
        sudo sshfs -o ${SSHFS_OPTS} ${REMOTE} {{guest_dir}}
    elif [ "\$OS" = NetBSD ]; then
        sudo mount_psshfs -O Port=${SSHD_PORT} -O IdentityFile=/tmp/mount.key -O StrictHostKeyChecking=accept-new -O UserKnownHostsFile=/dev/null ${REMOTE} {{guest_dir}}
    else
        echo "unsupported guest OS: \$OS" >&2
        exit 1
    fi
    EOF
    )
    just do {{port}} "$SCRIPT"
    just _banner "Mounted $HOST_DIR → {{guest_dir}} on port {{port}}"

# Unmount a previously mounted host directory inside a running VM
[group('Advanced')]
unmount port guest_dir='/mnt/host':
    #!/usr/bin/env bash
    set -euo pipefail
    just _action "Unmounting {{guest_dir}} on port {{port}}"
    just do {{port}} "sudo umount {{guest_dir}}"
    just _banner "Unmounted {{guest_dir}} on port {{port}}"

# Stop the project-local sshd that backs `just mount`
[group('Advanced')]
mount-sshd-stop:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -f mount.sshd.pid ] && kill -0 "$(cat mount.sshd.pid)" 2>/dev/null; then
        kill "$(cat mount.sshd.pid)" 2>/dev/null || true
        just _banner "Stopped project sshd"
    fi
    rm -f mount.sshd.pid mount.sshd.port

# Show the status of the project-local sshd
[group('Advanced')]
mount-sshd-status:
    #!/usr/bin/env bash
    if [ -f mount.sshd.pid ] && kill -0 "$(cat mount.sshd.pid)" 2>/dev/null; then
        echo "running   pid=$(cat mount.sshd.pid)   port=$(cat mount.sshd.port 2>/dev/null || echo ?)"
    else
        echo "not running"
    fi

_ensure-mount-key:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f mount.key ]; then
        ssh-keygen -t ed25519 -N '' -C 'self-ci mount key' -f mount.key >/dev/null
    fi

_ensure-mount-sshd:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -f mount.sshd.pid ] && kill -0 "$(cat mount.sshd.pid)" 2>/dev/null; then
        exit 0
    fi
    rm -f mount.sshd.pid mount.sshd.port
    if [ ! -f mount.host_key ]; then
        ssh-keygen -t ed25519 -N '' -C 'self-ci mount host key' -f mount.host_key >/dev/null
    fi
    cp mount.key.pub mount.authorized_keys
    chmod 600 mount.authorized_keys mount.host_key
    ABS=$(pwd)
    USER_NAME=$(whoami)
    cat > mount.sshd_config <<EOF
    HostKey                         ${ABS}/mount.host_key
    AuthorizedKeysFile              ${ABS}/mount.authorized_keys
    PidFile                         ${ABS}/mount.sshd.pid
    ListenAddress                   127.0.0.1
    PasswordAuthentication          no
    KbdInteractiveAuthentication    no
    ChallengeResponseAuthentication no
    PubkeyAuthentication            yes
    PermitRootLogin                 no
    UsePAM                          no
    StrictModes                     no
    AllowUsers                      ${USER_NAME}
    LogLevel                        INFO
    Subsystem                       sftp /usr/libexec/sftp-server
    EOF
    PORT=$(just _free-port)
    echo "$PORT" > mount.sshd.port
    just _action "Starting project sshd on 127.0.0.1:${PORT}"
    /usr/sbin/sshd -D -e -f "${ABS}/mount.sshd_config" -p "${PORT}" >mount.sshd.log 2>&1 &
    SSHD_PID=$!
    echo "$SSHD_PID" > mount.sshd.pid
    for i in $(seq 1 30); do
        if nc -z 127.0.0.1 "$PORT" 2>/dev/null; then exit 0; fi
        if ! kill -0 "$SSHD_PID" 2>/dev/null; then
            just _fail "project sshd died at startup; tail of mount.sshd.log:"
            tail -20 mount.sshd.log >&2 || true
            rm -f mount.sshd.pid mount.sshd.port
            exit 1
        fi
        sleep 0.1
    done
    just _fail "project sshd not listening within 3s"
    tail -20 mount.sshd.log >&2 || true
    exit 1

# Delete all images and logs
[group('Advanced')]
reset-everything:
    -just mount-sshd-stop
    rm -rf images/ logs/ build/
    rm -f *.pid *.port mount.*
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

# Optional `iterations` arg controls the wait budget (each iteration ≈ 2 s).
# 180 iterations ≈ 360 s is enough for booting a pre-provisioned image, but
# first-time cloud-init on TCG-emulated FreeBSD amd64 routinely takes longer —
# pass a larger value from those provisioning recipes.
_wait-for-ssh port iterations='180':
    #!/usr/bin/env bash
    for i in $(seq 1 {{iterations}}); do
        if sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 -o LogLevel=ERROR -p {{port}} ci@localhost "echo ready" 2>/dev/null; then
            exit 0
        fi
        sleep 2
    done
    echo "ERROR: SSH not available on port {{port}} after $(( {{iterations}} * 2 )) seconds"
    exit 1

_stop-vm pidfile port:
    #!/usr/bin/env bash
    sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -p {{port}} ci@localhost "sudo sync; sudo sync; { sudo poweroff 2>/dev/null || sudo /sbin/shutdown -hp now; }" 2>/dev/null || true
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
      - sshfs

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
      - sshfs

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
      - sshfs

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

# Alpine's cloud-init supports the same modules we use for Ubuntu (users,
# ssh_pwauth, packages via apk, power_state via busybox poweroff). bash and
# sudo are not in the base image, and both are CI contracts (`do` runs
# `bash --login`; the ci user needs NOPASSWD sudo).
#
# Three Alpine-specific extras, all discovered the hard way:
#  - datasource_list pin: without it, later seedless boots re-run the full
#    datasource search and block sshd behind ~4 min of EC2 metadata retries.
#  - sshd dropin: the image's sshd is the openssh-server-pam build with a
#    broken PAM stack (/etc/pam.d/sshd includes base-auth, which doesn't
#    exist), so kbd-interactive auth always fails; force plain password auth.
#  - console reorder runcmd: the stock cmdline ends in console=tty0, sending
#    all post-initramfs output to the (invisible) framebuffer; make the
#    serial console last so openrc/getty are visible in CI serial logs.
_create-cloud-init-alpine-amd64:
    #!/usr/bin/env bash
    set -euo pipefail
    iso="images/cloud-init-alpine-amd64.iso"
    [ -f "$iso" ] && exit 0
    mkdir -p images
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    cat > "$tmpdir/meta-data" <<'EOF'
    instance-id: ci-vm-alpine-amd64
    local-hostname: ci-vm-alpine-amd64
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

    write_files:
      - path: /etc/cloud/cloud.cfg.d/99-ci-datasource.cfg
        content: |
          datasource_list: [ NoCloud, None ]
      - path: /etc/ssh/sshd_config.d/40-ci-passwordauth.conf
        content: |
          PasswordAuthentication yes
          KbdInteractiveAuthentication no

    package_update: true
    packages:
      - bash
      - sudo
      - build-base
      - cmake
      - libx11-dev
      - libxext-dev
      - ncurses-dev
      - pkgconf
      - linux-headers
      - rsync
      - sshfs

    runcmd:
      - sed -i 's/console=ttyS0,115200n8 console=ttyAMA0,115200n8 console=tty0/console=tty0 console=ttyAMA0,115200n8 console=ttyS0,115200n8/' /boot/extlinux.conf

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

# Same three Alpine extras as the amd64 seed (see comment there); the console
# reorder targets grub.cfg since the aarch64 image boots via grub-efi.
_create-cloud-init-alpine-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    iso="images/cloud-init-alpine-arm64.iso"
    [ -f "$iso" ] && exit 0
    mkdir -p images
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    cat > "$tmpdir/meta-data" <<'EOF'
    instance-id: ci-vm-alpine-arm64
    local-hostname: ci-vm-alpine-arm64
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

    write_files:
      - path: /etc/cloud/cloud.cfg.d/99-ci-datasource.cfg
        content: |
          datasource_list: [ NoCloud, None ]
      - path: /etc/ssh/sshd_config.d/40-ci-passwordauth.conf
        content: |
          PasswordAuthentication yes
          KbdInteractiveAuthentication no

    package_update: true
    packages:
      - bash
      - sudo
      - build-base
      - cmake
      - libx11-dev
      - libxext-dev
      - ncurses-dev
      - pkgconf
      - linux-headers
      - rsync
      - sshfs

    runcmd:
      - sed -i 's/console=ttyS0,115200n8 console=ttyAMA0,115200n8 console=tty0/console=tty0 console=ttyS0,115200n8 console=ttyAMA0,115200n8/' /boot/grub/grub.cfg /etc/default/grub

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
      - fusefs-sshfs

    runcmd:
      - ssh-keygen -A
      - sed -i '' 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
      - sysrc sshd_enable=YES
      - sysrc -f /boot/loader.conf fusefs_load=YES
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
      - fusefs-sshfs
      # gcc14: stock LLVM clang on FreeBSD 15 (clang 19) generates a Self vm64
      # interpreter whose recursion blows the Self process stack during world
      # boot. gcc14 fits the same code in the default 5 MB SelfStackLimit.
      - gcc14

    runcmd:
      - ssh-keygen -A
      - sed -i '' 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
      - sysrc sshd_enable=YES
      - sysrc -f /boot/loader.conf fusefs_load=YES
      - service sshd start
      # Verify every requested package actually got installed. nuageinit's
      # `packages:` handler has been observed to silently drop items under
      # TCG-emulated load (lost pkgconf and libXext on amd64). The marker is
      # only touched when every package is present; the provisioning recipe
      # polls for /var/run/self-ci-provisioned and aborts if it's missing.
      - for p in cmake rsync bash xxd pkgconf sudo libX11 libXext ncurses fusefs-sshfs gcc14; do pkg info -e $p || exit 0; done; touch /var/run/self-ci-provisioned
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
      - fusefs-sshfs
      # Stock LLVM clang (FreeBSD 15 ships clang 19) generates an interpreter
      # for vm64 whose recursion blows the Self process stack during world
      # boot. gcc14 fits the same code in the default 5 MB SelfStackLimit.
      - gcc14

    runcmd:
      - ssh-keygen -A
      - sed -i '' 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
      - sysrc sshd_enable=YES
      - sysrc -f /boot/loader.conf fusefs_load=YES
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

# Write a per-build status sidecar consumed by _generate-report.
# Format: RESULT|ELAPSED_SEC|ARTIFACT_BASENAME|COMMIT|REMOTE_URL
# COMMIT may be empty (src not a git repo) or have a "-dirty" suffix.
# REMOTE_URL may be empty (no origin) or non-GitHub.
[private]
_record-status name result elapsed artifact:
    #!/usr/bin/env bash
    set -uo pipefail
    mkdir -p "{{justfile_directory()}}/artifacts/logs"
    SRCDIR="{{SRCDIR}}"
    COMMIT=""
    REMOTE=""
    if [ -n "$SRCDIR" ] && git -C "$SRCDIR" rev-parse --git-dir >/dev/null 2>&1; then
        COMMIT=$(git -C "$SRCDIR" rev-parse HEAD 2>/dev/null || true)
        if [ -n "$COMMIT" ]; then
            if ! git -C "$SRCDIR" diff --quiet 2>/dev/null || ! git -C "$SRCDIR" diff --cached --quiet 2>/dev/null; then
                COMMIT="${COMMIT}-dirty"
            fi
        fi
        REMOTE=$(git -C "$SRCDIR" remote get-url origin 2>/dev/null || true)
    fi
    printf '%s|%s|%s|%s|%s\n' "{{result}}" "{{elapsed}}" "{{artifact}}" "$COMMIT" "$REMOTE" \
        > "{{justfile_directory()}}/artifacts/logs/{{name}}.status"

# Generate artifacts/index.html from the status sidecars and log files.
# Idempotent — safe to call from any vm*-<platform> recipe.
[private]
_generate-report:
    #!/usr/bin/env bash
    set -euo pipefail
    REPORT_DIR="{{justfile_directory()}}/artifacts"
    LOGS_DIR="$REPORT_DIR/logs"
    OUT="$REPORT_DIR/index.html"
    mkdir -p "$LOGS_DIR"

    shopt -s nullglob
    statuses=("$LOGS_DIR"/*.status)
    shopt -u nullglob

    # ANSI-strip + HTML-escape in a single python invocation.
    sanitize() { python3 -c 'import html, re, sys; s = sys.stdin.read(); s = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", s); sys.stdout.write(html.escape(s))'; }

    # Convert a git remote URL + commit sha into a GitHub commit URL.
    # Prints nothing when the remote isn't recognised as GitHub.
    # Strips any "-dirty" suffix from the sha before building the URL.
    github_commit_url() {
        local remote=$1 sha=$2 path=""
        case "$remote" in
            git@github.com:*)     path=${remote#git@github.com:} ;;
            https://github.com/*) path=${remote#https://github.com/} ;;
            *) return ;;
        esac
        path=${path%.git}
        printf 'https://github.com/%s/commit/%s' "$path" "${sha%-dirty}"
    }

    passes=0; fails=0
    if [ "${#statuses[@]}" -gt 0 ]; then
        for sf in "${statuses[@]}"; do
            r=$(cut -d'|' -f1 "$sf")
            case "$r" in PASS) passes=$((passes+1));; FAIL|TIMEOUT) fails=$((fails+1));; esac
        done
    fi

    now=$(date '+%Y-%m-%d %H:%M')
    selfsrc_html=$(printf '%s' "${SELFSRC:-}" | sanitize)
    [ -z "$selfsrc_html" ] && selfsrc_html='<span class="muted">(unset)</span>'

    {
        cat <<'HEADER'
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <title>Self CI — Build Report</title>
    <style>
    :root { color-scheme: light dark; }
    body { font: 14px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; max-width: 1100px; margin: 2rem auto; padding: 0 1rem; }
    h1 { margin: 0 0 0.25rem; font-size: 1.5rem; }
    .meta { color: #666; margin: 0 0 1.5rem; }
    table { border-collapse: collapse; width: 100%; }
    th, td { padding: 0.5rem 0.75rem; border-bottom: 1px solid #ddd; text-align: left; vertical-align: top; }
    th { background: rgba(127,127,127,0.08); font-weight: 600; }
    code { font: 13px ui-monospace, "SF Mono", Menlo, monospace; }
    .badge { display: inline-block; padding: 0.1em 0.65em; border-radius: 0.4em; font-weight: 600; font-size: 0.82em; letter-spacing: 0.02em; }
    .pass { background: #cfecd0; color: #1b5e20; }
    .fail { background: #f6cccc; color: #8b0000; }
    .timeout { background: #fde7b3; color: #7a4a00; }
    .muted { color: #888; }
    .dur, .when, .commit { white-space: nowrap; }
    .links a { margin-right: 0.9em; }
    .empty { color: #888; font-style: italic; }
    @media (prefers-color-scheme: dark) {
        body { background: #1a1a1a; color: #ddd; }
        th { background: rgba(255,255,255,0.05); }
        th, td { border-color: #333; }
        .meta, .muted { color: #999; }
        .pass { background: #2c5d3e; color: #d4f0d8; }
        .fail { background: #5d2c2c; color: #f4d0d0; }
        .timeout { background: #5d4a1e; color: #f5e2b1; }
        a { color: #8ab4f8; }
    }
    </style>
    </head>
    <body>
    <h1>Self CI — Build Report</h1>
    HEADER
        printf '<p class="meta">Source: <code>%s</code> · Generated: %s · <strong>%d</strong> passed / <strong>%d</strong> failed</p>\n' \
            "$selfsrc_html" "$now" "$passes" "$fails"

        if [ "${#statuses[@]}" -eq 0 ]; then
            cat <<'EMPTY'
    <p class="empty">No builds recorded yet. Run <code>just fullrun-all</code> (or a single platform recipe like <code>just vm64-ubuntu-arm64</code>).</p>
    EMPTY
        else
            cat <<'THEAD'
    <table>
    <thead><tr><th>Platform</th><th>Status</th><th>Duration</th><th>Last run</th><th>Commit</th><th>Links</th></tr></thead>
    <tbody>
    THEAD
            # Stable order: sort by filename
            sorted=$(printf '%s\n' "${statuses[@]}" | sort)
            while IFS= read -r sf; do
                name=$(basename "$sf" .status)
                IFS='|' read -r result elapsed artifact commit remote < "$sf" || true
                mins=$((elapsed / 60))
                secs=$((elapsed % 60))
                mtime=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$sf" 2>/dev/null || date '+%Y-%m-%d %H:%M')
                case "$result" in
                    PASS)    badge_class="pass" ;;
                    TIMEOUT) badge_class="timeout" ;;
                    *)       badge_class="fail" ;;
                esac
                name_html=$(printf '%s' "$name" | sanitize)
                artifact_html=$(printf '%s' "$artifact" | sanitize)
                # Commit cell: short hash, optionally linked to GitHub.
                if [ -n "$commit" ]; then
                    bare=${commit%-dirty}
                    short=${bare:0:7}
                    [ "$commit" != "$bare" ] && short="${short}-dirty"
                    short_html=$(printf '%s' "$short" | sanitize)
                    commit_url=$(github_commit_url "$remote" "$commit")
                    if [ -n "$commit_url" ]; then
                        commit_cell="<td class=\"commit\"><a href=\"$(printf '%s' "$commit_url" | sanitize)\"><code>$short_html</code></a></td>"
                    else
                        commit_cell="<td class=\"commit\"><code>$short_html</code></td>"
                    fi
                else
                    commit_cell='<td class="commit muted">—</td>'
                fi
                printf '<tr>\n'
                printf '  <td><code>%s</code></td>\n' "$name_html"
                printf '  <td><span class="badge %s">%s</span></td>\n' "$badge_class" "$result"
                printf '  <td class="dur">%dm %02ds</td>\n' "$mins" "$secs"
                printf '  <td class="when">%s</td>\n' "$mtime"
                printf '  %s\n' "$commit_cell"
                printf '  <td class="links">\n'
                printf '    <a href="logs/%s.log">View log</a>\n' "$name_html"
                if [ "$result" = PASS ] && [ -n "$artifact" ]; then
                    printf '    <a href="%s">Download</a>\n' "$artifact_html"
                fi
                printf '  </td>\n'
                printf '</tr>\n'
            done <<< "$sorted"
            cat <<'TFOOT'
    </tbody>
    </table>
    TFOOT
        fi
        cat <<'FOOTER'
    </body>
    </html>
    FOOTER
    } > "$OUT"
    just _action "Report: $OUT"
