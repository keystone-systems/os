---
title: Experimental features
description: The keystone.experimental flag and the current list of experimental modules
---

# Experimental features

Experimental features are functional but may change significantly in future
releases. They are not part of the stable v1 surface.

## Opting in

```nix
keystone.experimental = true;
```

This auto-enables all experimental modules. Without it (the default), only the
stable surface is active. Individual experimental modules can still be enabled
directly with `keystone.<module>.enable = true`.

The option is defined in `modules/shared/experimental.nix` — a zero-dependency
module imported by NixOS (`operating-system`) and home-manager (`terminal`).

## Current experimental features

### `keystone.notes` — Git-backed notebook sync

| | |
|---|---|
| **Module** | `modules/notes/default.nix` |
| **Flag** | `keystone.notes.enable` (defaults to `keystone.experimental`) |
| **Milestone** | [v2 — Un-experimental](https://github.com/ncrmro/keystone/milestone/10) |

Syncs a git-backed notes repository on a timer using `repo-sync`. Optionally
initializes a zk Zettelkasten notebook structure with templates, directories,
and LSP integration.

**Why experimental**: The notes module was originally the source of truth for
project discovery. With the move to declarative `projects.yaml`, the notes
module's role is shifting to pure knowledge management. The option surface and
zk integration may be restructured.

**Options**: `keystone.notes.enable`, `.repo`, `.path`, `.syncInterval`,
`.commitPrefix`, `.sync.enable`, `.daily.enable`, `.daily.symlinkPath`,
`.daily.journalPath`, `.daily.dateFormat`, `.zk.enable`

### `keystone.terminal.conventions` — Agent instruction generation

| | |
|---|---|
| **Module** | `modules/terminal/conventions.nix` |
| **Flag** | `keystone.terminal.conventions.enable` (defaults to `keystone.experimental`) |
| **Milestone** | [v2 — Un-experimental](https://github.com/ncrmro/keystone/milestone/10) |

Reads `archetypes.yaml` and generates tool-native instruction files
(`~/.claude/CLAUDE.md`, `~/.gemini/GEMINI.md`, `~/.codex/AGENTS.md`).
In development mode, also generates `~/.keystone/repos/AGENTS.md`.

**Why experimental**: The archetype schema, convention composition model, and
generated file format are actively evolving. Role definitions and convention
assignment patterns may change.

### `keystone.os.zram` — Compressed RAM swap

| | |
|---|---|
| **Module** | `modules/os/zram.nix` |
| **Flag** | `keystone.os.zram.enable` (defaults to `keystone.experimental`) |
| **Milestone** | [v2 — Un-experimental](https://github.com/ncrmro/keystone/milestone/10) |

Wraps nixpkgs `zramSwap` with keystone defaults: one zstd-compressed
zram device sized at 50% of RAM and `vm.swappiness=150` so the kernel
reaches for compressed swap before evicting clean page-cache.

**Why experimental**: the right defaults differ between workstation,
laptop, and server profiles, and we have not yet tuned per-archetype
or validated the interaction with existing disk swap on every host.

**Options**: `keystone.os.zram.enable`, `.memoryPercent`, `.swappiness`

## For module authors

To mark a module as experimental:

1. Import `../shared/experimental.nix`.
2. Default `enable` to `config.keystone.experimental`.
3. Add `[EXPERIMENTAL]` to the module file header.
4. Add an entry to this page.

```nix
{
  imports = [ ../shared/experimental.nix ];

  options.keystone.<module>.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.keystone.experimental;
    description = "Enable <feature> (EXPERIMENTAL).";
  };
}
```

## Graduating from experimental

To promote a feature to stable (targeted for
[v2](https://github.com/ncrmro/keystone/milestone/10)):

1. Freeze the option surface — no breaking changes without migration.
2. Add comprehensive flake checks covering the feature's contract.
3. Document the feature in `docs/`.
4. Change the `enable` default from `config.keystone.experimental` to `true`.
5. Remove the `[EXPERIMENTAL]` marker from the module header.
6. Move the entry from this list to the stable surface list.
