---
title: ISO and OS virtual machine testing
description: End-to-end testing of template generation, installer ISO, desktop validation, and direct qcow2 image building in QEMU
---

# ISO and OS virtual machine testing

## Goal

Validate the full Keystone onboarding chain in a VM before touching real hardware:

1. `mkSystemFlake` template generation produces a valid NixOS config
2. The installer ISO boots and `ks` can install a host
3. The installed system boots, reaches the Hyprland desktop, and shows hyprlock
4. SSH works post-reboot with declarative keys from `admin.sshKeys`

When the VM passes, the same template-generated ISO works on real hardware.

## Two testing paths

Keystone provides two independent VM testing paths for different layers of the
stack.  Both coexist; neither replaces the other.

| Path | Tests | Time |
|------|-------|------|
| **Direct qcow2** | NixOS modules, storage config, boot chain | 2–10 min |
| **ISO + installer** | Installer TUI, disko, nixos-install, handoff | 20–30 min |

### Fastest direct path (most common)

```bash
# From the keystone repo — regenerates the fixture, then runs test-iso:
bin/test-e2e --direct laptop --headless

# From any consumer flake generated from the default template:
./bin/test-iso --direct laptop --dev --headless
```

Both invocations do the same thing:

1. Build `packages.x86_64-linux.vm-image-laptop` — a pre-installed qcow2.
2. Boot it via `bin/virtual-machine` (Q35 + OVMF + swtpm + SPICE).
3. Auto-type the `keystone` LUKS passphrase over the serial console.
4. Wait for SSH, run `uname -r` and `systemctl is-system-running`, clean up.

Use `--direct` any time you are iterating on NixOS modules, storage layout,
TPM, or boot chain — anything below the installer.

Drop `--headless` to leave a SPICE window open for interactive debugging; the
auto-feeder still runs in the background.

### Full ISO + installer path

Use this when testing the installer itself (`ks` binary, TUI flow,
`ks install` behaviour):

```bash
# From the keystone repo — the default when no mode flag is given:
bin/test-e2e                      # full e2e with screenshots (20-30 min)
```

## Direct qcow2 image workflow

`test-iso --direct` builds a bootable qcow2 directly from a host's NixOS
configuration using disko's image mode, then boots it via `bin/virtual-machine`.
No ISO is built or booted.

### How it works

```
nix build .#packages.x86_64-linux.vm-image-laptop
  └─ keystone.lib.mkVMImage { nixosSystem = nixosConfigurations.laptop; }
       └─ disko imageBuilder: partition + format virtual disk, copy Nix store
            └─ outputs: result/disk0.qcow2  (ZFS)  or  result/root.qcow2  (ext4)

bin/virtual-machine --disk-path result/disk0.qcow2 --start test-vm
  └─ Q35 + OVMF + swtpm + SPICE (same hardware config as ISO path)
```

### Quick start

```bash
# Build and boot in headless mode, run SSH health check, then clean up:
cd /path/to/keystone-config
./bin/test-iso --direct laptop --dev --headless

# Build image only (do not start VM):
./bin/test-iso --direct laptop --dev --build-only

# Boot with a SPICE window for interactive debugging:
./bin/test-iso --direct laptop --dev
```

### Building the image independently

`mkSystemFlake` exposes `packages.${system}.vm-image-${name}` for every Linux
host automatically.  You can build images without `test-iso`:

```bash
nix build .#packages.x86_64-linux.vm-image-laptop
ls result/          # disk0.qcow2 (ZFS) or root.qcow2 (ext4)
```

To boot the pre-built image with full UEFI + SecureBoot + TPM:

```bash
VM_SCRIPT="$KEYSTONE_LOCKED_PATH/bin/virtual-machine"
"$VM_SCRIPT" --name test-direct \
             --disk-path result/disk0.qcow2 \
             --ssh-port 12260 \
             --memory 8192 \
             --headless \
             --start \
             --wait-ssh
```

### Using `mkVMImage` in your own flake

