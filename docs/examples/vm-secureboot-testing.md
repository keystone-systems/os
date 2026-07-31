# VM Secure Boot Testing Guide

This guide shows how to use the `bin/virtual-machine` script to test Secure Boot integration in Keystone.

## Overview

The `bin/virtual-machine` script creates libvirt VMs with UEFI Secure Boot enabled in **Setup Mode**. This means:

- Secure Boot firmware is present and active
- No Platform Key (PK) is enrolled (Setup Mode)
- The firmware allows unsigned operating systems to boot
- The Keystone installer can enroll custom Secure Boot keys

This configuration is essential for testing Keystone's lanzaboote integration and custom key enrollment.

## Quick Start

### 1. Create a VM in Setup Mode

```bash
# Create and start a VM with default settings
./bin/virtual-machine --name secureboot-test --start
```

**What this does**:

- Creates a VM with UEFI Secure Boot enabled
- Initializes NVRAM from empty OVMF_VARS template (no pre-enrolled keys)
- Automatically boots in Setup Mode
- Loads the Keystone installer ISO (if available at `vms/keystone-installer.iso`)

### 2. Connect to the VM

```bash
# Option 1: Serial console (recommended for automated testing)
virsh console secureboot-test

# Option 2: Graphical display (recommended for interactive use)
remote-viewer $(virsh domdisplay secureboot-test)
```

### 3. Verify Setup Mode

Inside the VM, after booting from the Keystone installer:

```bash
bootctl status
```

**Expected output**:

```
System:
     Firmware: UEFI 2.70 (EDK II 1.00)
  Secure Boot: disabled (setup)
   Setup Mode: setup
```

**Interpretation**:

- `Secure Boot: disabled (setup)` - Firmware has Secure Boot capability, currently in setup mode
- `Setup Mode: setup` - No Platform Key enrolled, ready for key enrollment
- This is the **correct state** for testing the Keystone installer

## Common Workflows

### Test Keystone Installer with Secure Boot

```bash
# 1. Build the Keystone installer ISO with SSH key
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub

# 2. Create VM in setup mode
./bin/virtual-machine --name keystone-install-test --start

# 3. VM boots from ISO automatically

# 4. Connect via SSH (wait ~30 seconds for boot)
ssh root@192.168.100.99

# 5. Verify setup mode
bootctl status
# Should show "Secure Boot: disabled (setup)"

# 6. Run the installer (will enroll keys and transition to User Mode)
# ... installer commands ...

# 7. After installation, verify User Mode
bootctl status
# Should show "Secure Boot: enabled (user)"
```

### Reset VM to Setup Mode

To test key enrollment again, reset the VM:

```bash
# Delete VM completely
./bin/virtual-machine --reset secureboot-test

# Recreate fresh (automatically in setup mode)
./bin/virtual-machine --name secureboot-test --start
```

### Test Multiple Secure Boot Scenarios

```bash
# Scenario 1: Setup Mode (no keys)
./bin/virtual-machine --name test-setup --start
virsh console test-setup
# bootctl status → setup mode

# Scenario 2: User Mode (keys enrolled by installer)
# ... let installer enroll keys ...
# bootctl status → user mode

# Scenario 3: Return to Setup Mode
./bin/virtual-machine --reset test-setup
./bin/virtual-machine --name test-setup --start
# bootctl status → setup mode again
```

## Verification Methods

### Primary: bootctl status

```bash
# Inside the VM
bootctl status
```

**Setup Mode Output**:

```
System:
     Firmware: UEFI 2.70 (EDK II 1.00)
  Secure Boot: disabled (setup)
   Setup Mode: setup
```

**User Mode Output** (after key enrollment):

```
System:
     Firmware: UEFI 2.70 (EDK II 1.00)
  Secure Boot: enabled (user)
   Setup Mode: user
```

### Alternative: Manual EFI Variable Check

```bash
# Check SetupMode variable directly
od --address-radix=n --format=u1 \
  /sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c

# Expected output (setup mode):
# ... 7 0 0 0 1
#           ↑ Last byte is 1 (setup mode)
```

### From Host: NVRAM File Size

```bash
# Check NVRAM file size
stat -c%s vms/secureboot-test/OVMF_VARS.fd

# Expected: 540672 bytes (empty template, no pre-enrolled keys)
```

## Advanced Usage

### Custom VM Configuration

```bash
# Large VM for performance testing
./bin/virtual-machine \
  --name large-secureboot-test \
  --memory 8192 \
  --vcpus 4 \
  --disk-size 50 \
  --start

# Custom ISO path
./bin/virtual-machine \
  --name custom-iso-test \
  --iso /path/to/custom.iso \
  --start
```

### Monitor Secure Boot State Transitions

