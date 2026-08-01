---
title: Waybar Configuration
description: Waybar desktop bar configuration with dynamic theming and custom integrations
---

> **Moved:** Waybar moved to the ks.systems/desktop flake (keystone's
> `desktop` input). The systemd user unit lives in that repo's
> `modules/home/hyprland.nix`; the config/style files are template content
> (`templates/waybar/`) users seed into their own dotfiles and stow — nix no
> longer generates them. The layout/styling notes below describe that
> template content.

In Keystone, Waybar is configured as a core desktop component with dynamic theming and custom integrations.

### Configuration Location

- **Active Config**: user dotfiles (`~/.config/waybar/`, seeded from
  ks.systems/desktop `templates/waybar/`)
- **Enablement**: The waybar user service starts automatically when
  `keystone.desktop.enable` is set to `true` (environment `hyprland`).

### Layout Structure

The bar is positioned at the top with a height of 26px.

- **Left Module**:
  - `custom/keystone`: A launcher icon (right-click launches Ghostty).
  - `hyprland/workspaces`: Persistent workspaces with icon labels.
- **Center Module**:
  - `clock`: Displays time/date.
  - `custom/screenrecording-indicator`: A specialized module that:
    - Checks if `gpu-screen-recorder` is running.
    - Listens for **signal 8** (`RTMIN+8`) to update instantly.
    - Clicking it triggers `keystone-screenrecord` to stop recording.
- **Right Module**:
  - `group/tray-expander`: A collapsible system tray.
  - `bluetooth`, `network`, `pulseaudio`, `cpu`, `battery`: Standard system monitors.

### Dynamic Styling

Waybar's styling is designed to switch themes on the fly without rebuilding the system.

1.  **CSS Import**: The Stow-owned configuration imports `${config.xdg.configHome}/themes/current/waybar.css`.
2.  **Theme Switching**: The `keystone-theme-switch` script updates the symlink at `.../themes/current`, pointing it to the selected Stow-owned theme directory (e.g., `tokyo-night`, `catppuccin`), and then reloads Waybar.
3.  **Base Styles**: The `style` block in the Nix config sets base properties (fonts, margins) and uses variables like `@background` and `@foreground` which are populated by the imported theme CSS.
