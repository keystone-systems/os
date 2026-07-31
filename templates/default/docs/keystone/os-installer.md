---
title: OS installer — build the ISO and write it to USB
description: Build the Keystone installer ISO from this flake and write it to a USB stick on Linux, macOS, or Windows
---

# OS installer

Companion to [`onboarding.md`](onboarding.md) steps 3–4. Build the
Keystone installer ISO from this flake and write it to a USB stick. Pick
the section that matches your driver's OS.

## Build the ISO

Your `keystone-config` flake exposes a single ISO output. The image bakes in
installer targets for every Linux host you declared in `flake.nix`, so one
build covers the whole fleet.

```bash
nix build .#iso
```

After the build:

```bash
ls -lh result/iso/
```

You should see a `keystone-...-installer-X.Y.Z.iso` file in the few hundred
MB to ~2 GB range.

### Building x86_64-linux from an aarch64 MacBook

If you're driving from an Apple Silicon Mac, the build host architecture
(`aarch64-darwin`) doesn't match the target (`x86_64-linux`). Two options:

1. **Use a remote Linux builder.** Configure `nix.buildMachines` on your Mac to
   point at any x86_64-linux box you can SSH into. The Nix manual covers the
   wiring under "Distributed Builds". For one-shot use, the `--builders` flag
   on the build invocation works too.
2. **Rely on the cache.** Most ISO content is downloaded from
   `cache.nixos.org` and `ks-systems.cachix.org`. If your Mac is configured
   with both substituters, the local build mostly fetches binaries and
   links them — minimal cross-compilation needed. Add the keystone cache:
   ```bash
   # ~/.config/nix/nix.conf
   extra-substituters = https://ks-systems.cachix.org
   extra-trusted-public-keys = ks-systems.cachix.org-1:Abbd38auzcLIfJUtX7kSD6zdGUU4v831Sb2KfajR5Mo=
   ```

If the build still tries to compile something large from source (Chromium,
Rust toolchain, etc.), you're missing a cache hit. Cross-compilation under Nix
is usable but slow; remote builder is the saner path.

### Building from a Linux driver

No special setup. The build runs locally.

## Validate the ISO in a VM (optional)

Before burning to a USB stick, you can boot the freshly-built ISO inside a
local QEMU VM to confirm it actually reaches the installer login prompt. This
catches boot-chain regressions that manifest as "the kernel boots and DHCPs
but the console never comes back" — symptoms that are easy to miss until
you're standing in front of the real hardware.

The template ships a self-contained launcher at
[`bin/iso-vm-preview`](../../bin/iso-vm-preview). It uses `nix shell` to pull
QEMU + OVMF (UEFI firmware) on demand, so it works on any Linux driver
without libvirt or a system-installed QEMU.

```bash
nix develop -c iso-vm-preview              # graphical window + serial mirrored on stdio
nix develop -c iso-vm-preview --headless   # serial only, no window (good for SSH'd shells)
nix develop -c iso-vm-preview --clean      # wipe the scratch disk + NVRAM and start fresh
```

(Or just `iso-vm-preview ...` from an activated dev shell / direnv-loaded
shell. `./bin/iso-vm-preview` also works after `chmod +x bin/*`.)

What you should see:

1. OVMF firmware splash, then the GRUB menu picks `Keystone Installer`.
2. Kernel boot messages on the serial console.
3. NetworkManager (or `dhcpcd`) acquiring a DHCP lease — this is the point
   the user mentioned as a common stopping point.
4. `Reached target Multi-User System.` on serial.
5. Either a `keystone login:` prompt on tty1 (graphical window) **or**, if
   you've set `keystone.installer.tui.enable = true`, the Keystone installer
   TUI taking over tty1.

If step 5 never happens in `--headless` mode, that's expected: tty1 is a
*graphical* console, and `--headless` only attaches the serial port. Re-run
without `--headless` to actually see the login takeover. Conversely, if the
graphical window shows nothing past DHCP but serial scrolls fine, the kernel
parameters likely point the primary console at `ttyS0` only — check
`modules/iso-installer.nix` in your pinned keystone for the `console=` line.

You can SSH into the running installer (port-forwarded to `localhost:12222`)
*if* you set `keystone.installer.sshKeys` in `flake.nix`:

```bash
ssh -p 12222 -o StrictHostKeyChecking=no root@localhost
```

Exit the VM with **Ctrl+A then X** (when focused on the serial console) or
just close the QEMU window. The scratch install disk lives at
`/tmp/keystone-iso-vm-preview-disk.qcow2` and is reused across runs — pass
`--clean` to start from a blank disk if you want to dry-run `ks install`.

