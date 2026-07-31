---
title: Keystone OS install
description: Complete guide for installing NixOS using the Keystone installer ISO and nixos-anywhere
---

# Keystone OS install

Complete guide for installing NixOS using the Keystone installer ISO and nixos-anywhere.

## Prerequisites

- Keystone ISO generated and burned to USB (see [ISO Generation](iso-generation.md))
- Target machine capable of booting from USB with UEFI firmware
- Minimum hardware: 4 GB RAM, 32 GB disk
- Network connectivity for the target machine
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) installed on your development machine

## Overview

Keystone uses a two-phase installation approach with [disko](https://github.com/nix-community/disko) for declarative disk partitioning and [lanzaboote](https://github.com/nix-community/lanzaboote) for Secure Boot:

1. **Boot Phase**: Boot target machine from USB installer
2. **Installation Phase**: Use nixos-anywhere with disko to install the root system
3. **First Boot**: Systemd units automatically configure additional disks and ZFS pools

## Phase 1: Boot from USB

1. Boot the target machine from the Keystone USB installer
2. Wait for the system to fully boot and auto-configure networking
3. Get the IP address: `ip addr show`
4. Note the IP address for remote installation

**Note**: Headless installation procedures are not yet documented. You'll need console access to retrieve the IP address.

## Phase 2: Install with nixos-anywhere

### Prerequisites

- Target machine booted from Keystone ISO
- SSH connectivity to the installer
- Disko configuration file (disko.nix)

### Run Installation

```bash
# From your local machine with your NixOS configuration
nixos-anywhere --flake .#your-config root@<installer-ip>
```

The installation process:

1. **Disko** partitions and formats the root disk only
2. **nixos-anywhere** installs the base NixOS system
3. System reboots into the installed OS

### What Disko Handles

Disko configures the root disk with:

- Partitioning (UEFI boot, swap, root)
- LUKS encryption (if configured)
- ZFS root pool creation
- Essential datasets for NixOS

## Phase 3: First Boot and Additional Disks

### Automatic Disk Initialization

On first boot, systemd units automatically:

1. **Detect additional disks** not managed by disko
2. **Create ZFS pools** on additional drives
3. **Reuse encryption keys** from root disk for additional LUKS devices
4. **Create ZFS datasets** with appropriate properties
5. **Set up mount points** and permissions

### Post-Boot Configuration

The NixOS modules include systemd units that handle:

- **Additional storage pools**: Data storage, backups, media
- **ZFS dataset creation**: With compression, encryption, snapshots
- **TPM integration**: After initial manual unlock and attestation
- **Secure boot setup**: Key generation and enrollment

### Verification

After first boot, verify the installation:

```bash
# Check ZFS pools
zpool list
zfs list

# Check systemd services
systemctl status keystone-*

# Check disk encryption
lsblk -f
```

## Configuration Examples

### Client Configuration

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    keystone.url = "github:ncrmro/keystone";
  };

  outputs = { nixpkgs, keystone, ... }: {
    nixosConfigurations.client = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        keystone.nixosModules.client
        ./hardware-configuration.nix
        {
          # Your custom configuration
          users.users.myuser = {
            isNormalUser = true;
            extraGroups = [ "wheel" ];
          };
        }
      ];
    };
  };
}
```

### Server Configuration

```nix
nixosConfigurations.server = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    keystone.nixosModules.server
    ./hardware-configuration.nix
    {
      # Server-specific configuration
      services.openssh.enable = true;
      networking.firewall.allowedTCPPorts = [ 22 ];
    }
  ];
};
```

## Troubleshooting

### Network Issues

```bash
# Check network status on installer
ip addr show
systemctl status dhcpcd

# Test connectivity
ping 8.8.8.8
```

### SSH Connection Problems

```bash
# Verify SSH is running
systemctl status sshd

# Check SSH configuration
cat /etc/ssh/sshd_config

# View authorized keys
cat ~/.ssh/authorized_keys
```

### Installation Failures

```bash
# Check disko output
journalctl -u disko

# Verify disk configuration
lsblk -f
```

## Security Notes

- The installer allows root SSH access with key-based authentication only
- Password authentication is disabled
- Consider using dedicated SSH keys for the installer
- The ISO contains your public keys - treat it accordingly
- LUKS encryption keys are automatically managed across disks

## Next Steps

After successful installation:

1. **Configure users and access control**
2. **Set up backup destinations**
3. **Configure VPN and networking**
4. **Install application-specific services**
5. **Enable automatic updates**

See the main README for infrastructure architecture and service configuration options.
