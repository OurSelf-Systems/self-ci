# Local CI — Technical Manual

## Architecture overview

The CI system boots QEMU virtual machines, rsyncs the source tree in, runs `cmake` + `make`, and reports pass/fail. All recipes live in `Justfile` at the repository root.

It supports two VM codebases:
- **vm64** (64-bit) — builds on macOS native, Ubuntu ARM64, Ubuntu AMD64, FreeBSD ARM64, FreeBSD AMD64, NetBSD AMD64
- **vm32** (32-bit) — builds on Ubuntu AMD64 multilib, FreeBSD AMD64 lib32 chroot, NetBSD i386, NetBSD macppc, NetBSD sparc64 (via `-m32`)

```
self-ci/
├── Justfile             Unified CI — all recipes (provisioning is inline)
├── src/                 Source trees (gitignored)
│   └── self64@current/  Example: a self64 checkout
├── images/              VM disk images and generated cloud-init ISOs (gitignored)
├── build/               Local build output (gitignored)
├── artifacts/           Compiled binaries (gitignored)
└── logs/                Build logs (gitignored)
```

Provisioning is no longer driven by external scripts. Ubuntu and FreeBSD images are configured via cloud-init seed ISOs that the `_create-cloud-init-*` recipes (in the Justfile) build under `images/`. NetBSD images are installed by Anita, invoked via `uv` from the Justfile.

## How VM builds work

1. **Starts QEMU** — Boots the VM in the background with `-snapshot` mode and `-daemonize`. A PID file is written for clean shutdown.

2. **Waits for SSH** — Polls SSH on the forwarded port for up to 360 seconds (180 × 2 s).

3. **Rsyncs source** — Copies the entire source tree into `/tmp/self-build` inside the VM, excluding `build/`, `build-*/`, `*.o`, `*.snap`, and `*.snap64`.

4. **Builds and tests** — Runs `cmake` and `cmake --build` over SSH. For vm64, tests include VM tests, worldBuilder snapshot creation, snapshot loading, and the Self automatic test suite (`--runAutomaticTests --headless`). For vm32, tests build a snapshot via worldBuilder, reload it, then run `--runAutomaticTests --headless`.

5. **Stops VM** — Sends `sudo poweroff` via SSH, waits for the process to exit, then cleans up the PID file.

Each `vm64-X` / `vm32-X` recipe is self-contained and ensures the VM is always stopped even on failure.

## QEMU acceleration

| Guest arch | On Apple Silicon | Acceleration | Speed |
|-----------|-----------------|-------------|-------|
| aarch64 | Yes | HVF (`-accel hvf`) | Near-native |
| x86_64 | Yes | TCG (software) | ~5-10x slower |

ARM64 guests use Apple's Hypervisor.framework (HVF), which runs guest code directly on the CPU. x86_64 guests use QEMU's Tiny Code Generator (TCG) for binary translation.

## SSH port allocation

SSH ports are dynamically assigned at VM boot time. Each `start-*` recipe picks a free port using the `_free-port` helper (which binds a socket to port 0 and reads the OS-assigned port), writes it to `<name>.port`, and launches QEMU with that port. This eliminates port conflicts when running multiple VMs or when stale QEMU processes hold ports.

The `.port` files are read by the top-level recipes and cleaned up by `stop-*`. You can read the port of a running VM with `cat <name>.port`.

## Snapshot mode

All CI builds use QEMU's `-snapshot` flag on the disk image. This means:
- The base image is never modified during builds
- Each build starts from a clean state
- No cleanup needed after builds
- Multiple concurrent builds from the same image are safe

Only setup recipes boot without `-snapshot` (to save provisioning changes).

## vm64 vs vm32 build differences