## Write the ISO to USB

⚠️ **Writing to a USB stick destroys all data on the target device.**
The template ships a guided script that minimizes the chance of overwriting
the wrong disk; raw `dd` is the manual fallback for users who prefer it or
are on Windows.

### Recommended: `iso-burn-usb` via the dev shell (Linux + macOS)

The script ships in `bin/iso-burn-usb` and is exposed as a dev-shell
package, so the canonical invocation is either:

```bash
# direnv users: cd into the repo and direnv auto-loads the shell, then:
iso-burn-usb

# Otherwise:
nix develop -c iso-burn-usb

# Run nix build .#iso first, then burn — collapses both phases:
nix develop -c iso-burn-usb --build
```

(Running `./bin/iso-burn-usb` directly also works *after* you `chmod +x
bin/*` — `nix flake new -t` strips executable bits during scaffolding,
which is why the dev-shell form is the documented one. Inside the dev
shell, the script is wrapped via a Nix derivation that preserves the
exec bit and lives on PATH.)

What it does:

1. Locates `result/iso/*.iso` automatically (override with `--iso PATH`).
2. Lists **only removable USB devices** — internal NVMe/SATA drives are
   filtered out at detection, so a typo can't target your driver disk.
3. Shows the picked device's model, size, and current partition layout
   before doing anything destructive.
4. Requires you to type the literal word `BURN` (uppercase) to proceed.
   `y`/Enter/anything else aborts.
5. Unmounts any auto-mounted partitions on the target.
6. Calls `dd` with `bs=4M` (Linux) or `bs=4m` on the raw character device
   `/dev/rdiskN` (macOS, dramatically faster than the buffered device).
7. Runs `sync` at the end.

If multiple USB sticks are plugged in, it presents a numbered picker. If
none are detected, it errors with a clear message instead of falling through
to internal disks.

### Manual fallback: raw `dd`

Use this if you want full manual control, are on Windows (Rufus), or are
intentionally writing to a non-USB device the safety script won't pick.

### Linux

1. Plug the USB in. Wait a beat.
2. List block devices:
   ```bash
   lsblk -dpno NAME,SIZE,MODEL,TRAN
   ```
   Identify the USB (`TRAN` column shows `usb`). Note the path, e.g.
   `/dev/sdb`. Common gotcha: the USB stick's size on the label is a marketing
   round-up — `lsblk` will show the slightly smaller actual size.
3. Unmount any partitions of the USB if your file manager auto-mounted them:
   ```bash
   sudo umount /dev/sdb*  # adjust device
   ```
4. Write:
   ```bash
   sudo dd if=result/iso/*.iso of=/dev/sdb bs=4M status=progress conv=fsync
   sync
   ```
5. Wait for `sync` to return. Pull the USB.

### macOS

1. Plug the USB in. Wait a beat. Dismiss any "Disk Not Readable" popup —
   that's the Mac complaining about the ISO9660 filesystem, which is fine.
2. List devices:
   ```bash
   diskutil list
   ```
   Identify the USB. It'll typically be `/dev/diskN` where `N` is something
   like `2` or `4`. Confirm by size and the absence of `Apple_APFS` partitions.
3. Unmount the whole device (do NOT eject):
   ```bash
   diskutil unmountDisk /dev/diskN
   ```
4. Write to the *raw* device (`/dev/rdiskN`, not `/dev/diskN`) for much faster
   throughput:
   ```bash
   sudo dd if=result/iso/*.iso of=/dev/rdiskN bs=4m status=progress
   sync
   ```
   (Lowercase `4m`, not `4M`, on macOS dd.)
5. Eject when `dd` finishes:
   ```bash
   diskutil eject /dev/diskN
   ```

### Windows

Use Rufus (<https://rufus.ie/>) in "DD Image" mode. Select the ISO file in
the WSL-shared `result/iso/` directory. Rufus handles the device picker and
unmount safely.

## Boot the target from USB

1. Plug the USB into the new host.
2. Power on, enter UEFI / BIOS setup (vendor-specific — common keys: F2, F10,
   F12, Del).
3. Disable Secure Boot for now (the keystone installer ISO is not signed
   with a key your firmware trusts yet — Step 7 of the onboarding doc enrolls
   keys).
4. Boot from the USB.

The Keystone installer banner appears. Once it auto-DHCPs, the system's IP
shows on the console. You can now follow Step 5 of [`onboarding.md`](onboarding.md).
