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

# vm platforms (32-bit multilib on AMD64)
UBUNTU_MULTILIB_QCOW := 'images/ubuntu-amd64-multilib.qcow2'

# ─── Download URLs ────────────────────────────────────────

UBUNTU_ARM64_URL   := 'https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img'
UBUNTU_AMD64_URL   := 'https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img'

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

# ═══════════════════════════════════════════════════════════
#  Provision — Download and provision VM images
# ═══════════════════════════════════════════════════════════

# Download and provision all VM images
[group('Provision')]
provision-all: provision-ubuntu-arm64 provision-ubuntu-amd64 provision-ubuntu-amd64-multilib
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
            xxd)                  echo "included with vim — brew install vim" ;;
            xz)                   echo "brew install xz" ;;
        esac
    }

    for cmd in cmake curl expect gunzip python3 qemu-img qemu-system-aarch64 qemu-system-x86_64 rsync ssh sshpass xxd xz; do
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
    for i in $(seq 1 60); do
        if sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 -o LogLevel=ERROR -p {{port}} ci@localhost "echo ready" 2>/dev/null; then
            exit 0
        fi
        sleep 2
    done
    echo "ERROR: SSH not available on port {{port}} after 120 seconds"
    exit 1

_stop-vm pidfile port:
    #!/usr/bin/env bash
    sshpass -p ci ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -p {{port}} ci@localhost "sudo poweroff" 2>/dev/null || true
    if [ -f {{pidfile}} ]; then
        pid=$(cat {{pidfile}})
        for i in $(seq 1 30); do
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

_pass *ARGS:
    @echo "$(tput setaf 2)$(tput bold)[$(date +%H:%M:%S)] PASS: {{ARGS}}$(tput sgr0)"

_fail *ARGS:
    @echo "$(tput setaf 1)$(tput bold)[$(date +%H:%M:%S)] FAIL: {{ARGS}}$(tput sgr0)"

_banner *ARGS:
    @echo "$(tput setaf 2)$(tput bold)[$(date +%H:%M:%S)] {{ARGS}}$(tput sgr0)"

_action *ARGS:
    @echo "$(tput setaf 208)$(tput bold)[$(date +%H:%M:%S)] {{ARGS}}$(tput sgr0)"
