# REQ-001: Config Generation

This document defines requirements for the configuration output that the
ks must produce. The TUI generates a complete, buildable NixOS
flake directory from user-provided inputs using the `keystone.lib.mkSystemFlake`
template format.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Requirements

### Output Structure

**REQ-001.1** The TUI MUST produce a directory containing `flake.nix` and
a `hosts/<hostname>/` subdirectory with `configuration.nix` and
`hardware.nix`.

**REQ-001.2** The generated `flake.nix` MUST declare `keystone` as the
sole flake input. Nixpkgs, disko, and home-manager are provided
transitively through the keystone input.

**REQ-001.3** The generated `flake.nix` MUST call
`keystone.lib.mkSystemFlake` with an `owner`, `hosts` inventory, and
`hostsRoot = ./hosts` to produce `nixosConfigurations` outputs.

**REQ-001.4** Each host entry in the `hosts` inventory MUST declare a
`kind` field (`"server"`, `"workstation"`, `"laptop"`, or `"macbook"`)
that determines architecture, desktop, and storage defaults.

**REQ-001.5** The generated `hosts/<hostname>/hardware.nix` MUST use the
`{ system; module; }` attrset format, exporting the system architecture
and a NixOS module with hardware-specific configuration (hostId, storage
devices, boot modules).

### Content Quality

**REQ-001.6** The generated files MUST NOT contain any `TODO:` markers.

**REQ-001.7** The generated files MUST be valid Nix syntax that parses
without error via `nix-instantiate --parse`.

**REQ-001.8** The generated files SHOULD be formatted with `nixfmt` and
produce no diff when re-formatted.

**REQ-001.9** The generated `hosts/<hostname>/configuration.nix` contains
only host-specific overrides. Admin user synthesis, desktop defaults, and
storage defaults are handled by `mkSystemFlake` from the flake-level
`owner` block and host `kind`.

### Completeness

**REQ-001.10** The generated configuration MUST evaluate successfully via
`mkSystemFlake` without additional user modifications (aside from
`hardware.nix` customization for target hardware).

**REQ-001.11** The generated `flake.nix` MUST expose at least one host in
the `hosts` inventory using the user-provided hostname.

**REQ-001.12** The generated configuration MUST set `defaults.timeZone` to
a user-provided value or default to `"UTC"`.

### Config Versioning

**REQ-001.13** The TUI MUST detect config format version by inspecting the
flake structure. Version `0.0.0` is the legacy hand-wired
`nixpkgs.lib.nixosSystem` format. Version `1.0.0` is the
`keystone.lib.mkSystemFlake` format.

**REQ-001.14** When opening a repository with config version `0.0.0`, the
TUI MUST display a warning indicating the config uses a legacy format and
SHOULD offer guidance on migrating to version `1.0.0`.

**REQ-001.15** New config generation MUST always produce version `1.0.0`
format.