```nix
# flake.nix
packages.x86_64-linux.my-vm-image = keystone.lib.mkVMImage {
  nixosSystem = nixosConfigurations.laptop;
  # Optional overrides:
  # imageFormat = "qcow2";   # default
  # memSize = 4096;          # builder VM RAM in MB
  # devices = [ "/dev/vda" ]; # virtual disk paths for builder VM
};
```

### Snapshot-based iteration with direct images

Direct images support the same qcow2 snapshot workflow as ISO-installed disks:

```bash
VM_SCRIPT="$KEYSTONE_LOCKED_PATH/bin/virtual-machine"
VM_NAME="keystone-direct-$$"

# Create a snapshot after first boot
"$VM_SCRIPT" --snapshot "$VM_NAME" post-direct

# List snapshots
"$VM_SCRIPT" --list-snapshots "$VM_NAME"

# Restore and reboot
"$VM_SCRIPT" --destroy "$VM_NAME"
"$VM_SCRIPT" --restore "$VM_NAME" post-direct
"$VM_SCRIPT" --post-install-reboot "$VM_NAME" --headless
```

### Storage layout in image mode

disko's image builder automatically remaps storage device paths to virtual
ones (`/dev/vda`, `/dev/vdb`, …) regardless of what paths are declared in the
host's `hardware.nix`.  The resulting image boots with the same storage layout
on any Q35 VM with matching virtual disk count.

`mkVMImage` overrides `keystone.os.storage.devices` to `["/dev/vda"]` by
default.  This ensures the NixOS initrd (ZFS devNodes, LUKS crypttab) also
uses the virtual path and boots correctly without hardware-specific disk IDs.

For multi-disk configs (ZFS mirror, raidz), pass additional devices:

```nix
packages.x86_64-linux.vm-image-mirror = keystone.lib.mkVMImage {
  nixosSystem = nixosConfigurations.server;
  devices = [ "/dev/vda" "/dev/vdb" ];
};
```

### LUKS and ZFS encryption in image mode

Direct images use the same `keystone` LUKS passphrase the installer sets up
via the credstore.  At every boot the initrd prompts for it.

`test-iso --direct` (and `bin/test-e2e --direct`) auto-types the passphrase
over the serial console, so no manual interaction is needed.  `mkVMImage`
sets `boot.kernelParams = [ "console=tty0" "console=ttyS0,115200" ]`, which
routes the initrd `cryptsetup-ask-password` prompt onto the serial PTY that
`bin/virtual-machine` exposes.  A background feeder writes the passphrase to
that PTY every five seconds until SSH comes up; post-unlock writes are
harmless (they surface as failed serial getty login attempts and stop when
the feeder is killed at cleanup).

Override the passphrase with either a CLI flag or env var:

```bash
./bin/test-iso --direct laptop --dev --headless --luks-passphrase "s3cret"
# or
DIRECT_LUKS_PASSPHRASE=s3cret ./bin/test-iso --direct laptop --dev --headless
```

The direct-mode SSH timeout is floored at 1800 seconds (30 min) to cover
LUKS unlock plus first-boot activation (home-manager, sshd host keys,
nix-daemon).  Observed initrd-phase durations range from ~8 min to ~13 min
across runs on the same host — the 30 min floor gives comfortable headroom
without masking real hangs.  Pass `--ssh-timeout N` above 1800 for
unusually slow hardware; lower values are raised automatically.

For interactive SPICE sessions (omit `--headless`), type the passphrase at
the console — the auto-feeder still runs in the background but an
interactive keystroke typically arrives first.

## What lives in the ISO vs what is evaluated at install time

Understanding this boundary is the key to fast iteration.

### Baked into the ISO (rebuild required to change)

| Component | Files |
|-----------|-------|
| `ks` binary | `packages/ks/src/` |
| Installer NixOS modules | `modules/iso-installer.nix`, `modules/installer.nix` |
| Live environment packages | Tools in the ISO's squashfs closure |
| Embedded config repo snapshot | Copied from the template at ISO build time |

