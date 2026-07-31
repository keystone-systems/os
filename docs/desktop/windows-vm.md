---
title: Windows VM
description: Running Windows virtual machines on Keystone workstations with the hypervisor module
---

# Windows VM

Keystone workstations can run Windows virtual machines through the
`keystone.os.hypervisor` module.

This uses libvirt and QEMU/KVM with:

- OVMF for UEFI firmware,
- `swtpm` for TPM 2.0 emulation,
- SPICE for display access, and
- virt-manager on desktop hosts.

## Enable the hypervisor

```nix
keystone.os.hypervisor = {
  enable = true;
  defaultUri = "qemu:///session";
  connections = [ ];
};
```

On Keystone Desktop systems, this also enables virt-manager and the related
desktop integration.

## Why this works well for Windows

The hypervisor module already sets up the pieces that Windows guests usually
need:

- UEFI boot via OVMF
- TPM emulation via `swtpm`
- managed libvirt connections
- session or remote libvirt URIs for desktop users

That makes it a reasonable base for Windows 11 guests, test VMs, and desktop
application compatibility workflows.

## Typical workflow

1. Enable `keystone.os.hypervisor`
2. Rebuild the workstation
3. Open virt-manager
4. Create a Windows guest with UEFI firmware and TPM enabled
5. Install Windows normally

## Notes

- Keystone documents the hypervisor stack in terms of the shared libvirt
  workflow, so Windows VMs fit into the same host setup used for NixOS testing
  and general virtualization
- Desktop users are automatically integrated with libvirt through the hypervisor
  module

## Related docs

- [Desktop](../desktop.md)
- [VM Testing](../os/testing-vm.md)
- [Desktop Keybindings](keybindings.md)
