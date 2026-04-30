# Local CI — Tutorial

This guide walks you through setting up and running the local CI system for Self. It builds vm64 (64-bit) on macOS, Linux, FreeBSD, and NetBSD, and the legacy vm (32-bit) on Ubuntu AMD64, FreeBSD i386, and NetBSD i386 — all using QEMU virtual machines.

## Prerequisites

Install QEMU, sshpass, and just on your Mac:

```bash
brew install qemu sshpass just
```

That's it. QEMU includes the EFI firmware needed for ARM64 VMs.

## Step 1: Set up a source tree

Source trees live inside the `src/` directory. Each is a directory containing
the Self source code (vm64/, vm/, objects/, etc.).

```bash
# Clone the self64 repo as a source tree
git clone https://github.com/OurSelf-Systems/self64.git src/self64@current

# Or create a symlink to an existing checkout
ln -s /path/to/self64 src/self64@dev
```

All build commands require `SELFSRC=<name>` to specify which source tree to build.

## Step 2: Verify your environment

```bash
just check-env
```

This checks that all required tools are installed and lists available source trees.

## Step 3: Download and provision VM images

Set up all images at once:

```bash
just provision-all
```

Or set up individual platforms:

```bash
just provision-ubuntu-arm64           # Ubuntu ARM64 (vm64, near-native speed)
just provision-ubuntu-amd64           # Ubuntu AMD64 (vm64, emulated)
just provision-ubuntu-amd64-multilib  # Ubuntu AMD64 multilib (vm 32-bit, emulated)
just provision-freebsd-amd64-multilib # FreeBSD AMD64 multilib (vm 32-bit, emulated)
just provision-freebsd-arm64          # FreeBSD ARM64 (vm64, hvf-accelerated)
just provision-freebsd-amd64          # FreeBSD AMD64 (vm64, emulated)
just provision-netbsd-i386            # NetBSD i386 (vm 32-bit, emulated, via Anita)
just provision-netbsd-amd64           # NetBSD AMD64 (vm64, emulated, via Anita)
just provision-netbsd-macppc          # NetBSD macppc (vm 32-bit, PowerPC, emulated, via Anita)
```

### Ubuntu (ARM64 and AMD64)

Ubuntu cloud images use cloud-init, which automatically creates the `ci` user and installs packages on first boot. The VM will shut down automatically when provisioning completes. The AMD64 image installs standard packages for vm64 builds. The separate Ubuntu AMD64 multilib image installs additional multilib packages for 32-bit vm builds.

Note: the AMD64 images are emulated (TCG) and boot slowly (~2-5 minutes).

## Step 4: Run CI builds

### Quick start — build everything

```bash
just SELFSRC=self64@current fullrun-all         # All platforms, both vm64 and vm32
```

### Run by VM codebase

```bash
just SELFSRC=self64@current fullrun-vm64        # All vm64 platforms
just SELFSRC=self64@current fullrun-vm32        # All vm32 platforms
```

### Run individual platforms

```bash
# vm64
just SELFSRC=self64@current vm64-macos-native   # Fastest — no VM, runs directly
just SELFSRC=self64@current vm64-ubuntu-arm64    # Near-native speed on Apple Silicon
just SELFSRC=self64@current vm64-ubuntu-amd64    # Emulated, slower
just SELFSRC=self64@current vm64-freebsd-arm64   # FreeBSD 15 arm64, hvf-accelerated
just SELFSRC=self64@current vm64-freebsd-amd64   # FreeBSD 15 amd64, emulated
just SELFSRC=self64@current vm64-netbsd-amd64    # NetBSD 10 amd64, emulated

# vm32 (32-bit)
just SELFSRC=self64@current vm32-ubuntu-amd64    # 32-bit build via multilib on AMD64
just SELFSRC=self64@current vm32-freebsd-amd64-multilib  # 32-bit build on FreeBSD via multilib
just SELFSRC=self64@current vm32-netbsd-i386     # 32-bit build on NetBSD i386, emulated
just SELFSRC=self64@current vm32-netbsd-macppc   # 32-bit build on NetBSD macppc (PowerPC), emulated
```

### See all available recipes

```bash
just                    # Shows grouped recipe list
```

## Advanced usage

### Manual VM control

You can start/stop VMs independently and run commands manually:

```bash
just start-ubuntu-arm64                          # Boot the VM
just do $(cat ubuntu-arm64.port) 'uname -a'     # Run a command on it
just do $(cat ubuntu-arm64.port) 'cmake --version'  # Run another command
just stop-ubuntu-arm64                           # Shut it down
```

### Clean slate

```bash
just reset-everything   # Delete all images and logs
```

## Troubleshooting

**"Disk image not found"** — Run `just provision-<platform>` first.

**SSH connection refused** — The VM may still be booting. The script waits up to 120 seconds. If it still fails, try re-provisioning the image.

**"sshpass: command not found"** — Install it: `brew install sshpass` (may need `brew install hudochenkov/sshpass/sshpass`).

**x86_64 build is very slow** — This is expected. Software emulation (TCG) runs at ~5-10x slower than native. Budget 10-20 minutes for x86_64 builds.

**QEMU firmware not found** — Make sure QEMU is installed via Homebrew: `brew install qemu`. The EFI firmware is at `/opt/homebrew/share/qemu/edk2-aarch64-code.fd`.

**"just: command not found"** — Install it: `brew install just`.
