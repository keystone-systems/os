---
title: Reasoning about your keystone-config
description: How to think about this consumer flake — fleet model, scopes, and where keystone stops and vanilla Nix begins
---

# Reasoning about your keystone-config

This repo is a **consumer flake** for [Keystone](https://github.com/ncrmro/keystone).
It assumes you know what a [Nix flake](https://nix.dev/concepts/flakes) is,
roughly what a [NixOS module](https://nixos.org/manual/nixos/stable/#sec-writing-modules)
and a [Home Manager module](https://nix-community.github.io/home-manager/index.xhtml#sec-usage-configuration)
look like, and that
[search.nixos.org](https://search.nixos.org/packages) is where you find
package names. Nothing in this doc re-teaches that.

What it does cover: how Keystone's `mkSystemFlake` turns a small declarative
inventory into a real fleet, and where the convention stops so you can drop
back to vanilla Nix.

## A real fleet, in one file

Here's what a four-host fleet looks like — `flake.nix` more or less in
full:

```nix
keystone.lib.mkSystemFlake {
  admin = {
    username = "ada";
    fullName = "Ada Lovelace";
    email = "ada@example.com";
    initialPassword = "changeme";
    sshKeys = [
      "ssh-ed25519 AAAA…ada@workstation"
      "ssh-ed25519 AAAA…ada@laptop"
    ];
  };

  defaults = {
    timeZone = "America/New_York";
    updateChannel = "stable";
  };

  hostsRoot = ./hosts;

  shared = {
    # CLI tools, every user, every host (Linux + macOS).
    userModules = [
      ({ pkgs, ... }: { home.packages = with pkgs; [ fd ripgrep jq ]; })
    ];

    # System packages, OS-wide, Linux hosts only (macbook silently skips).
    systemModules = [
      ({ pkgs, ... }: { environment.systemPackages = with pkgs; [ btop ]; })
    ];

    # GUI apps, only on desktop-class hosts (laptop + workstation).
    desktopUserModules = [
      ({ pkgs, ... }: { home.packages = with pkgs; [ obsidian bitwarden-desktop ]; })
    ];
  };

  keystoneServices = {
    git.host        = "server";   # Forgejo runs on `server`; every other host
    mail.host       = "server";   # gets the matching client config wired up
    monitoring.host = "server";   # without you having to repeat yourself.
  };

  hosts = {
    workstation = { kind = "workstation"; };
    laptop      = { kind = "laptop"; };
    server      = { kind = "server"; };
    macbook     = { kind = "macbook"; };   # Home Manager only — no NixOS, no agenix
  };
}
```

What `mkSystemFlake` does with that:

- Emits `nixosConfigurations.workstation`, `…laptop`, `…server` — full
  NixOS systems with `ada` as admin, the right timezone, the shared user
  and system modules layered on, and the relevant keystone services
  enabled by kind.
- Emits `homeConfigurations.macbook` — Home Manager only, picking up
  `shared.userModules` but skipping the system + desktop hooks.
- Emits `packages.<system>.iso` — one installer ISO that boots on any of
  the Linux hosts and lets `ks install` finish the install.
- Reads `hosts/<name>/configuration.nix` and `hosts/<name>/hardware.nix`
  (Linux only) for per-host overrides, layered on top of everything above.

See [`flake.md`](flake.md) for the full argument and output reference.

## Scopes — the mental model

Every change you make lives in one of these scopes. Pick the scope first;
the file follows.

| Scope | Applies to | Where to write it |
|---|---|---|
| Fleet, system | OS-wide on every Linux host | `shared.systemModules` |
| Fleet, user | Per-user on every host (Linux + macOS) | `shared.userModules` |
| Desktop, user | Per-user on `laptop` + `workstation` only | `shared.desktopUserModules` |
| Host, system | One Linux host's NixOS | `hosts/<name>/configuration.nix` |
| Host, hardware | One Linux host's disks/CPU/firmware | `hosts/<name>/hardware.nix` |
| Host, user (macOS) | A `macbook` host | `hosts/<name>/configuration.nix` |
| Shared infra | A service whose host every other host should know about | `keystoneServices.<service>.host` |
| Secret | Anything that mustn't land in the Nix store | `secrets/<name>.age` + `age.secrets.*` |

Two questions resolve every entry: **fleet vs per-host**, and **system vs
user**.

## NixOS vs Home Manager

Two module systems, two namespaces. Keystone wires both up; you compose the
option names for the scope you're writing in.

| Module system | Lives on | Common option roots | Reference |
|---|---|---|---|
| NixOS | Linux hosts | `environment.*`, `services.*`, `networking.*`, `users.*`, `boot.*` | [options.nixos.org](https://search.nixos.org/options) |
| Home Manager | Every user, every host (including macOS) | `home.*`, `programs.<name>.*`, `xdg.*`, `wayland.*` | [Home Manager options](https://nix-community.github.io/home-manager/options.xhtml) |

**The `programs.<name>` namespace exists in both systems with different
schemas.** `programs.zsh.interactiveShellInit` is NixOS;
`programs.zsh.initExtra` is Home Manager. They look similar; they are not
interchangeable. The host's `configuration.nix` is a NixOS module on Linux
hosts and a Home Manager module on macOS — use the option names that match.

## Installing programs

Pick the scope, drop the package in the right module hook:

```nix
# CLI everywhere → shared.userModules → home.packages
# Daemon everywhere → shared.systemModules → environment.systemPackages
# GUI on desktops → shared.desktopUserModules → home.packages
# One host only → hosts/<name>/configuration.nix → environment.systemPackages
```

Package names: [search.nixos.org/packages](https://search.nixos.org/packages).

## When to drop down to vanilla Nix

`mkSystemFlake` returns a regular flake output set. If keystone's
convention doesn't cover a case — a custom package, a check, a darwin
config, an alternative test — extend the return value with `//`:

```nix
outputs = { keystone, ... }:
  keystone.lib.mkSystemFlake { /* … */ } // {
    packages.x86_64-linux.my-tool =
      keystone.inputs.nixpkgs.legacyPackages.x86_64-linux.callPackage ./my-tool.nix { };

    checks.x86_64-linux.my-check = /* … */;
  };
```

Same for inputs: declare your own `nixpkgs` / `llm-agents` /
`browser-previews` and have keystone follow them via
`keystone.inputs.<name>.follows = "<name>";` in `flake.nix`. Comments in the
scaffolded `flake.nix` show the canonical pattern.

The 80% case fits the helper. The other 20% is plain Nix and you have full
access to it.

## File layout

- `flake.nix` — single `mkSystemFlake` call
- `hosts/<name>/` — one directory per attribute in `hosts = { ... }`
- `hosts/<name>/configuration.nix` — per-host overrides
- `hosts/<name>/hardware.nix` — Linux hardware metadata (no macbook)
- `secrets/*.age` + `secrets.nix` — agenix; see [`secrets/README.md`](../../secrets/README.md)
- `docs/keystone/` — these docs; edit freely

`server` is just an example name. Rename to anything that fits — keep the
entry in `hosts = { ... }` and the directory under `hosts/` in sync.

## Going deeper

- [`flake.md`](flake.md) — full `mkSystemFlake` argument + output reference
- [`onboarding.md`](onboarding.md) — step-by-step first-host walkthrough
- [`system-agent-prompts.md`](system-agent-prompts.md) — prompts for
  asking your AI agent to handle common workflows
- Keystone's helper source:
  [`lib/templates.nix`](https://github.com/ncrmro/keystone/blob/main/lib/templates.nix)
- agenix: [ryantm/agenix](https://github.com/ryantm/agenix)
- Nix fundamentals (when the question isn't about keystone):
  [nix.dev](https://nix.dev),
  [NixOS manual](https://nixos.org/manual/nixos/stable/),
  [Home Manager manual](https://nix-community.github.io/home-manager/)
