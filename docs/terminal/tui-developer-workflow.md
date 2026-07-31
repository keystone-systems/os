---
title: TUI Developer Workflow
description: Terminal-based development workflow using modern TUI tools
---

# TUI Developer Workflow

Keystone embraces a TUI-first development philosophy. Terminal User Interface tools provide a consistent, efficient environment that works identically whether you're on a local machine or connected to a remote server.

## Why TUI-First?

**Consistency**: The same tools work the same way everywhere—your laptop, a server, a VM, a container.

**Efficiency**: Keyboard-driven workflows are faster once mastered. No context switching between mouse and keyboard.

**Low Bandwidth**: TUI applications transmit text, not pixels. Work effectively over slow connections.

**Resumable Sessions**: With terminal multiplexers, your entire workspace persists. Disconnect and reconnect without losing state.

**Reproducibility**: Declaratively configure your environment with Nix. New machine? Same setup in minutes.

## Core Tools

### Shell

Zsh with a minimal, fast prompt. Nix provides the shell and any tools you need:

```nix
programs.zsh = {
  enable = true;
  autosuggestion.enable = true;
  syntaxHighlighting.enable = true;
};
```

### Editor: Helix

**Helix** is a modern, modal editor with batteries included—LSP, tree-sitter, and multiple cursors work out of the box:

```bash
hx .
```

Key features:

- Built-in LSP support (no plugin configuration)
- Tree-sitter for syntax highlighting and text objects
- Multiple cursors and selections
- Vim-like modal editing with improved ergonomics

### Terminal Multiplexer: Zellij

Zellij manages terminal sessions, panes, and tabs. It's a modern alternative to tmux with better defaults:

```bash
# Start new session
zellij

# Named session for a project
zellij -s myproject

# Attach to existing session
zellij attach myproject

# List sessions
zellij list-sessions
```

Key concepts:

- **Sessions**: Persist your workspace (survives disconnection)
- **Tabs**: Organize by context (code, logs, servers)
- **Panes**: Split views within a tab
- **Floating panes**: Quick temporary terminals

Basic navigation:

- `Ctrl+p` then arrow keys: Switch panes
- `Ctrl+t`: Open a visible prompt, type the tab name, and press `Enter`
- `Ctrl+PageUp` / `Ctrl+PageDown`: Switch tabs
- `Ctrl+p` then `n`: New pane
- `Ctrl+o` then `d`: Detach session

Tab naming helpers:

- `ztab "name"`: Rename the current tab explicitly
- `znewtab`: Open the same visible prompt from the shell

### Version Control

**Git** with **lazygit** for a TUI interface:

```bash
# Interactive git operations
lazygit

# Or the classic CLI
git status
git diff
git add -p
```

### File Management

**yazi** provides fast, keyboard-driven file browsing:

```bash
yazi
```

Navigate with vim keys, preview files, bulk operations—all without leaving the terminal.

### Search Tools

**fzf**: Fuzzy finder for files, commands, history:

```bash
# Find files
fzf

# Search command history
Ctrl+r

# Find and open file
nvim $(fzf)
```

**ripgrep** and **fd**: Fast search for content and files:

```bash
# Search file contents
rg "pattern"

# Find files by name
fd "pattern"
```

### Monitoring

**btop** for system monitoring:

```bash
btop
```

## Thin Client Development

The TUI workflow truly shines when combined with remote development. Instead of running everything locally, connect to a powerful workstation or server and work from any device.

Your laptop becomes a thin client—a window into a persistent development environment running elsewhere. Close the laptop, open it on a different network, and resume exactly where you left off.

This approach is detailed in the [Thin Client Development Guide](tui-developer-workflow-thin-client.md), covering:

- Mosh for persistent SSH connections
- SSH port forwarding for remote services
- Zellij session resumption workflow

## NixOS Integration

All tools can be declared in your NixOS or Home Manager configuration:

```nix
{ pkgs, ... }: {
  home.packages = with pkgs; [
    zellij
    helix
    lazygit
    yazi
    fzf
    ripgrep
    fd
    btop
  ];

  programs.zsh.enable = true;
  programs.fzf.enable = true;
  programs.zellij.enable = true;
}
```

New machine? Apply your config and you're ready to work.

## Getting Started

1. Install the core tools via Nix
2. Learn the basics of Helix (`hx --tutor`)
3. Start using Zellij for session management
4. Gradually adopt additional tools as needed

The investment in learning these tools pays dividends in productivity and flexibility.