### Evaluated from the flake during nixos-install (no rebuild)

| Component | Files |
|-----------|-------|
| NixOS modules | `modules/os/`, `modules/desktop/`, `modules/server/` |
| Template library | `lib/templates.nix` (`mkSystemFlake`, `mkLaptop`, etc.) |
| Template flake config | `templates/default/flake.nix` |
| Host definitions | `templates/default/hosts/` |
| SSH keys | `admin.sshKeys` in the template flake |

These are resolved when `nixos-install --flake <repo>#laptop` runs inside the
VM. Changes take effect by updating the fixture's keystone flake input.

### Host-side only (never in the ISO)

| Component | Files |
|-----------|-------|
| `test-iso` script | `templates/default/bin/test-iso` |
| QEMU flags | Memory, GPU, display backend |
| Screenshot capture | `screendump` via QEMU monitor |
| Checkpoint validation | SSH-based checks from the host |


## Quick iteration workflow

### After changing NixOS modules or storage config (direct path — fastest)

Use the direct qcow2 path to validate module changes without the ISO installer:

```bash
cd /path/to/keystone-config

# Headless direct validation (2–10 min depending on store hits):
./bin/test-iso --direct laptop --dev --headless

# Or build standalone for manual testing:
nix build .#packages.x86_64-linux.vm-image-laptop
bin/virtual-machine --disk-path result/disk0.qcow2 --ssh-port 12260 --headless --start --wait-ssh
```

### First run (creates fixture and builds ISO)

```bash
cd /tmp/keystone-dev-template-fixture   # or any consumer repo
./bin/test-iso --dev --headless --e2e --port 12260 --memory 12288
```

### After changing NixOS modules or lib/templates.nix (ISO path)

No ISO rebuild needed — the modules are evaluated during `nixos-install`:

```bash
cd /tmp/keystone-dev-template-fixture
nix flake update keystone                # pick up worktree changes
./bin/test-iso --dev --headless --e2e --port 12260 --no-build --memory 12288
```

### After changing the ks binary

ISO rebuild required — the binary is baked into the live environment:

```bash
./bin/test-iso --dev --headless --e2e --port 12260 --memory 12288
```

### After changing only the test-iso script

Copy the updated script, no rebuild:

```bash
cp <worktree>/templates/default/bin/test-iso bin/test-iso
./bin/test-iso --dev --headless --e2e --port 12260 --no-build --memory 12288
```

## Snapshot-based iteration

`bin/virtual-machine` uses qcow2 internal snapshots so you can roll back to
known-good states without reinstalling.  `--post-install-reboot` automatically
creates a `post-install` snapshot before booting the installed disk.

### Snapshot checkpoints

| Checkpoint | Created by | VM state | What it captures |
|------------|-----------|----------|-----------------|
| `post-install` | `--post-install-reboot` (automatic) | stopped | Complete NixOS install — partitions, system profile, handoff |
| `post-unlock` | manual | stopped | System booted past LUKS, before desktop |
| (none / fresh) | deleting the disk file | — | Start from scratch |

### Snapshot commands

```bash
VM_SCRIPT="$KEYSTONE_LOCKED_PATH/bin/virtual-machine"

# List snapshots
$VM_SCRIPT --list-snapshots <vm-name>

# Restore to a checkpoint (VM must be stopped)
$VM_SCRIPT --destroy <vm-name>                     # stop if running
$VM_SCRIPT --restore <vm-name> post-install        # revert disk

# Create a custom checkpoint
$VM_SCRIPT --destroy <vm-name>
$VM_SCRIPT --snapshot <vm-name> my-checkpoint

# Boot from the restored snapshot
$VM_SCRIPT --post-install-reboot <vm-name> --headless --monitor-socket /tmp/e2e-monitor.sock
```

### Desktop debugging workflow (most common)

After a full e2e run completes the install but desktop validation fails:

1. The `post-install` snapshot already exists.
2. Edit NixOS modules (e.g. `modules/desktop/`) in the keystone worktree.
3. Restore and re-boot without reinstalling:

```bash
VM_SCRIPT="$KEYSTONE_LOCKED_PATH/bin/virtual-machine"
VM_NAME="keystone-e2e-<pid>"   # from the test run output

# Restore to the state right after install
$VM_SCRIPT --destroy "$VM_NAME"
$VM_SCRIPT --restore "$VM_NAME" post-install

# Re-boot the installed disk
$VM_SCRIPT --post-install-reboot "$VM_NAME" \
  --headless --monitor-socket /tmp/e2e-monitor.sock
```

4. SSH in and apply the module change without full reinstall:

```bash
# In the fixture:
nix flake update keystone

# Copy updated flake into the VM:
scp -P 12260 -i .test-iso-dev-key -r . keystone@localhost:~/updated-flake/
ssh -i .test-iso-dev-key -p 12260 keystone@localhost \
  'sudo nixos-rebuild switch --flake ~/updated-flake#laptop'
```

5. Reboot the VM and check the desktop — or take a new snapshot if it works.

This loop takes 2-3 minutes instead of 15+ minutes for a full reinstall.

### When to use each strategy

| Situation | Strategy | Time |
|-----------|----------|------|
| NixOS module change (storage, TPM, boot) | `test-iso --direct laptop --headless` | 2-10 min |
| Module change, install known good | Restore `post-install` → `nixos-rebuild switch` | 2-3 min |
| Boot/LUKS issues | Restore `post-install` → re-boot | 30 sec |
| Installer change (`ks` binary) | Full reinstall (rebuild ISO) | 15-20 min |
| Disko layout change | Delete disk → full reinstall | 15-20 min |
| Template flake change | `nix flake update keystone` → `--no-build` reinstall | 15-20 min |
| First run (no snapshots) | Full e2e run | 15-20 min |

### Keeping the VM alive for manual debugging

`test-iso --e2e` cleans up the VM on exit.  For manual debugging, run without
`--e2e` to keep the VM alive after SSH is ready:

```bash
# Boot and keep alive (no automated install):
./bin/test-iso --dev --headless --port 12260 --no-build --memory 12288

# SSH in and drive manually:
ssh -i .test-iso-dev-key -p 12260 keystone@localhost
ks install --host laptop   # excludes installer media, may prompt for a disk number, then asks for `destroy`
```

Then use snapshot commands directly to save and restore checkpoints.

## Editing files on a running ISO

SSH into the live ISO to test changes without rebuilding:

```bash
ssh -i .test-iso-dev-key -p 12260 keystone@localhost
```

The embedded config repo is read-only (squashfs). When `ks` starts an install,
it copies the repo to `/tmp/keystone-install-repo` (writable). You can edit
files there before the install runs `nixos-install`.

## Post-install iteration

After a successful install, the installed system's config lives at
`/mnt/home/<user>/.keystone/repos/<owner>/<repo>/`. To iterate on the installed
system without re-running the full install:

1. Edit keystone modules or template config in the worktree
2. `nix flake update keystone` in the fixture
3. Copy the updated flake into the VM's installed repo via `scp`
4. Run `nixos-rebuild switch --flake <repo>#laptop` inside the VM via SSH

This is useful for fixing desktop, login, or service issues after install.

## Headless install with ks install --host

Skip the TUI entirely for automated testing:

```bash
# On the live ISO (via SSH):
ks install --host laptop
# or pin the disk explicitly:
ks install --host laptop --disk /dev/disk/by-id/virtio-keystone-test-disk
```

The command prints discovered disks, highlights the selected target, and then
requires you to type `destroy` before it will erase the disk. If `--disk` is
omitted, it excludes installer media first, auto-selects the only remaining
disk, or prompts for a numbered disk choice when multiple candidates remain.
Exit code 0 means success. The `--e2e` flag in `test-iso` passes `--disk` and
pipes the confirmation token into this prompt.

## Screenshot-based reboot validation

The `--e2e` flag in `test-iso` adds a second layer after install completes:

1. Destroys the install VM (`--destroy`)
2. Boots the installed disk via `--post-install-reboot` with virtio-gpu display
3. Creates a `post-install` qcow2 snapshot automatically
4. Takes QEMU monitor screenshots at each boot stage via `screendump` + `socat`
5. Unlocks LUKS via `sendkey`
6. Validates SSH connectivity with the dev key
7. Compares screenshots against LFS-tracked baselines (byte-for-byte via `cmp`)

Screenshot stages:

| Stage | What to expect |
|-------|----------------|
| 01-luks-prompt | LUKS passphrase prompt (text console) |
| 02-post-unlock | Boot progress after disk unlock |
| 03-desktop-or-login | Hyprland/hyprlock lockscreen |
| 04-final-state | Final state after login timeout |

First run copies captured screenshots into `tests/e2e/screenshots/` as baselines.
Subsequent runs compare byte-for-byte and fail on mismatch. The LFS pointer SHA-256
serves as the natural checksum (see "LFS as natural checksum" below).

## VM lifecycle: bin/virtual-machine

`test-iso --e2e` delegates VM lifecycle to `bin/virtual-machine` (in the keystone
repo) via `$KEYSTONE_LOCKED_PATH/bin/virtual-machine`. This is a Python/libvirt
script that provides the proven Q35 + EDK2 SecureBoot + TPM + virtio-gpu configuration.

`test-iso` resolves the keystone repo path from `flake.lock` automatically.

```bash
# What test-iso --e2e does internally:
VM_SCRIPT="$KEYSTONE_LOCKED_PATH/bin/virtual-machine"

# Install phase
"$VM_SCRIPT" --name e2e-install --iso "$iso" --disk-path "$disk" \
  --memory 12288 --ssh-port 12260 --headless --start --wait-ssh

# After install completes (creates "post-install" snapshot automatically)
"$VM_SCRIPT" --post-install-reboot e2e-install \
  --headless --monitor-socket /tmp/e2e-monitor.sock

# Snapshot management for iterative debugging:
"$VM_SCRIPT" --list-snapshots e2e-install
"$VM_SCRIPT" --destroy e2e-install
"$VM_SCRIPT" --restore e2e-install post-install
"$VM_SCRIPT" --post-install-reboot e2e-install --headless  # re-boot from snapshot

# Cleanup
"$VM_SCRIPT" --reset e2e-install
```

### Why libvirt instead of raw QEMU

- OVMF boot device discovery works correctly (proven in `bin/test-deployment`)
- TPM 2.0 via swtpm is managed by libvirt automatically
- Disk snapshots for quick revert
- Consistent PCI topology between install and reboot phases
- virtio-gpu with egl-headless provides virgl 3D for guest GL/EGL
- Screenshots captured via grim over SSH (Wayland surface), not screendump

### hardware.graphics

