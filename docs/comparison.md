# Keystone Comparison

How Keystone compares to other operating systems, and how `keystone.terminal` works
across platforms.

## OS Comparison

| Feature              | Keystone (NixOS)                                                                            | macOS                        | Windows                     | Ubuntu                  | Omarchy (Arch)            |
| -------------------- | ------------------------------------------------------------------------------------------- | ---------------------------- | --------------------------- | ----------------------- | ------------------------- |
| Full disk encryption | ZFS native + TPM2 auto-unlock                                                               | FileVault (APFS)             | BitLocker (TPM)             | LUKS (manual)           | LUKS (manual)             |
| Declarative config   | Entire system via Nix flakes                                                                | Partial (defaults, profiles) | No                          | No                      | No                        |
| Reproducible builds  | Yes — pinned inputs, binary cache                                                           | No                           | No                          | No                      | No                        |
| Self-hosted services | One-toggle enable with auto TLS/DNS                                                         | Manual or Docker             | Manual or Docker            | Manual or Docker        | Manual or Docker          |
| Desktop environment  | Hyprland (tiling, 15 themes)                                                                | Aqua (proprietary)           | Explorer (proprietary)      | GNOME                   | Hyprland                  |
| Terminal environment | Zsh + Helix + Zellij + AI tools                                                             | Zsh + user choice            | PowerShell / WSL            | Bash + user choice      | Zsh + user choice         |
| AI agents            | Sandboxed OS users with own UID, SSH keys, email, desktop ([compare](agents/comparison.md)) | Third-party only             | Third-party only            | Third-party only        | Third-party only          |
| Rollbacks            | Instant (NixOS generations + ZFS snapshots)                                                 | Time Machine (slow)          | System Restore (unreliable) | Snapper (if configured) | Timeshift (if configured) |
| Secure Boot          | Custom key enrollment via lanzaboote                                                        | Apple Secure Boot            | Microsoft keys              | shim-signed             | No                        |
| Multi-user           | Declarative user accounts + agents                                                          | Yes                          | Yes                         | Yes                     | Yes                       |

## keystone.terminal Cross-Platform

The `keystone.terminal` module is a Home Manager module — it configures your shell,
editor, multiplexer, Git, AI tools, and PIM stack declaratively. Because Home Manager
runs in userspace, it works anywhere Nix runs.

### NixOS (native)

Full integration. The terminal module is applied via `home-manager.nixosModules.home-manager`
inside your NixOS configuration. Everything works out of the box including hardware key
support, system-level agent integration, and service coordination.

```nix
# In your NixOS flake
home-manager.users.you = {
  imports = [ keystone.homeModules.terminal ];
  keystone.terminal.enable = true;
};
```

### Ubuntu / Other Linux

Install Nix as a package manager (multi-user mode), then use standalone Home Manager.
You get the full terminal experience — shell, editor, tools — without replacing your OS.

```bash
# Install Nix
sh <(curl -L https://nixos.org/nix/install) --daemon

# Install Home Manager standalone
nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
nix-channel --update
nix-shell '<home-manager>' -A install
```

Then import `keystone.homeModules.terminal` in your `~/.config/home-manager/flake.nix`.

### macOS

Use nix-darwin for system-level Nix integration, plus Home Manager for user config.
Most terminal tools work identically. Desktop modules are not available on macOS.

```bash
# Install Nix
sh <(curl -L https://nixos.org/nix/install)

# Install nix-darwin + Home Manager
# Then import keystone.homeModules.terminal in your darwin flake
```

### Windows (WSL2)

Run a WSL2 Linux distribution, install Nix inside it, then use Home Manager standalone.
The terminal module works fully within the WSL2 environment.

```powershell
# Enable WSL2 and install a distro (e.g., Ubuntu)
wsl --install

# Inside WSL2, install Nix and Home Manager as described in the Linux section
```

### Omarchy (Arch-based)

Omarchy already uses Hyprland, so the desktop experience is similar. Install Nix as a
package manager on Arch, then use standalone Home Manager to get the keystone terminal
stack alongside Omarchy's existing config.

```bash
# Install Nix on Arch
sh <(curl -L https://nixos.org/nix/install) --daemon

# Use standalone Home Manager with keystone.homeModules.terminal
```

## What You Get

Regardless of platform, `keystone.terminal` provides:

- **Shell**: Zsh with custom prompt, completions, and aliases
- **Editor**: Helix with LSP configurations
- **Multiplexer**: Zellij with custom layouts
- **Git**: SSH signing, custom aliases, forge integrations
- **AI tools**: Claude Code, Gemini CLI, and other coding agents
- **PIM**: Email (Himalaya), calendar, contacts, tasks — all terminal-based
