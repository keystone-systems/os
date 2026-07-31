---
title: VM Testing
description: Testing Keystone configurations in QEMU/KVM virtual machines
---

# VM Testing

This document covers testing Keystone configurations in QEMU/KVM virtual machines, including setup requirements, known issues, and troubleshooting.

## Overview

Keystone uses libvirt-managed QEMU/KVM VMs for testing NixOS configurations before deploying to physical hardware. This provides a safe, reproducible environment for validating:

- Disk encryption and ZFS configuration
- Secure Boot setup and key enrollment
- TPM2 integration
- Desktop environment (Hyprland) functionality
- System module integration

## VM Requirements

### Host System

- NixOS with libvirtd enabled
- User must be in `libvirtd` group
- QEMU with UEFI/OVMF firmware support
- Sufficient resources (4GB+ RAM, 2+ vCPUs recommended)

### NixOS Configuration

```nix
virtualisation.libvirtd.enable = true;
users.users.<youruser>.extraGroups = [ "libvirtd" ];
```

## Essential Configuration: qemu-guest.nix Profile

**Critical**: All VM configurations MUST import the qemu-guest.nix profile to function properly.

### Why qemu-guest.nix is Required

The `qemu-guest.nix` profile provides:

1. **Complete virtio driver stack** - Including graphics-related drivers
2. **QEMU guest agent** - Better host-guest communication
3. **VM-specific optimizations** - Performance tuning for virtualization
4. **Graphics backend support** - DRM/KMS drivers for VM graphics

Without this profile, you may experience:

- Missing virtio drivers
- Graphics initialization failures
- Poor VM performance
- Device detection issues

### How to Add qemu-guest.nix

In your VM configuration (e.g., `vms/test-hyprland/configuration.nix`):

```nix
{
  config,
  pkgs,
  lib,
  modulesPath,  # Required for profiles
  ...
}: {
  # Import QEMU guest profile
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # Ensure complete kernel module set
  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "virtio_pci"
    "virtio_blk"
    "virtio_net"
    "virtio_scsi"
    "sr_mod"
  ];

  # Rest of your configuration...
}
```

## VM Management with bin/virtual-machine

The `bin/virtual-machine` script handles VM lifecycle:

```bash
# Create and start VM
./bin/virtual-machine --name keystone-test-vm --start

# Create with custom resources
./bin/virtual-machine --name test --memory 8192 --vcpus 4 --disk-size 50 --start

# Post-installation: snapshot, remove ISO, reboot
./bin/virtual-machine --post-install-reboot keystone-test-vm

# Complete reset
./bin/virtual-machine --reset keystone-test-vm
```

### VM Features

- **UEFI Secure Boot** in Setup Mode (no pre-enrolled keys)
- **TPM 2.0 emulation** for testing TPM features
- **Serial console** for debugging
- **SPICE graphics** for remote viewing
- **Static IP** (192.168.100.99 on keystone-net)

### Connection Methods

```bash
# Graphical display
remote-viewer $(virsh domdisplay keystone-test-vm)

# Serial console
virsh console keystone-test-vm

# SSH (after installation)
./bin/test-vm-ssh
./bin/test-vm-ssh "systemctl status"
```

## Graphics Configuration for VMs

### Working Configuration (2025-11-08)

**QXL is the working graphics driver** for Hyprland in QEMU/KVM VMs:

```xml
<graphics type='spice' autoport='yes'>
  <listen type='address' address='127.0.0.1'/>
</graphics>
<video>
  <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1'/>
</video>
```

While QXL is primarily designed for SPICE protocol and has some limitations with Wayland, it provides sufficient DRM/KMS support for Hyprland to function in VM environments.

### Why virtio Doesn't Work

**virtio-gpu without GL acceleration is incompatible** with Hyprland:

```xml
<video>
  <model type='virtio'/>
</video>
```

**Result:** ❌ Failed - Missing virgl 3D acceleration, Hyprland cannot initialize EGL

**Explanation:**

- Plain virtio-gpu provides basic 2D framebuffer support
- Hyprland requires OpenGL ES 2.0 minimum for compositing
- Without virgl/GL acceleration, virtio-gpu cannot provide the required OpenGL context
- Attempting to use virtio results in: `libEGL warning: egl: failed to create dri2 screen`

