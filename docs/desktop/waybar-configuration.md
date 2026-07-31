---
title: Waybar Configuration
description: Waybar desktop bar configuration with dynamic theming and custom integrations
---

In Keystone, Waybar is configured as a core desktop component with dynamic theming and custom integrations.

### Configuration Location

- **Active Config**: `.submodules/keystone/modules/desktop/home/components/waybar.nix`
- **Enablement**: It is enabled automatically when `keystone.desktop.enable` is set to `true`.

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

1.  **CSS Import**: The configuration imports `${config.xdg.configHome}/keystone/current/theme/waybar.css`.
2.  **Theme Switching**: The `keystone-theme-switch` script updates the symlink at `.../keystone/current/theme`, pointing it to the new theme directory (e.g., `tokyo-night`, `catppuccin`), and then reloads Waybar.
3.  **Base Styles**: The `style` block in the Nix config sets base properties (fonts, margins) and uses variables like `@background` and `@foreground` which are populated by the imported theme CSS.
