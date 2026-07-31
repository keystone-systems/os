---
title: Shell Tools
description: Core CLI tools included in the Keystone terminal environment
---

# Shell Tools

Keystone Terminal ships with a curated shell toolset for daily development and
system work.

## Core shell environment

The base shell stack is:

- Zsh
- Starship
- Zoxide
- direnv with `nix-direnv`
- fzf

## Common CLI tools

Keystone also includes a practical set of command-line tools, including:

- `eza` for directory listings
- `rg` for search
- `fd` for file discovery
- `bat` for file preview
- `sd` for simple search and replace
- `bottom`, `htop`, and `ncdu` for system inspection
- `glow` for Markdown rendering
- `gh` for GitHub workflows

## Default aliases

Common aliases include:

- `ls` and `l` to `eza -1l`
- `grep` to `rg`
- `g` to `git`
- `lg` to `lazygit`
- `y` to `yazi`

## Related docs

- [Terminal Module](terminal.md)
- [Functions](functions.md)
- [TUIs](tuis.md)