`modules/desktop/nixos.nix` enables `hardware.graphics = true` when desktop is
enabled. This pulls in mesa + virgl drivers so Hyprland can render on the
virtio-gpu device in VMs and on real GPUs on bare metal.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| OOM during nixos-install | VM needs more RAM | `--memory 12288` (12 GB) |
| `Holding login session` | No GPU device in QEMU | Ensure `virtio-gpu-pci` + `egl-headless` |
| System profile not detected by checkpoint | Symlink chain doesn't resolve on ISO | Use `test -L` not `test -f` |
| `Cannot find terminfo for xterm-ghostty` | Host TERM passed to VM | Set `TERM=xterm-256color` |
| SSH rejected post-reboot | `admin.sshKeys` not bridged to installed system | Check `lib/templates.nix` `adminSshKeys` bridge |
| nixos-install rebuilds from source | Closure not in cache | Run `bin/warm-cachix` or `nix build .#nixosConfigurations.laptop.config.system.build.toplevel` on the host first |
| `No disks found` in ks install | Disk has no serial number | `ks` discovers disks via `/dev/disk/by-id/`; virtio-blk needs `<serial>` in XML |
| PCI slot conflict on VM start | qemu:commandline device collides with libvirt-managed device | Assign explicit `bus=pcie.0,addr=0xNN` to qemu:commandline devices |
| `vm-image-<host> not found` in direct mode | `mkSystemFlake` not called in flake | Check `packages.x86_64-linux.vm-image-*` are exposed; ensure `hostsRoot` is set |
| Direct image OOM during build | Builder VM (disko) needs more RAM | Override `disko.memSize` via `extraConfig` in `mkVMImage` |
| LUKS prompt hangs in headless direct mode | Auto-feeder never reached the serial PTY, or the image's passphrase differs from `keystone` | Confirm `boot.kernelParams` includes `console=ttyS0,115200` (added by `mkVMImage`); check `virsh -c qemu:///session dumpxml <vm>` shows a `/dev/pts/N` serial; pass `--luks-passphrase` if the image uses a non-default passphrase |
| SSH validation aborts before LUKS unlocks | Default `--ssh-timeout` lower than first-boot takes | `--direct` floors the SSH timeout at 1800 seconds; raise further with `SSH_WAIT_TIMEOUT=2400` or `--ssh-timeout 2400` if LUKS consistently takes more than ~25 min |

## Existing VM test infrastructure

`bin/virtual-machine` is the canonical VM tool. All VM workflows should converge
on it. See #339 for the consolidation plan.

| Script | Tier | Machine | SecureBoot | TPM | Display | Purpose |
|--------|------|---------|-----------|-----|---------|---------|
| `bin/virtual-machine` | 3 | Q35 | EDK2 | tpm-crb | egl-headless+virtio-gpu | Full libvirt VM lifecycle |
| `bin/test-deployment` | 3 | (via virtual-machine) | Yes | Yes | — | nixos-anywhere workflow |
| `bin/build-vm` | 2 | — | No | No | — | Fast nixos-rebuild iteration |
| `bin/test-microvm-tpm` | 1 | Q35 | No | tpm-tis | — | Lightweight TPM test (~20s) |
| `test-iso --e2e` | — | (via virtual-machine) | Yes | Yes | virtio-gpu | Template → ISO → install → desktop |
| `test-iso --direct` | — | (via virtual-machine) | Yes | Yes | SPICE/headless | Direct qcow2 → boot → SSH validation |

Test configs in `tests/flake.nix`: `test-server`, `test-hyprland`, `build-vm-terminal`,
`build-vm-desktop`, `tpm-microvm`.

## Target architecture

The unified e2e pipeline validates the full new-user journey. One command:

```
./bin/test-iso --dev --headless --e2e --port 12260 --memory 12288
```

Stages (current status):