```bash
# Before installer runs
bootctl status
# Secure Boot: disabled (setup)

# ... installer enrolls keys ...

# After installer completes
bootctl status
# Secure Boot: enabled (user)

# This transition confirms successful key enrollment
```

### Inspect UEFI Variables Directly

```bash
# Check SetupMode variable
cat /sys/firmware/efi/efivars/SetupMode-* | od -An -t u1
# Expected: 1 (setup mode active)

# Check SecureBoot variable
cat /sys/firmware/efi/efivars/SecureBoot-* | od -An -t u1
# Expected: 0 (Secure Boot not enforcing in setup mode)

# List all Secure Boot related variables
ls /sys/firmware/efi/efivars/ | grep -i secure
```

## Troubleshooting

### OVMF Firmware Not Found

**Error**:

```
ERROR: OVMF firmware not found!
```

**Solution**:

```bash
# Ensure libvirtd is enabled (provides OVMF firmware)
# In configuration.nix:
virtualisation.libvirtd.enable = true;

# Rebuild system
sudo nixos-rebuild switch
```

### VM Shows "Secure Boot: enabled (user)"

**Symptom**: `bootctl status` shows user mode instead of setup mode

**Cause**: NVRAM file already has Platform Key enrolled

**Solution**:

```bash
# Reset to setup mode by deleting and recreating
./bin/virtual-machine --reset <vm-name>
./bin/virtual-machine --name <vm-name> --start
```

### bootctl Shows "Secure Boot: n/a"

**Symptom**: `bootctl status` doesn't show Secure Boot information

**Possible Causes**:

1. VM didn't boot with UEFI (check machine type = q35)
2. Kernel doesn't expose efivars
3. Running bootctl outside of UEFI environment

**Solution**:

```bash
# Verify UEFI boot
ls /sys/firmware/efi
# Should list efi directories

# Check efivars are mounted
mount | grep efivars
# Should show efivars filesystem
```

## Technical Details

### How Setup Mode Works

**UEFI Secure Boot Modes**:

1. **Setup Mode** (Target for testing)
   - Platform Key (PK) is not enrolled
   - Firmware allows unsigned code to execute
   - All key variables (PK, KEK, db, dbx) can be modified
   - Transitions to User Mode when PK is enrolled

2. **User Mode** (After key enrollment)
   - Platform Key is enrolled
   - Secure Boot signature verification enforces trusted boot chain
   - Unsigned code is rejected

### NVRAM File Structure

```
vms/keystone-test-vm/
├── disk.qcow2              # VM disk image
└── OVMF_VARS.fd            # NVRAM file (540,672 bytes if fresh)
                            # Contains UEFI variables:
                            #   SetupMode = 0x01
                            #   SecureBoot = 0x00
                            #   PK = (empty)
```

### libvirt XML Configuration

The script creates VMs with:

```xml
<os>
  <loader readonly='yes' secure='yes' type='pflash'>
    /nix/store/.../edk2-x86_64-secure-code.fd
  </loader>
  <nvram template='/nix/store/.../edk2-i386-vars.fd'>
    /home/user/keystone/vms/keystone-test-vm/OVMF_VARS.fd
  </nvram>
</os>
<features>
  <smm state='on'>
    <tseg unit='MiB'>48</tseg>
  </smm>
</features>
```

Key attributes:

- `secure='yes'` - Enables Secure Boot in firmware
- `template` - Source for NVRAM initialization
- `smm state='on'` - Required for Secure Boot (System Management Mode)

## Expected Timeline

**VM Creation**: 15-30 seconds

- Firmware detection: ~2 seconds
- NVRAM copy: <1 second
- VM definition: ~5 seconds
- VM start: ~10 seconds

**First Boot**: 20-40 seconds

- UEFI firmware init: ~5 seconds
- Boot from ISO: ~15-30 seconds

**Total Time to Verification**: ~1-2 minutes from command to `bootctl status` output

## Success Criteria

After following this guide, you should be able to:

- ✅ Create a VM with one command
- ✅ VM boots in Secure Boot setup mode (verified with `bootctl status`)
- ✅ NVRAM file created at correct location (`vms/<name>/OVMF_VARS.fd`)
- ✅ NVRAM file has correct size (540,672 bytes)
- ✅ VM accessible via serial console and graphical display
- ✅ Ready to test Keystone installer's Secure Boot integration

## Reference

**Related Scripts**:

- `bin/virtual-machine` - VM creation and management
- `bin/build-iso` - Build Keystone installer ISO

**UEFI/Secure Boot Resources**:

- `bootctl(1)` man page
- UEFI Specification 2.10
- OVMF Documentation: https://github.com/tianocore/tianocore.github.io/wiki/OVMF
- Arch Wiki Secure Boot: https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot
