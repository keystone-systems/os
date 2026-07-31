---
title: Keystone Testing Procedure
description: VM-based testing workflow for validating deployments and features
---

# Keystone Testing Procedure

**Version**: 1.0
**Date**: 2025-11-03

## Overview

Keystone uses a VM-based testing workflow for validating deployments and testing features. This document describes the automated testing scripts and common workflows.

---

## Testing Scripts

### bin/test-deployment

**Purpose**: Full VM deployment testing (fresh install)

**What it does**:

1. Stops/resets existing test VM
2. Optionally rebuilds ISO with SSH keys
3. Creates/starts VM from ISO (TPM emulation enabled)
4. Waits for VM boot and SSH access
5. Deploys via nixos-anywhere to `.#test-server`
6. Unlocks disk via initrd SSH (password: "keystone")
7. Runs Secure Boot provisioning
8. Verifies deployment (SSH, ZFS, Secure Boot)

**Usage**:

```bash
./bin/test-deployment                    # Normal test run
./bin/test-deployment --rebuild-iso      # Rebuild ISO first
./bin/test-deployment --hard-reset       # Force VM cleanup
./bin/test-deployment --debug            # Show full output
```

**Time**: 10-15 minutes (full redeploy)

**Use when**: Testing fresh installations, major changes, Secure Boot changes

---

### bin/update-test-vm

**Purpose**: Incremental configuration updates (fast iteration)

**What it does**:

1. Verifies VM is running and accessible
2. Builds configuration locally (or on VM with `--build-host`)
3. Copies closure to VM via nixos-rebuild
4. Activates new configuration
5. Optionally reboots VM

**Usage**:

```bash
./bin/update-test-vm                    # Quick update (no reboot)
./bin/update-test-vm --reboot           # Update and reboot
./bin/update-test-vm --build-host       # Build on VM (slow network)
```

**Time**: 1-3 minutes

**Use when**: Iterating on module changes, testing configuration updates

**Preserves**: All VM state (enrolled keys, data, TPM enrollment)

---

### bin/virtual-machine

**Purpose**: VM lifecycle management

**What it does**:

- Creates VMs with UEFI Secure Boot (Setup Mode)
- Configures TPM 2.0 emulation
- Manages VM lifecycle (start, stop, reset)
- Post-installation workflows (snapshot, ISO removal)

**Usage**:

```bash
./bin/virtual-machine --name test-vm --start          # Create and start
./bin/virtual-machine --post-install-reboot test-vm   # Post-install cleanup
./bin/virtual-machine --reset test-vm                 # Complete removal
./bin/virtual-machine --reset-setup-mode test-vm      # Reset Secure Boot
```

**Network**: VMs connect to `keystone-net` with static IP `192.168.100.99`

---

### bin/build-iso

**Purpose**: Build Keystone installer ISO with optional SSH keys

**What it does**:

- Builds installation media from `.#iso`
- Optionally injects SSH public keys for remote installation
- Creates symlink: `result` → ISO file

**Usage**:

```bash
./bin/build-iso                                      # No SSH keys
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub     # With SSH key
./bin/build-iso --ssh-key "ssh-ed25519 AAA..."      # Direct key string
```

---

## Common Testing Workflows

### Workflow 1: Fresh Deployment Testing

```bash
# Deploy fresh system
./bin/test-deployment

# SSH in
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.100.99

# Test feature (e.g., TPM enrollment)
sudo keystone-enroll-recovery --auto

# Verify
sudo reboot
# System should unlock automatically via TPM
```

---

### Workflow 2: Iterative Development

```bash
# Make changes to module
vim modules/tpm-enrollment/default.nix

# Quick update to VM (preserves state)
./bin/update-test-vm

# SSH and test
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.100.99
sudo keystone-enroll-recovery --auto

# Repeat as needed
```

---

### Workflow 3: Testing Boot Changes