| | vm64 | vm32 |
|---|---|---|
| cmake source | `cmake -S vm64` | `cmake -S vm` |
| Build dir | `build` | `build` |
| Test steps | 4: VM tests, snapshot build, snapshot load, Self suite (`--runAutomaticTests --headless`) | 3: snapshot build, snapshot load, Self suite (`--runAutomaticTests --headless`) |
| FreeBSD compiler | system gcc (pkg) | default `gcc`/`g++` inside the `/compat/i386` lib32 chroot |

Each VM codebase uses its own dedicated image, so there is no build directory collision.

## Adding a new platform

1. **Download an image** — Add download URL as a Justfile variable. Add a `provision-<name>` recipe.

2. **Add start/stop recipes** — Define `start-<name>` and `stop-<name>` in the Advanced group. Use `_free-port` for dynamic port allocation.

3. **Add a compile recipe** — Create `_vm64-compile-<name>` or `_vm32-compile-<name>` (private recipe).

4. **Add a top-level recipe** — Create `vm64-<name>` or `vm32-<name>` that starts, compiles, and stops.

5. **Register in fullrun** — Add the recipe to `fullrun-vm64` or `fullrun-vm32` dependencies.

6. **Wire up provisioning** — For Ubuntu/FreeBSD, add a `_create-cloud-init-*` recipe that emits a seed ISO with package installation commands. For NetBSD, extend the Anita workflow. Either way, add `provision-<name>` / `start-<name>` / `stop-<name>` recipes.

7. **Test** — Run `just vm64-<name>` or `just vm32-<name>` to verify.

## CMake flags

| Platform | Graphics | Flags |
|----------|----------|-------|
| macOS | Quartz (default) | (none needed) |
| Linux | X11 | `-DSELF_QUARTZ=OFF` |
| FreeBSD | X11 | `-DSELF_QUARTZ=OFF` |
| NetBSD | X11 | `-DSELF_QUARTZ=OFF` |

## Build dependencies

| Platform | Compiler | Packages |
|----------|----------|----------|
| macOS | Xcode clang | `cmake` |
| Ubuntu ARM64 | g++ | `cmake g++ libx11-dev libxext-dev libncurses-dev rsync` |
| Ubuntu AMD64 | g++ | `cmake g++ libx11-dev libxext-dev libncurses-dev rsync` |
| Ubuntu AMD64 multilib | g++ + multilib | `cmake g++ rsync` + `gcc-multilib g++-multilib libc6-dev-i386 libx11-dev:i386 libxext-dev:i386 libncurses-dev:i386` |
| FreeBSD ARM64 | gcc (pkg) | `cmake gcc libX11 libXext ncurses rsync sudo` |
| FreeBSD AMD64 | gcc (pkg) | `cmake gcc libX11 libXext ncurses rsync sudo` |
| FreeBSD AMD64 lib32 | system `gcc`/`g++` inside `/compat/i386` chroot | host: `cmake rsync sudo`; chroot: `gcc binutils libX11 libXext ncurses` |
| NetBSD i386 | gcc12 (pkgin) | `cmake gcc12 libX11 libXext ncurses rsync jemalloc` |
| NetBSD AMD64 | gcc12 (pkgin) | `cmake gcc12 libX11 libXext ncurses rsync` |
| NetBSD macppc | gcc12 (pkgin) | `cmake gcc12 libX11 libXext ncurses rsync` |
| NetBSD sparc64 | gcc12 (pkgin) `-m32` | `cmake gcc12 libX11 libXext ncurses rsync` |

## Disk image management

Images live in `images/` and are gitignored. They are large (1-4 GB each) and should not be committed.

To re-provision an image, delete it and re-run provisioning:

```bash
rm images/ubuntu-arm64.qcow2
just provision-ubuntu-arm64
```

## The `do` recipe

The `do port COMMAND` recipe executes shell commands on a running VM. It hex-encodes the command to avoid SSH quoting issues, then decodes and runs it inside the VM via `bash --login`.

```bash
just do $(cat ubuntu-arm64.port) 'echo hello world'
```
