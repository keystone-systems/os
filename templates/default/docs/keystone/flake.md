---
title: How `flake.nix` is structured
description: Reference for `keystone.lib.mkSystemFlake`, the helper your `flake.nix` calls
---

# How `flake.nix` is structured

The scaffolded `flake.nix` is a single call to `keystone.lib.mkSystemFlake`.
You describe the fleet declaratively — admin identity, fleet-wide defaults,
shared modules, the host inventory — and the helper expands that into the
standard flake outputs.

## What `mkSystemFlake` produces

| Output | Contents |
|---|---|
| `nixosConfigurations.<host>` | One entry per Linux host (`kind = "laptop"` / `"workstation"` / `"server"`). Used by `nixos-rebuild`, `ks switch`, the installer. |
| `homeConfigurations.<host>` | One entry per macOS host (`kind = "macbook"`). Deployed with `home-manager switch --flake .#<username>@<host>`. |
| `packages.<system>.iso` | A single installer ISO that boots on any declared Linux host. Build with `nix build .#iso`. |
| `packages.<system>.vm-image-<host>` | Direct-boot qcow2 images per Linux host — useful for fast VM validation without going through the installer. |
| `packages.<system>.installerTargetsJson` | Manifest describing each host's storage/disk targets, consumed by `ks install`. |

## The arguments

These are the fields you'll set in `flake.nix`:

### `admin`

Single source of truth for the admin user across the fleet. Every host
inherits this identity unless you explicitly override per-host.

```nix
admin = {
  username = "ada";
  fullName = "Ada Lovelace";
  email = "ada@example.com";
  initialPassword = "changeme";   # replaced post-install with `passwd`
  sshKeys = [ "ssh-ed25519 AAAA…" ];
};
```

### `defaults`

Fleet-wide defaults the helper applies to every host before per-host
overrides.

```nix
defaults = {
  timeZone = "America/New_York";
  updateChannel = "stable";   # "stable" | "unstable"
};
```

### `hostsRoot`

Directory containing per-host subdirectories. The template uses `./hosts`.
For each host declared in `hosts = { ... }`, `mkSystemFlake` automatically
pulls in `<hostsRoot>/<name>/configuration.nix` (and `hardware.nix` for
Linux hosts) if those files exist.

```nix
hostsRoot = ./hosts;
```

### `shared.*`

Three "apply everywhere" module hooks. Pick the right one based on scope:

| Hook | Applied to | Use for |
|---|---|---|
| `shared.systemModules` | OS-wide on every host | Root-owned services, system packages other users need, NixOS-level settings |
| `shared.userModules` | Per-user on every host (Linux + macOS) | CLI tools, dotfiles, Home Manager program enables |
| `shared.desktopUserModules` | Per-user on desktop hosts only (laptop, workstation) | GUI apps — Obsidian, browsers, VS Code |

Skip a hook entirely if you have nothing fleet-wide to apply at that scope.

### `keystoneServices`

Global service-to-host wiring. Keystone validates each `*.host` matches a
declared host, then auto-enables both the server and any clients on the
fleet.

```nix
keystoneServices = {
  git.host = "server";       # forgejo runs on `server`, every host gets the SSH config
  mail.host = "server";      # stalwart runs on `server`, every host gets aliases
  monitoring.host = "server";
};
```

Skip the whole block if you're not running shared infrastructure yet.

### `hosts`

The host inventory itself. Each attribute name is a host; the value picks a
`kind` and (optionally) overrides defaults like `hostname` or
`nixosModules`.

```nix
hosts = {
  laptop = {
    kind = "laptop";
    # Optional: pull in extra NixOS modules just for this host.
    # nixosModules = [ keystone.nixosModules.server ];
  };

  server = {
    kind = "server";
    # `hostname` defaults to the attribute name. Override only if it needs
    # to differ from the host name in this inventory.
  };

  macbook = {
    kind = "macbook";   # Home Manager only; no nixosConfigurations entry.
  };
};
```

Valid `kind` values: `laptop`, `workstation`, `server`, `macbook`.

## Where the helper lives

`mkSystemFlake` is defined in
[`lib/templates.nix`](https://github.com/ncrmro/keystone/blob/main/lib/templates.nix)
in the keystone repo. Read that file if you need to see exactly how the
inventory becomes flake outputs, what defaults each `kind` carries, or
which keystone NixOS modules are applied automatically per kind.

## Common patterns

**One host to start.** Comment out (or delete) `server` and `macbook` from
`hosts`, leaving just `laptop`. `mkSystemFlake` is happy with a single
entry.

**Add an MCP/CI box.** Add another `kind = "server"` host with a distinct
attribute name (`server-ci`, `server-staging`, etc.). Point relevant
`keystoneServices.*.host` at it.

**Bring a new user into the fleet.** Use `shared.users` (see
`lib/templates.nix` for the schema) — it's the same shape as `admin` but
keyed by username.
