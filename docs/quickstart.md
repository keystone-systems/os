---
title: Install Keystone OS from the ISO and Docker container
description: Boot the published ISO and install one host from a second computer without installing Nix
---

# Keystone OS quickstart

Keystone OS `v0.13.0-rc.2` pairs a bootable ISO with an installer container.
Boot the target from the ISO, prepare its configuration on a second computer,
and run the matching container. The second computer needs Docker, not Nix.

> **Use spare hardware or a virtual machine.** Installation erases the disk
> you select. Installation uses `changeme` as both the temporary root SSH
> password and the disk-encryption passphrase. Keep the target on a trusted
> local network, then replace this temporary first-boot configuration after the
> health check.
>
> We have booted the published ISO, connected over root SSH, evaluated a target
> configuration, and reached the destructive confirmation prompt in a Digital
> Twin. The latest full desktop run stopped while building a pinned Codex
> dependency, before installing to disk or rebooting the target. Use this
> release for testing only.

## What you need

- An x86-64 target with a disk you can erase
- An x86-64 Linux computer with Docker and a POSIX shell
- A USB drive large enough for the 1.4 GB ISO
- A trusted local network connecting both computers

## 1. Download the matched release

Create a working directory and download the ISO, installer archive, and
checksums from the same release:

```bash
mkdir keystone-v0.13.0-rc.2
cd keystone-v0.13.0-rc.2

curl -LO https://github.com/keystone-systems/os/releases/download/v0.13.0-rc.2/keystone-os-v0.13.0-rc.2-x86_64-linux.iso
curl -LO https://github.com/keystone-systems/os/releases/download/v0.13.0-rc.2/keystone-installer-v0.13.0-rc.2-x86_64-linux.oci.tar.gz
curl -LO https://github.com/keystone-systems/os/releases/download/v0.13.0-rc.2/SHA256SUMS
sha256sum --check SHA256SUMS
```

The checksum file detects incomplete or damaged downloads; this release does
not yet include signed artifacts.

## 2. Write and boot the ISO

Write `keystone-os-v0.13.0-rc.2-x86_64-linux.iso` to the USB drive with a raw
image writer such as GNOME Disks, KDE ISO Image Writer, or balenaEtcher. Do not
copy the ISO onto the USB filesystem as an ordinary file.

Boot the target from the USB drive. At the target's console, record the LAN
address and inspect its disks:

```bash
ip -brief address
lsblk -d -o NAME,PATH,SIZE,MODEL,SERIAL,TRAN
ls -l /dev/disk/by-id/
```

Identify the installation disk by model, serial number, and size. Record its
stable `/dev/disk/by-id/...` path. Stop if more than one disk could be the
target.

## 3. Prepare the starter configuration

On the second computer, download the source archive for the same tag and copy
its starter configuration:

```bash
curl -L https://github.com/keystone-systems/os/archive/refs/tags/v0.13.0-rc.2.tar.gz \
  | tar xz
cp -R os-0.13.0-rc.2/templates/default keystone-config
cd keystone-config
```

Edit `flake.nix` and fill in the administrator fields. Then adapt
`hosts/laptop/hardware.nix` for the target:

1. Replace `__KEYSTONE_DISK__` with the stable disk path recorded above.
2. Replace the QEMU guest defaults with the target's hardware configuration.
3. Set a unique eight-character hexadecimal `networking.hostId` for ZFS.
4. Add an SSH public key for the installed administrator.

The ISO can print a starting hardware configuration:

```bash
nixos-generate-config --show-hardware-config
```

When you copy that output into `hardware.nix`, keep Keystone's storage and
host-ID settings. The installer evaluates the flake and lists every configured
disk it will erase before changing the target.

### Ask an agent to help

Open `keystone-config` with a coding agent and use this prompt:

> Help me adapt this Keystone v0.13.0-rc.2 starter configuration for a new
> laptop. Ask for the target IP address. Show me how to find its stable disk
> path and generate its hardware configuration from the booted ISO. Review
> every edit before running the installer. Do not erase anything until the
> installer prints the disk identity and I type its exact confirmation line.

## 4. Load and run the installer container

Load the release's OCI archive into Docker:

```bash
gzip -dc ../keystone-installer-v0.13.0-rc.2-x86_64-linux.oci.tar.gz \
  | docker load
```

Create a local state directory, then run the installer container from the
`keystone-config` directory. Replace the example address with the target's LAN
address:

```bash
mkdir -p "$HOME/.local/state/keystone-installer"

docker run --rm -it \
  -v "$PWD:/workspace" \
  -v "$HOME/.local/state/keystone-installer:/state" \
  ghcr.io/keystone-systems/os-installer:v0.13.0-rc.2 \
  install --target 192.168.1.100 --flake /workspace#laptop
```

The installer container authenticates to the live ISO with `changeme`, prints
the remote SSH identity and hardware inventory, evaluates the configuration,
and lists the disks it will erase. Type the confirmation line only when the
displayed model, serial number, size, and stable path identify the intended
disk.

After installation, enter `changeme` at the target console if the encrypted
root filesystem prompts for its passphrase. The installer container waits for
SSH to return, then checks the installed revision, root filesystem, and failed
systemd units. Logs and a JSON result remain in
`~/.local/state/keystone-installer`.

## 5. Disable the bootstrap access

The RC does not automate bootstrap cleanup. Keep the host on a trusted network
until you deploy a hardened generation and verify that root password SSH is
rejected.

First, log in as the administrator you set in `flake.nix` and change that
account's `changeme` password:

```bash
ssh keystone@192.168.1.100
passwd
exit
```

Replace `keystone` and the address with your administrator name and target
address. On the second computer, set
`keystone.os.releaseBootstrap.enable = false;` in `flake.nix`. Then copy the
configuration to the target and activate it:

```bash
tar czf - . | ssh keystone@192.168.1.100 \
  'mkdir -p ~/keystone-config && tar xzf - -C ~/keystone-config'
ssh -t keystone@192.168.1.100 \
  'sudo nixos-rebuild switch --flake ~/keystone-config#laptop'
```

Confirm that root password SSH is rejected:

```bash
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no \
  root@192.168.1.100
```

Continue at
[Step 6 of the onboarding walkthrough](keystone/onboarding.md#step-6--first-boot-housekeeping-per-host-ssh-key--password)
to establish the host's key-based identity. Complete the later disk-unlock and
backup steps separately.

## Report a failed install

Open a [Keystone OS issue](https://github.com/keystone-systems/os/issues) with:

- the target hardware model;
- the installer container's JSON result and relevant log excerpt;
- the phase that failed; and
- whether the target was still running the ISO or had rebooted.

Do not include passwords, private keys, tokens, or a complete environment dump.

## Advanced paths

- [Build the installer ISO from source](os/iso-generation.md)
- [Run NixOS Anywhere directly](os/installation.md)
- [Test the ISO and installed system in a VM](testing/iso-os-virtual-machine.md)
- [Understand the starter configuration](keystone/keystone-config.md)
