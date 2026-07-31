---
title: ZFS and Linux Kernel Version Compatibility
description: How ZFS and Linux kernel versions interplay and why they must be matched
---

# ZFS and Linux Kernel Version Compatibility

## Research Question

How do ZFS and Linux kernel versions interplay, and why must they be matched? Specifically for NixOS and the Keystone project issue #68 (AMD GPU support requiring newer kernels while maintaining ZFS compatibility).

## Executive Summary

ZFS is an **out-of-tree kernel module** that must be recompiled for each kernel version. Because Linux provides **no stable kernel ABI**, ZFS developers must actively patch their code whenever kernel internals change. This creates a fundamental tension: new hardware support (like AMD RDNA4 GPUs) requires bleeding-edge kernels, but ZFS compatibility lags behind kernel releases.

## The Core Problem

### Linux Kernel ABI Instability

The Linux kernel **intentionally provides no stable internal API** for kernel modules. From the [Linux kernel documentation](https://www.kernel.org/doc/Documentation/process/stable-api-nonsense.rst):

> "Linux does not have a stable in-kernel API."

This means:

- Functions appear, disappear, or change signatures between kernel versions
- Struct fields are added, removed, or reordered
- How you're supposed to do things shifts with each release
- Distribution kernels may have additional patches changing behavior

### What ZFS Must Do

To compile on a new kernel version, OpenZFS developers must:

1. **Inspect kernel changes** — manually review what APIs changed
2. **Adapt ZFS code** — modify their implementation to match new interfaces
3. **Test thoroughly** — ensure no subtle bugs were introduced
4. **Tag a release** — only then officially support the new kernel

This process takes time. A new kernel might release, but ZFS support could lag by weeks or months.

## OpenZFS Version Compatibility Matrix

| OpenZFS Version | Release Date | Linux Kernel Support | Status    |
| --------------- | ------------ | -------------------- | --------- |
| **2.4**         | Dec 18, 2025 | 4.18 - 6.18          | Current   |
| **2.3**         | Oct 17, 2024 | 4.18 - 6.15          | Supported |
| **2.2**         | Jul 27, 2023 | 4.18 - 6.15          | LTS       |
| 2.1             | Apr 19, 2021 | 3.10 - 6.7           | EOL       |
| 2.0             | Nov 30, 2020 | 3.10 - 5.15          | EOL       |

Source: [endoflife.date/openzfs](https://endoflife.date/openzfs)

### Key Insight

OpenZFS 2.4 supports up to kernel 6.18. If you need kernel 6.19+ (hypothetically for new hardware), you must wait for a ZFS update or use `zfs_unstable` (risky for data integrity).

## How NixOS Handles ZFS Compatibility

### The `meta.broken` Flag

NixOS marks ZFS kernel modules as "broken" when the kernel version is outside the supported range:

```nix
# From pkgs/os-specific/linux/zfs/generic.nix
kernelIsCompatible = kernel:
  (lib.versionAtLeast kernel.version kernelMinSupportedMajorMinor)
  && (lib.versionOlder kernel.version (nextMajorMinor kernelMaxSupportedMajorMinor));

meta.broken = buildKernel && !kernelIsCompatible kernel;
```

When `meta.broken = true`, NixOS **refuses to build** — your configuration won't evaluate.

### The `kernelModuleAttribute` Property

This is the key link between a ZFS package and its kernel modules:

```nix
# Access the kernel module for a specific kernel
config.boot.kernelPackages.${pkgs.zfs.kernelModuleAttribute}
```

This attribute (`zfs` or `zfs_unstable`) identifies which kernel module package to use.

### Finding Compatible Kernels

The official NixOS Wiki provides this pattern to find the latest ZFS-compatible kernel:

```nix
let
  zfsCompatibleKernelPackages = lib.filterAttrs (
    name: kernelPackages:
    (builtins.match "linux_[0-9]+_[0-9]+" name) != null
    && (builtins.tryEval kernelPackages).success
    && (!kernelPackages.${config.boot.zfs.package.kernelModuleAttribute}.meta.broken)
  ) pkgs.linuxKernel.packages;

  latestKernelPackage = lib.last (
    lib.sort (a: b: (lib.versionOlder a.kernel.version b.kernel.version)) (
      builtins.attrValues zfsCompatibleKernelPackages
    )
  );
in
{
  boot.kernelPackages = latestKernelPackage;
}
```

**Warning**: This can cause kernel version to jump backward when older kernels are removed from nixpkgs.

### Deprecated: `latestCompatibleLinuxPackages`

Previously, `config.boot.zfs.package.latestCompatibleLinuxPackages` provided automatic selection, but this was deprecated. The manual filtering approach above is now recommended.

## Keystone Issue #68 Analysis

### The Problem

AMD RDNA4 GPUs (RX 9070 series) require kernel 6.14+ for:

- SMU (System Management Unit) resume functionality
- Proper suspend/resume without fan issues
- Avoiding hard reboot requirements

But at the time of writing:

- `linuxPackages` (default) = 6.12.x — **too old for RDNA4**
- `linuxPackages_latest` = 6.18.x — **ZFS compatible** (OpenZFS 2.4 supports up to 6.18)

### The Proposed Solution

The issue proposes a `keystone.desktop.kernel` option:

```nix
kernel = mkOption {
  type = types.either (types.enum [ "default" "latest" ]) types.package;
  default = "latest";
  description = ''
    - "default": NixOS default kernel (linuxPackages)
    - "latest": Latest ZFS-compatible kernel (linuxPackages_latest)
    - Or a kernel package (e.g., pkgs.linuxPackages_6_14)
  '';
};
```

With a build-time ZFS compatibility assertion:

```nix
assertions = [{
  assertion =
    let
      zfsEnabled = builtins.elem "zfs" (config.boot.supportedFilesystems or []);
      zfsModule = config.boot.kernelPackages.${pkgs.zfs.kernelModuleAttribute} or null;
      isBroken = zfsModule != null && (zfsModule.meta.broken or false);
    in !zfsEnabled || !isBroken;
  message = ''
    Kernel ${config.boot.kernelPackages.kernel.version} is incompatible with ZFS.
    Use keystone.desktop.kernel = "default" or wait for nixpkgs ZFS update.
  '';
}];
```

## Practical Recommendations

### For Keystone Users

1. **Check current compatibility** before upgrading:

   ```bash
   # In a nix shell
   nix eval nixpkgs#linuxPackages_latest.kernel.version
   nix eval nixpkgs#zfs.version
   ```

2. **Use the assertion** — let NixOS fail at build time rather than boot time.

3. **Plan for future kernel needs** — if you're buying new AMD hardware, check the kernel requirements against current ZFS support.

### For the Implementation

The issue's proposed implementation is sound:

1. **Default to "latest"** — `linuxPackages_latest` is usually ZFS-compatible
2. **Provide escape hatches** — allow explicit kernel package specification
3. **Fail early** — the assertion catches incompatibility at build time
4. **Document the matrix** — help users understand their options

## Key Takeaways

1. **ZFS lags kernel releases** — this is unavoidable due to Linux's unstable ABI
2. **NixOS makes this explicit** — the `meta.broken` flag prevents building incompatible configurations
3. **The gap is usually weeks, not months** — OpenZFS 2.4 already supports 6.18
4. **Build-time assertions are crucial** — catching issues at build time is far better than runtime failures
5. **Hardware drivers vs ZFS is a real tension** — new GPUs need new kernels, but ZFS users must wait for support

## Sources

- [OpenZFS Releases](https://github.com/openzfs/zfs/releases)
- [OpenZFS endoflife.date](https://endoflife.date/openzfs)
- [ZFS - NixOS Official Wiki](https://wiki.nixos.org/wiki/ZFS)
- [DKMS vs kmod Guide - Klara Systems](https://klarasystems.com/articles/dkms-vs-kmod-the-essential-guide-for-zfs-on-linux/)
- [NixOS ZFS Module Source](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/tasks/filesystems/zfs.nix)
- [NixOS ZFS Package Source](https://github.com/NixOS/nixpkgs/blob/master/pkgs/os-specific/linux/zfs/generic.nix)
- [Keystone Issue #68](https://github.com/ncrmro/keystone/issues/68)
