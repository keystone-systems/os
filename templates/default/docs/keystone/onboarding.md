---
title: Keystone onboarding
description: Progressive walkthrough from `nix flake new` to a fully-secured first host
---

# Keystone onboarding

This walkthrough takes a freshly scaffolded `keystone-config` and gets you to a
first running host. It is **progressive**: each step is independently readable,
makes one focused change, and ends with a "you should now see…" check. Stop
whenever it makes sense — you can carry on later from the same point without
re-reading earlier steps.

> Installed with the public ISO and Docker container? Follow the canonical
> [quickstart](https://git.ncrmro.com/ks.systems/os/src/branch/main/docs/quickstart.md)
> through its first-boot health
> check, then resume this walkthrough at
> [Step 6](#step-6--first-boot-housekeeping-per-host-ssh-key--password).
> Steps 0–5 below are the advanced build-from-source installation path.

The walkthrough assumes you have *one* current machine (call it your **driver**;
likely your MacBook or current Linux box) and are bringing up *one* new
**target** host (likely a fresh laptop or server). Steps 1–4 happen on the
driver, step 5 happens during install, steps 6–8 happen on the target after
first boot.

## What you'll have at the end

- The release installer ISO flashed to a USB stick and its matching controller
  image available through Docker or Podman.
- The target host installed, booting from its own disk, reachable over SSH.
- A per-host SSH key generated on the target — your driver's key was only the
  bootstrap.
- The temporary `changeme` LUKS password and TPM-less unlock replaced with a
  user-chosen password and TPM auto-unlock.
- (Optional) A sops-encrypted GitHub PAT wired in so `ks update` and
  `nix flake update` don't trip the 60 req/hr anonymous rate limit.

## Anatomy of each step

Every numbered step below uses the same anatomy:

- **Goal** — what you'll have when the step is done.
- **Edit** — files to change, with the exact field.
- **Run** — commands.
- **Verify** — what success looks like.
- **If it fails** — one-line pointer.

---

## Step 0 — Decide your hosts

**Goal:** Pick the first host you want to bring up. This walkthrough scaffolds a
`laptop`. If you only need a server, use the `server` host instead — the
flow is the same, just substitute the name. The shipped `macbook` host is a
Home Manager-only target (no NixOS system, no ISO); see
`hosts/macbook/configuration.nix` for that flow.

**Edit:** Nothing yet.

**Run:** Read the host list. Each subdirectory under `hosts/` is one host:

```bash
ls hosts/
# laptop  macbook  server
```

**Verify:** You can name the one host you'll bring up first.

**If it fails:** You're in the wrong directory. `cd` into the repo you just
made with `nix flake new`.

---

## Step 1 — Fill in owner identity

**Goal:** Replace the `Your Name` / `keystone@example.com` placeholders in
`flake.nix` with your real identity. This is the user that will be created on
every host.

> `flake.nix` is one call to `keystone.lib.mkSystemFlake`. See
> [`flake.md`](flake.md) for the full argument reference if you want
> context on what else you could pass.

**Edit:** `flake.nix`. Find the `admin` block (look for `TODO:` markers) and
set:

- `username` — your login name (lowercase, no spaces). This is the Linux user
  account created on the target.
- `fullName` — your display name.
- `email` — used for Git commits made on the host.
- `timeZone` — IANA tz name, e.g. `America/Chicago` or `Europe/Berlin`. See
  `timedatectl list-timezones` on a Linux box.

Leave `initialPassword = "changeme"` for now — Step 5 walks through replacing
it.

**Run:**

```bash
nix flake check
```

**Verify:** `nix flake check` exits 0 with no errors. If the placeholders are
still present, the check should still pass — the placeholders don't break
evaluation, they're just wrong values.

**If it fails:** `nix flake check` errors usually point at the file and line.
Most likely cause at this stage: missing quotes around a string value, or
removed a comma.

---

## Step 2 — Add your driver's SSH key

**Goal:** Bake your *current machine's* SSH public key into the installer ISO,
so that when the target host boots from the USB, you can SSH into the live
installer from your driver.

This step uses your driver's existing key. You'll generate a new per-host key
*on the target* later (Step 6).

**Edit:** Find your driver's public key:

```bash
# On macOS / Linux
cat ~/.ssh/id_ed25519.pub        # preferred
cat ~/.ssh/id_rsa.pub            # fallback if no ed25519 key

# No key yet? Generate one:
ssh-keygen -t ed25519 -C "your@email"
```

Paste the full pubkey line into `flake.nix` under `admin.sshKeys`:

```nix
admin = {
  username = "...";
  fullName = "...";
  email = "...";
  initialPassword = "changeme";
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... your@driver"
  ];
};
```

**Run:**

```bash
grep -A2 sshKeys flake.nix
```

**Verify:** The grep output shows your key string.

**If it fails:** Common mistakes: forgetting the surrounding double quotes,
splitting the key across multiple lines, or pasting the *private* key by
accident. The public key starts with `ssh-` and is a single line.

---

## Step 3 — Build the installer ISO

**Goal:** Produce a bootable ISO at `result/iso/` with your SSH key embedded.

See [`os-installer.md`](os-installer.md) for cross-platform notes (building
an x86_64-linux ISO from an aarch64-darwin MacBook needs a remote builder or
relies on Hydra cache hits).

**Run:**

```bash
nix build .#iso
```

The ISO is a single artifact that bakes in installer targets for every Linux
host declared in `flake.nix` — you don't build a per-host ISO.

**Verify:**

```bash
ls -lh result/iso/
# -r--r--r-- 1 root root 1.4G ... keystone-server-installer-0.0.0.iso
```

A `.iso` file should be present and at least several hundred MB.

**Optional — preview the ISO in a VM before burning:**

```bash
nix develop -c iso-vm-preview   # opens a QEMU window, mirrors serial to your terminal
```

Confirms the ISO boots cleanly to a login prompt (or installer TUI) without
spending a USB write cycle. See [`os-installer.md`](os-installer.md) §
"Validate the ISO in a VM" for what to watch for.

**If it fails:** If the build wants to compile something huge from source
(GHC, Chromium, etc.), your Nix instance is missing the keystone cache. Add
`ks-systems.cachix.org` to `nix.settings.substituters` on your driver, or
build on a host that already has it (e.g. another keystone machine).

---

## Step 4 — Burn the ISO to USB

**Goal:** Write `result/iso/*.iso` to a USB stick.

**Run** (Linux + macOS):

```bash
# If you already built in Step 3:
nix develop -c iso-burn-usb

# To build and burn in one go (skips Step 3's manual `nix build .#iso`):
nix develop -c iso-burn-usb --build
```

(Or just `iso-burn-usb [--build]` from an activated dev shell or
direnv-loaded shell.)

The script lists only USB devices (internal disks are filtered out), shows
the picked device's model and partition layout, and requires you to type
`BURN` (uppercase) before any writes happen. See
[`os-installer.md`](os-installer.md) § "Write the ISO to USB" for what each
prompt means and for the manual `dd` fallback (required on Windows; use
Rufus in DD Image mode).

> **Warning:** Burning a USB stick destroys all data on the target. The
> script's USB-only filter prevents picking your driver disk, but if you
> drop down to raw `dd`, the entire safety is on you to verify the path
> immediately before running.

**Verify:** Plug the USB into the target host. Power on. Select the USB from
the UEFI boot menu. The Keystone installer banner appears on the screen.

**If it fails:** UEFI won't boot the USB → confirm Secure Boot is *off* in
firmware for now (you'll enroll keys in Step 7). Wrong key bytes → re-burn,
maybe the `dd` was interrupted.

---

## Step 5 — Install the target

**Goal:** Use the release controller's pinned NixOS Anywhere to lay down the OS
on the target's local disk without installing Nix on the driver.

**Run:**

The installer auto-DHCPs and starts root password SSH. Read the address on the
target console. If it is not visible, log in as `root` with password
`changeme`, then run `ip -br address`.

From the root of this repository on your driver:

```bash
mkdir -p .keystone-install
docker run --rm -it \
  -v "$PWD:/workspace:ro" \
  -v "$PWD/.keystone-install:/state" \
  ghcr.io/keystone-systems/os-installer:v0.13.0-rc.2 \
  install --target <installer-ip> --flake /workspace#laptop
```

The controller:

1. Authenticates to the live ISO as `root` with the public password
   `changeme` and shows its SSH fingerprint and hardware inventory.
2. Evaluates the stable disk identifiers in `hosts/laptop/` and requires you
   to type an exact erase phrase. Stop if any identity or disk is wrong.
3. Runs NixOS Anywhere and creates root encryption with the temporary
   password `changeme`.
4. Reboots. Enter `changeme` at the target's disk-unlock prompt.
5. Reconnects as `root` with `changeme` and checks the installed revision,
   root storage health, and failed systemd units.

This password is public. Use only a trusted local network and do not expose the
target to the Internet during bootstrap.

**Verify:** The target reboots and boots into the installed system. You can
SSH in as `root` with `changeme` for the health check, or as your owner user.
Both are temporary bootstrap accounts in this generation.

**If it fails:** Install errors usually surface in the SSH session.
`nixos-install` failures are the most common — check disk free space and
that the disko config matches the target's actual block devices.

---

## Step 6 — First-boot housekeeping (per-host SSH key + password)

**Goal:** Two independent housekeeping tasks on the freshly-installed
host:

1. Replace the temporary `changeme` user password with one you choose.
2. Generate a per-host SSH key that gives this target its own outbound
   identity — useful once the fleet has more than one host (so it can
   SSH to siblings) and required by Step 8 if you wire up sops
   (the host's pubkey becomes a recipient for system-scoped secrets).

The driver's bootstrap key in `admin.sshKeys` is *not* removed — it
continues to authorize inbound SSH from the driver. This step adds the
new target identity alongside it, not as a replacement.

**Edit:** Nothing in the repo yet — these changes happen *on the target*.

**Run:** On the target (SSH in as your owner user):

```bash
# 1. Replace the changeme user password.
passwd

# 2. Generate a per-host SSH key (the target's outbound identity).
ssh-keygen -t ed25519 -C "<username>@<hostname>"
cat ~/.ssh/id_ed25519.pub
```

Copy the new pubkey output. **On your driver**, edit your `keystone-config`
repo and add it to `admin.sshKeys` in `flake.nix` *alongside* the existing
driver key — this is what enables fleet-internal SSH (target reaches other
hosts that share the same `admin.sshKeys`). If your fleet is single-host
for now, you can skip this addition; the key still serves as a secrets
recipient in Step 8.

Commit and push the repo change if you have initialized a Git remote.

**Verify:**

```bash
# On the driver
ssh -i ~/.ssh/id_ed25519 <username>@<target-ip>
```

You're back in. The new per-host key on the target can also be used to SSH
*from* the target to other hosts.

**If it fails:** `passwd` complaining about complexity → use a longer
passphrase. SSH refusing the new key → you need to deploy the new `flake.nix`
to the target (`sudo nixos-rebuild switch --flake .#laptop` after copying the
repo over, or wait until `ks update` is wired up).

---

## Step 7 — Enroll TPM unlock + replace the `changeme` LUKS password

**Goal:** Move from "anyone with the literal string `changeme` can unlock your
disk" to "the TPM unlocks the disk automatically when Secure Boot, kernel, and
initrd match expected measurements, and a user-chosen password is the fallback."

**Edit:** Nothing in the repo. The enrollment is a one-shot on the target.

**Run:** On the target, as your owner user:

```bash
sudo keystone-enroll-password
```

This script:

1. Prompts you for a new LUKS password (cannot be `changeme`).
2. Adds your new password to a LUKS keyslot.
3. Enrolls the TPM with the current PCR measurements so future boots
   auto-unlock without prompting (unless boot integrity changes).
4. **Removes the default `changeme` keyslot.**

For TPM-only enrollment (no password fallback — advanced; rescue media required
if the TPM ever fails) or recovery-key enrollment, see `keystone-enroll-tpm`
and `keystone-enroll-recovery`.

**Verify:**

```bash
# Reboot
sudo systemctl reboot
```

After reboot, the disk should unlock without prompting for a password. The
shell login prompts for your *user* password (set in Step 6), not the LUKS
password.

To prove the `changeme` slot is gone:

```bash
sudo cryptsetup luksDump /dev/disk/by-partlabel/disk-root-root | grep -A1 'Keyslot'
```

Should not show the slot that was tied to `changeme`. (Slot indices differ by
disko config — the key signal is that `cryptsetup open --test-passphrase` with
input `changeme` fails.)

**If it fails:** TPM enrollment can fail if the system was booted without
Secure Boot enabled or with mismatched PCRs. The script tells you which. If
you can't recover, the `changeme` slot is still active until the script
explicitly removes it (read the script's output carefully — it confirms before
deleting).

---

## Step 8 — (Optional) Add a sops-encrypted GitHub PAT

**Goal:** Stop hitting GitHub's 60 req/hr anonymous rate limit (the source of
recurring `403 API rate limit exceeded` errors during `ks update` and
`nix flake update`).

See [`github-token.md`](github-token.md) for the full walkthrough. Summary:

1. Generate a fine-grained PAT at <https://github.com/settings/personal-access-tokens>
2. Encrypt it with `ks secrets edit` into the host's `secrets/<host>.yaml`.
3. Uncomment the `keystone.secrets.provided` block in
   `hosts/<host>/configuration.nix` (see [`github-token.md`](github-token.md)).
4. Rebuild and reboot.

Without this, you'll still install fine — it just makes subsequent updates
more reliable on flaky networks or shared IPs.

---

## What's next

- More hosts: copy `hosts/laptop/` to a new directory, adjust `configuration.nix`
  and `hardware.nix`, add the host name to `flake.nix`.
- Services (mail, monitoring, photos, etc.): see the keystone main repo's
  `modules/server/` for opt-in service modules.
- Desktop environment: `hosts/<name>/configuration.nix` can enable
  `keystone.desktop.enable = true;` for Hyprland + Walker.
- Day-to-day updates: `ks update` (relocks the consumer flake, rebuilds, and
  activates).