**QXL vs virtio:**

- QXL provides sufficient DRM/KMS despite being designed for SPICE
- virtio requires GL acceleration (virgl) for Wayland compositors
- Since virgl/GL is unavailable (NVIDIA host incompatibility), QXL is the only viable option

### Hardware GL Acceleration Investigation

Extensive testing was conducted to enable hardware-accelerated graphics (OpenGL/virgl) for better performance. **All hardware acceleration approaches failed** due to NVIDIA driver incompatibilities with libvirt.

### Attempted GL Acceleration Solutions

#### 3. SDL with GL (incorrect XML syntax)

```xml
<graphics type='sdl' display=':0' gl='yes'/>
<video>
  <model type='virtio-vga-gl'/>
</video>
```

**Result:** ❌ Failed - Attribute syntax incorrect (should be child element)

**Error:**

```
The display backend does not have OpenGL support enabled
It can be enabled with '-display BACKEND,gl=on'
```

#### 4. SDL with GL (correct XML syntax)

```xml
<graphics type='sdl' display=':0'>
  <gl enable='yes'/>
</graphics>
<video>
  <model type='virtio-vga-gl'/>
</video>
```

**Result:** ❌ Failed - Same error as above

**Analysis:** libvirt not properly translating XML to QEMU command-line arguments

#### 5. SPICE with GL and explicit rendernode

```xml
<graphics type='spice'>
  <listen type='none'/>
  <image compression='off'/>
  <gl enable='yes' rendernode='/dev/dri/by-path/pci-0000:0a:00.0-render'/>
</graphics>
<video>
  <model type='virtio' heads='1' primary='yes'>
    <acceleration accel3d='yes'/>
  </model>
</video>
```

**Result:** ❌ Failed

**Error:**

```
qemu-system-x86_64: egl: eglInitialize failed: EGL_NOT_INITIALIZED
qemu-system-x86_64: egl: render node init failed
```

### Root Cause Analysis

**NixOS Issue #164436**: "libvirt: openGL does not work with Nvidia GPUs"

The fundamental problem is an incompatibility between:

- NVIDIA proprietary drivers
- libvirt's EGL initialization
- QEMU in `qemu:///system` mode

This is a **known, unresolved issue** on NixOS when using NVIDIA GPUs with libvirt OpenGL.

### Web Research Findings

Extensive web research confirmed:

- Multiple NixOS users reporting identical `eglInitialize failed` errors
- NVIDIA proprietary drivers have compatibility issues with QEMU/libvirt EGL
- SDL GL child element syntax (`<gl enable='yes'/>`) is correct per libvirt docs (added 2018)
- SPICE GL with explicit rendernode is the recommended workaround on Arch Linux
- **None of these workarounds resolve the NVIDIA + libvirt + NixOS issue**

### References

