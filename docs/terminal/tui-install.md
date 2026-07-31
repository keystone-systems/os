---
title: Installing ks
description: How to install the Keystone Terminal UI environment
---

# Installing ks

ks is a curated terminal environment powered by Nix. It provides a consistent, high-performance developer experience across macOS and Linux.

**What's included:** [Zsh](https://www.zsh.org/), [Helix](https://helix-editor.com/) editor, [Zellij](https://zellij.dev/) terminal multiplexer, [Lazygit](https://github.com/jesseduffield/lazygit), [Direnv](https://direnv.net/), [Zoxide](https://github.com/ajeetdsouza/zoxide), Ripgrep, Eza, and language servers for Bash, Nix, TypeScript, YAML, and more.

## Keystone OS Users

If you are using **Keystone OS**, you don't need to do anything. ks comes pre-installed and configured out of the box.

## Non-Keystone OS Users (macOS / Linux)

For users on macOS or other Linux distributions (Ubuntu, Fedora, Arch, etc.), you can install ks by following these steps.

### 1. Install Nix

First, you need the Nix package manager installed with flakes enabled.

- **macOS:** Use the [Determinate Systems installer](https://github.com/DeterminateSystems/nix-installer#installation) — it enables flakes by default and handles macOS quirks
- **Linux:** Use the [official Nix installer](https://nixos.org/download/#nix-install-linux) or the Determinate Systems installer (recommended for flake support)

If you already have Nix but flakes are not enabled, add this to `/etc/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

### 2. Install ks

Once Nix is installed and flakes are enabled, you can run ks directly or install it into your profile.

#### Option A: Try it out (Ephemeral Shell)

To launch a shell with all Keystone tools available without permanently installing them:

```bash
nix shell github:ncrmro/keystone#tui
```

This will drop you into a shell with `helix`, `zellij`, `lazygit`, and other tools available.

#### Option B: Install with Home Manager (Recommended)

For a permanent installation that manages your configuration files (dotfiles), we recommend using [Home Manager](https://nix-community.github.io/home-manager/).

1.  **Initialize a simplified flake:**

    create a `flake.nix` file in your preferred config directory (e.g., `~/.config/home-manager/flake.nix`):

    ```nix
    {
      description = "My ks Configuration";

      inputs = {
        nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
        keystone.url = "github:ncrmro/keystone";
        home-manager.url = "github:nix-community/home-manager";
        home-manager.inputs.nixpkgs.follows = "nixpkgs";
      };

      outputs = { self, nixpkgs, keystone, home-manager, ... }: {
        homeConfigurations."YOUR_USERNAME" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux; # Or aarch64-darwin for Apple Silicon
          modules = [
            # Import ks module
            keystone.homeManagerModules.tui

            {
              home.username = "YOUR_USERNAME";
              home.homeDirectory = "/home/YOUR_USERNAME"; # Or /Users/YOUR_USERNAME on macOS
              home.stateVersion = "23.11";
            }
          ];
        };
      };
    }
    ```

2.  **Apply the configuration:**

    ```bash
    nix run home-manager/master -- switch --flake .#YOUR_USERNAME
    ```

## Next Steps

Now that you have the tools installed, learn how to use them effectively in our Developer Workflow guide.

- [**Developer Workflow Guide**](tui-developer-workflow.md) - Learn how to use Zellij, Helix, and other tools together.
