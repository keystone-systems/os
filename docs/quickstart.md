---
title: Install Keystone OS from the ISO and Docker container
description: Burn the published ISO and install one host from a second computer without installing Nix
---

# Keystone OS quickstart

A public installer release consists of an ISO, a starter configuration, and an
installer container published and tested together. The target boots the ISO;
the container runs NixOS Anywhere from a second computer and completes the
first-boot check. The second computer does not need Nix.

> **Not available yet:** continue only when one entry on the
> [Keystone OS releases page](https://github.com/keystone-systems/os/releases)
> includes the installer ISO, `SHA256SUMS`, a starter-configuration archive,
> and either an exact container image reference or a loadable image archive.
> Older prereleases without all four parts cannot be used for this quickstart.
> No complete public installer bundle is currently available. The steps below
> define the release interface; do not substitute historical artifacts,
> commands, or credentials.

## Installation outline

1. Download every artifact from one complete installer release.
2. Check the downloads and write the ISO to a USB drive.
3. Boot the target computer and find its network address and disk identity.
4. Configure the release's starter flake for that hardware.
5. Run the exact Docker command published with the release.
6. Confirm the target disk immediately before installation.
7. Let the installer reconnect after reboot and report the health check.

## Before you begin

You need:

- the target computer; installation will erase the disk you select;
- a second Linux or macOS computer with Docker and a POSIX shell;
- a USB drive large enough for the ISO; and
- a trusted local network connecting both computers.

A release may add other tested controller platforms. Do not translate the
published shell command to PowerShell or another shell unless that release
provides and tests the alternate command.

The release page states its temporary login and disk-encryption credentials.
They are public bootstrap credentials. Keep the target on a trusted network,
do not expose its SSH service to the internet, and replace the credentials
after the first health check.

## 1. Download one complete release

Open the release page. Download its ISO, `SHA256SUMS`, and starter-configuration
archive. Use the exact container image reference shown on the page, or download
the container archive linked there. Do not combine artifacts from different
releases.

Check the downloaded files for transfer corruption:

```bash
sha256sum --check SHA256SUMS --ignore-missing
```

On macOS, use `shasum -a 256` to compare each downloaded file with its entry in
`SHA256SUMS`. These checks detect damaged or incomplete downloads; they do not
authenticate files obtained from a compromised release page. Follow the
release's signature instructions when signed artifacts become available.

If the release provides a container archive, run the `docker load` command
printed on that release page. Record the image reference reported by Docker.

## 2. Write the ISO to USB

Use an image-writing tool that supports raw or DD image mode. Select the
release ISO as the source and the USB drive as the destination. Writing the
image destroys everything already on the USB drive.

- Linux: use GNOME Disks, KDE ISO Image Writer, or another raw-image writer.
- macOS: use a raw-image writer such as balenaEtcher.

Do not copy the ISO onto the USB filesystem as an ordinary file. Eject the USB
only after the writer reports completion.

## 3. Boot and inspect the target

Connect the target to a trusted wired network when possible, insert the USB,
and choose it from the computer's UEFI boot menu. Use the temporary console
login printed on the release page. Then display the target's addresses and
disks:

```bash
ip -brief address
lsblk -d -o NAME,PATH,SIZE,MODEL,SERIAL,TRAN
ls -l /dev/disk/by-id/
```

Record the LAN address on the connected interface. Ignore loopback
(`127.0.0.1`) and disconnected interfaces.

Identify the intended installation disk by model, serial number, and size.
Record its stable `/dev/disk/by-id/...` path. Stop if more than one disk could
be the target.

Generate the target's NixOS hardware configuration and retain the output for
the next step:

```bash
nixos-generate-config --show-hardware-config
```

## 4. Configure the starter flake

Extract the starter-configuration archive on the Docker computer and enter its
directory:

```bash
tar -xf keystone-starter-config-*.tar.gz
cd keystone-starter-config-*
```

Choose one host from `hosts/`, normally `laptop` or `server`. Complete the
`TODO:` values in `flake.nix`, including the admin identity and an SSH public
key that the installed admin account can use.

Use the hardware configuration generated on the target as the basis for
`hosts/<host>/hardware.nix`. Restore the Keystone settings documented in the
starter file, including `networking.hostId`, then replace
`__KEYSTONE_DISK__` with the stable `/dev/disk/by-id/...` path recorded above.
Do not retain the starter's QEMU guest import or assumed virtual hardware on a
physical target.

The installer container evaluates this configuration and displays the selected
disk before it allows installation.

## 5. Run the published container command

The release page provides a copyable command with its exact image reference and
bootstrap options. Run it from the starter-configuration directory after
replacing only the target address and host name. Its command has this shape:

```bash
TARGET_IP=192.168.1.100
TARGET_HOST=laptop
INSTALLER_IMAGE='RELEASE_IMAGE_REFERENCE'

mkdir -p .keystone-install
docker run --rm -it \
  -v "$PWD:/workspace:ro" \
  -v "$PWD/.keystone-install:/state" \
  "$INSTALLER_IMAGE" \
  install --target "$TARGET_IP" --flake "/workspace#$TARGET_HOST"
```

The example image value is deliberately non-runnable. Copy the real value from
the complete release; do not guess it.

Before erasing anything, the released installer must show the remote SSH
identity, hardware inventory, and every configured disk, then require an exact
interactive confirmation. Read the model, serial number, size, and stable path
again. Confirm only when they identify the intended target.

The released installer runs NixOS Anywhere, waits for the target to reboot, and
performs its documented first-boot checks. Follow the release page for any
console unlock step. Logs and a machine-readable result remain under
`.keystone-install/` when the release implements this interface.

## 6. Secure the installed host

Do not treat the first successful boot as a hardened system. Confirm that the
installer reports the installed revision, healthy root storage, and no
unexpected failed systemd units.

The installed admin account and disk may still use release bootstrap
credentials. Resume the
[onboarding walkthrough at Step 6](keystone/onboarding.md#step-6--first-boot-housekeeping-per-host-ssh-key--password)
immediately to configure permanent SSH access, replace temporary passwords,
configure durable disk unlocking, and enable snapshots and backups.

## Advanced paths

- [Build the installer ISO from source](os/iso-generation.md)
- [Run NixOS Anywhere directly](os/installation.md)
- [Test the ISO and installed system in a VM](testing/iso-os-virtual-machine.md)
- [Understand the starter configuration](keystone/keystone-config.md)