- [NixOS GitHub #164436](https://github.com/NixOS/nixpkgs/issues/164436) - libvirt OpenGL not working with NVIDIA GPUs
- [NixOS Discourse: QEMU 3D acceleration error](https://discourse.nixos.org/t/qemu-with-3d-acceleration-terminates-with-an-error-the-display-backend-does-not-have-opengl-support-enabled/59222)
- [Arch Linux Forum: virgl with libvirt](https://bbs.archlinux.org/viewtopic.php?id=238569)
- [libvirt SDL OpenGL support patches (2018)](https://listman.redhat.com/archives/libvir-list/2018-May/msg00658.html)

## Software Rendering Fallback (Optional)

If hardware acceleration is unavailable, Hyprland can use software rendering (llvmpipe):

### In VM Configuration

Keep basic virtio graphics (no GL):

```xml
<graphics type='spice' autoport='yes'>
  <listen type='address' address='127.0.0.1'/>
</graphics>
<video>
  <model type='virtio' heads='1' primary='yes'/>
</video>
```

### In Guest NixOS Configuration

Add to `modules/client/desktop/hyprland.nix` or system configuration:

```nix
environment.sessionVariables = {
  WLR_RENDERER_ALLOW_SOFTWARE = "1";
  WLR_NO_HARDWARE_CURSORS = "1";
};
```

### Trade-offs

- ✅ Works with any GPU/driver combination
- ✅ No host EGL/GL dependencies
- ✅ Reliable for development/testing
- ⚠️ Slower graphics performance (CPU-based rendering)
- ⚠️ Higher CPU usage during compositing
- ⚠️ Not suitable for graphics-intensive workloads

**Recommendation:** Only use software rendering if hardware acceleration is confirmed unavailable. With proper qemu-guest.nix configuration, basic virtio graphics should work for most testing scenarios.

## Testing Procedure

### 1. Build ISO

```bash
./bin/build-iso --ssh-key ~/.ssh/id_ed25519.pub
```

### 2. Create VM

```bash
./bin/virtual-machine --name keystone-test-vm --start
```

### 3. Connect to VM

```bash
# Graphical (for installer)
remote-viewer $(virsh domdisplay keystone-test-vm)

# Serial console (for debugging)
virsh console keystone-test-vm
```

### 4. Deploy Configuration

```bash
# From installer or host
nixos-anywhere --flake .#test-hyprland root@192.168.100.99
```

### 5. Post-Installation

```bash
# Shutdown VM
virsh shutdown keystone-test-vm

# Remove ISO and snapshot
./bin/virtual-machine --post-install-reboot keystone-test-vm
```

### 6. Verify Configuration

```bash
# SSH into VM
./bin/test-vm-ssh

# Inside VM, verify:
bootctl status              # Check Secure Boot status
zpool status rpool          # Verify ZFS pool
systemctl status hyprland   # Check desktop service
```

## Troubleshooting

### VM Won't Start

**Check OVMF firmware:**

```bash
ls -la /nix/store/*-OVMF-*/FV/
```

**Verify libvirtd:**

```bash
systemctl status libvirtd
virsh version
```

### Graphics Issues

1. **Verify qemu-guest.nix is imported** in VM configuration
2. **Check kernel modules** are loaded:
   ```bash
   lsmod | grep virtio
   ```
3. **Review system logs:**
   ```bash
   journalctl -b | grep -i "drm\|egl\|opengl"
   ```

### Hyprland Won't Start

**Check compositor logs:**

```bash
journalctl --user -u hyprland
```

**Verify environment variables:**

```bash
printenv | grep -E "WAYLAND|XDG|WLR"
```

**Test with basic Weston:**

```bash
# Install weston for testing
nix-shell -p weston
weston --backend=drm-backend.so
```

### Serial Console Issues

**Enable in kernel params:**

```nix
boot.kernelParams = [
  "console=ttyS0,115200n8"
  "console=tty0"
];
```

**Connect:**

```bash
virsh console keystone-test-vm
# Press Ctrl+] to exit
```

## Known Issues

1. **Hardware GL acceleration unavailable with NVIDIA host** (NixOS #164436)
   - No working solution as of 2025-11-08
   - Software rendering fallback available but not recommended

2. **SPICE GL requires local unix socket**
   - Cannot use GL with network-accessible SPICE (`-spice port=5900`)
   - Only works with `listen type='none'` (local only)

3. **VM performance with encryption**
   - ZFS native encryption + LUKS adds overhead
   - Use adequate vCPU/memory allocation
   - Consider snapshot-based testing to avoid repeated installations

## Best Practices

1. **Always import qemu-guest.nix** in VM configurations
2. **Use descriptive VM names** for multiple test scenarios
3. **Snapshot after successful installation** for quick rollback
4. **Test Secure Boot before production** deployment
5. **Verify TPM functionality** if using TPM features
6. **Use serial console** for debugging boot issues
7. **Keep ISO up to date** with latest configuration changes

## Future Improvements

Potential areas for enhancement:

1. **Alternative virtualization platforms**
   - Test with AMD GPU hosts
   - Evaluate qemu:///session vs qemu:///system
   - Consider non-NVIDIA solutions for GL acceleration

2. **Testing automation**
   - Automated test suite for VM configurations
   - CI/CD integration for configuration validation
   - Snapshot-based rapid testing

3. **Graphics alternatives**
   - Monitor virglrenderer/Venus developments
   - Track NixOS GitHub #164436 for NVIDIA fixes
   - Evaluate GTK display backend as SDL alternative