| # | Stage | Status | Requirement |
|---|-------|--------|-------------|
| 1 | Template generation (`mkSystemFlake`) | Working | REQ-008.3 |
| 2 | ISO build + artifact verification | Working | REQ-003 |
| 3 | Headless install (`ks install --host`) | Working | REQ-008.12-18 |
| 4 | Install checkpoint verification | Working | REQ-003 |
| 5 | Reboot from installed disk | Pending — OVMF boot discovery (#339) | REQ-008.20 |
| 6 | LUKS unlock via QEMU `sendkey` | Working (when boot succeeds) | — |
| 7 | Screenshot capture at boot stages | Working (PPM via `screendump`) | — |
| 8 | Desktop validation (Hyprland + hyprlock) | Working — virgl + egl-headless + grim | REQ-002 |
| 9 | SSH validation with dev key | Working | — |
| 10 | SHA-to-SHA screenshot comparison | Working (LFS baselines) | — |

### Future stages (separate issues)

- SecureBoot enrollment (sbctl + lanzaboote) — #283
- TPM enrollment (systemd-cryptenroll) — #283
- First-boot wizard completion — REQ-008.20-23
- Service provisioning — #228

## Requirements traceability

| Requirement | What it covers | Where tested |
|------------|----------------|--------------|
| REQ-003 | Build and e2e validation: template eval, ISO, VM test matrix | `test-iso --e2e` stages 1-4 |
| REQ-008 | Onboarding journey: template → install → first boot → services | `test-iso --e2e` stages 1-9 |
| REQ-001 | Config generation: flake.nix, hosts, hardware.nix | `nix flake check` (eval tests) |
| REQ-002 | Template data model: storage, security, desktop | Desktop screenshot validation |

## Screenshot standardization

All VM testing uses a standard screenshot pipeline:

1. QEMU monitor `screendump <path>.ppm` via `socat` to the monitor socket
2. Convert PPM → PNG via `imagemagick` (`magick` or `convert`)
3. Compare against LFS-tracked baselines at `templates/default/tests/e2e/screenshots/`

First run saves the baseline (copy captured screenshots into the baseline directory).
Subsequent runs compare captured screenshots byte-for-byte against the committed
baselines and fail on mismatch.

### LFS as natural checksum

Git LFS pointer files contain the SHA-256 of the stored object:

```
version https://git-lfs.github.com/spec/v1
oid sha256:abc123...
size 12345
```

This makes a separate `reference-hashes.json` redundant. The LFS-tracked screenshots
ARE the reference — `git diff` shows when a baseline changes, `git blame` shows who
changed it and why, and the SHA-256 is immutable in the pointer. The e2e runner uses
`cmp` for byte-for-byte comparison against the checked-out LFS files; on mismatch it
reports both SHA-256 values for debugging.

## TUI testing notes

The `ks` installer is a terminal UI (ratatui). It is not a line-oriented CLI.
When testing the TUI interactively over SSH, keep these points in mind.

### Driving the TUI over SSH

```bash
ssh -tt -i .test-iso-dev-key -p 12260 keystone@localhost ks
```

The `-tt` forces a remote PTY. Without it, `ks` fails with
`Error: No such device or address (os error 6)` because it cannot set up
terminal raw mode.

### Key sequences

Use carriage return (`\r`) not line feed (`\n`) when scripting. `\n` may
behave like navigation instead of submit.

The template fixture has two hosts (`laptop`, `server-ocean`) and one virtio
disk. The installer screens are:

1. **Host selection** — first item (`laptop`) is focused by default. Press Enter.
2. **Disk selection** — only one disk. Press Enter.
3. **Confirmation** — warns about data erasure. Press Enter to proceed.

### Terminal environment

If the VM reports `Cannot find terminfo entry for 'xterm-ghostty'`, set
`TERM=xterm-256color` before launching `ks`:

```bash
TERM=xterm-256color ks
```

### Automated TUI driving

For scripted testing, `ks install --host laptop` is preferred over driving the
TUI with `expect` or FIFO-based key injection. The headless install reuses the
same code paths (host selection, disk discovery, disko, nixos-install,
handoff) without needing a PTY. For automation, pass `--disk` so only the
destructive confirmation prompt remains, then pipe `destroy` into stdin to
satisfy it.

If TUI-level regression testing is needed (verifying screen rendering,
navigation, key bindings), use `ks --screenshot <screen>` which renders a
single screen to stdout without entering raw mode:

```bash
ks --screenshot welcome
ks --screenshot create-config
ks --screenshot hosts
```

### Do not trust the TUI alone

The installer screen shows streaming command output, but it is not the best
source of truth for install state. Use separate SSH sessions to check:

- `/tmp/keystone-install-repo` — the writable install repo (hardware config, commits)
- `/mnt/nix/var/nix/profiles/system` — whether nixos-install landed the system
- `/mnt/home/<user>/.keystone/repos/` — whether the handoff completed
- `free -h` and `ps` — whether the VM is healthy or OOM

See `CONTRIBUTOR.md` for detailed debugging commands.