```bash
# Make boot-related changes
vim modules/disko-single-disk-root/default.nix

# Update and reboot
./bin/update-test-vm --reboot

# Verify boot behavior
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.100.99
```

---

### Workflow 4: Complete Reset and Redeploy

```bash
# Clean slate
./bin/test-deployment --hard-reset --rebuild-iso

# Fresh deployment with latest changes
```

---

## VM Configuration

### Test Server Details

- **Configuration**: `.#test-server` (flake.nix)
- **Hostname**: `keystone-test-vm`
- **IP Address**: `192.168.100.99` (static)
- **Network**: `keystone-net` (libvirt network)
- **Disk**: `/dev/vda` (20GB default)
- **TPM**: 2.0 emulation enabled
- **Secure Boot**: UEFI with OVMF, starts in Setup Mode

### Enabled Modules

- `modules/server` - Base server configuration
- `modules/disko-single-disk-root` - ZFS + LUKS encryption
- `modules/secure-boot` - Secure Boot with lanzaboote
- `modules/initrd-ssh-unlock` - Remote disk unlock
- `modules/tpm-enrollment` - TPM enrollment (enabled by default)

---

## SSH Access

### Standard SSH (ignores host key changes)

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.100.99
```

### Why These Options?

Test VMs are recreated frequently, causing:

- Host key changes (new SSH keys on each deploy)
- "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!" errors

These options:

- Disable host key checking (safe for test VMs)
- Don't modify ~/.ssh/known_hosts
- No manual cleanup needed

---

## Testing Checklist

### Before Committing Changes

- [ ] Run `./bin/test-deployment` - verify fresh deployment works
- [ ] Test feature-specific workflows (e.g., TPM enrollment)
- [ ] Verify documentation matches actual behavior
- [ ] Check error handling (disable Secure Boot, remove TPM, etc.)
- [ ] Test rollback: `ssh root@192.168.100.99 'nixos-rebuild switch --rollback'`

### After Major Changes

- [ ] Test with `--rebuild-iso` to ensure ISO build works
- [ ] Verify Secure Boot enrollment completes
- [ ] Test initrd SSH unlock works
- [ ] Confirm automatic boot unlock (if TPM enrolled)

---

## Troubleshooting

### VM Won't Start

```bash
# Check VM status
virsh list --all | grep keystone-test-vm

# Check libvirt network
virsh net-list | grep keystone-net

# View serial console
virsh console keystone-test-vm

# Check logs
virsh dumpxml keystone-test-vm
```

### SSH Connection Failed

```bash
# Check VM IP
virsh domifaddr keystone-test-vm

# Verify network
virsh net-dhcp-leases keystone-net

# Try serial console instead
virsh console keystone-test-vm
```

### Deployment Hangs

```bash
# Check if waiting for disk unlock
virsh console keystone-test-vm
# Look for password prompt

# Manually unlock via serial console
# Enter: keystone
```

### Update Failed

```bash
# Rollback on VM
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.100.99
sudo nixos-rebuild switch --rollback

# Or reset and redeploy
./bin/virtual-machine --reset keystone-test-vm
./bin/test-deployment
```

---

## Script Maintenance

**IMPORTANT**: When modifying testing scripts, update this document to reflect:

- New flags or options
- Changed behavior
- New workflows
- Updated timings

Testing scripts to keep in sync:

- `bin/test-deployment`
- `bin/update-test-vm`
- `bin/virtual-machine`
- `bin/build-iso`

---

## Related Documentation

- **VM Management**: `bin/virtual-machine --help`
- **Secure Boot Testing**: `docs/examples/vm-secureboot-testing.md`
- **TPM Enrollment**: `docs/tpm-enrollment.md`
- **Manual Test Plans**: `docs/specs/REQ-*-test-plan.md`

---

**Document Version**: 1.0
**Last Updated**: 2025-11-03
**Maintainer**: Keystone Project
