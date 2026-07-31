# Desktop Module — Editing Guide (`modules/desktop/`)

This guide covers conventions for editing the desktop module. The module is split into
two layers: NixOS system-level (`nixos.nix`) and home-manager level (`home/`).

## NixOS Level (`nixos.nix`)

```nix
keystone.desktop = {
  enable = true;
  user = "alice";    # Primary desktop user for the Hyprland session
  obs.enable = true; # OBS Studio (default: true, disable per-host if needed)
};
```

**Included at NixOS level**: Hyprland + UWSM, greetd session launch, startup
`hyprlock` authentication, PipeWire audio, Bluetooth, CUPS printing,
NetworkManager, flatpak, Nerd Fonts (JetBrains Mono,
Caskaydia Mono), polkit, OOM protection (Docker/Podman get `OOMScoreAdjust = 1000`),
OBS Studio with PipeWire audio capture (enabled by default, disable per-host via
`obs.enable = false` for hosts without GPU encoding support).

**Security invariant**: when `keystone.desktop.enable = true`, the session MUST
fail closed if startup `hyprlock` cannot start. Missing theme or wallpaper state
MUST NOT expose an unlocked desktop.

OS-level changes require a full `nixos-rebuild switch` — not just `ks build`.

## Validation safety

Desktop validation MUST NOT probe real Wayland binaries against the developer's
active session. Tools such as `hyprlock`, `hyprpaper`, `hypridle`, and
`hyprctl` will attach to the current compositor when environment variables such
as `WAYLAND_DISPLAY`, `HYPRLAND_INSTANCE_SIGNATURE`, and `XDG_RUNTIME_DIR` are
in scope.

When validating generated desktop config:

1. Prefer rendered-config assertions first.
2. Run real-binary smoke tests only in an isolated environment that does not
   inherit the live session variables above.
3. Prefer Nix check derivations or other non-interactive test wrappers over
   ad hoc terminal probes on the developer machine.
4. If a real session is required, use a dedicated test compositor or test host
   — never the operator's current unlocked desktop session.

CRITICAL: live-session validation can lock the operator screen, kill the active
wallpaper process, or otherwise mutate the running desktop while debugging.

## Home-Manager Level (`home/`)

Enabled via `keystone.desktop.enable = true` in home-manager config. Components:

| Component  | File                        | Key Detail                                            |
| ---------- | --------------------------- | ----------------------------------------------------- |
| Ghostty    | `components/ghostty.nix`    | JetBrains Mono Nerd Font, 12pt, 0.95 opacity          |
| Waybar     | `components/waybar.nix`     | Named workspaces, clock, CPU, battery, BT, audio      |
| Walker     | `components/walker.nix`     | Apps, files, emoji, calculator, web search, clipboard |
| Mako       | `components/mako.nix`       | Notification daemon (themed)                          |
| Clipboard  | `components/clipboard.nix`  | clipse (100 items) + wl-clipboard + wl-clip-persist   |
| Screenshot | `components/screenshot.nix` | grim + slurp + satty annotation                       |
| SwayOSD    | `components/swayosd.nix`    | Volume/brightness OSD                                 |
| Btop       | `components/btop.nix`       | System monitor (themed)                               |
| Slidev     | `home/default.nix`          | Markdown presentation tool (`pkgs.keystone.slidev`)   |

## Key Hyprland Options

```nix
keystone.desktop.hyprland = {
  modifierKey = "SUPER";       # Primary modifier key
  capslockAsControl = true;    # Remap Caps Lock → Control
  scale = 2;                   # HiDPI scale factor (1 or 2)
};
keystone.desktop.monitors = {
  primaryDisplay = "eDP-1";
  autoMirror = true;           # Auto-mirror new displays
};
keystone.desktop.theme.name = "tokyo-night";  # 15 themes
```

**CRITICAL keyboard note**: `altwin:swap_alt_win` is **always** enabled. This means
the physical Alt key (thumb-accessible) triggers `$mod` bindings. Set
`modifierKey = "SUPER"` to use physical Alt as the modifier.

## Theming (`home/theming/`)

15 themes with runtime switching via `keystone-theme-switch <name>`. Each theme
provides: Hyprland colors, hyprlock, waybar CSS, mako, walker CSS, ghostty, helix,
zellij, btop, swayosd, and wallpapers.

When adding a new theme:

1. Create `home/theming/<name>/` with the required component files
2. Register in `home/theming/default.nix`
3. Runtime switcher picks it up automatically

Available themes: tokyo-night (default), kanagawa, catppuccin, catppuccin-latte,
ethereal, everforest, flexoki-light, gruvbox, hackerman, matte-black, nord,
osaka-jade, ristretto, rose-pine, royal-green.

## Key Hyprland Bindings (`home/hyprland/bindings.nix`)

`$mod` = configured `modifierKey` (physical Alt when `altwin:swap_alt_win` active).

| Binding       | Action           |
| ------------- | ---------------- |
| `$mod+Return` | Terminal         |
| `$mod+Space`  | Walker launcher  |
| `$mod+W`      | Close window     |
| `$mod+F`      | Fullscreen       |
| `$mod+D`      | Context switcher |
| `$mod+1-0`    | Workspaces 1-10  |
| `Print`       | Screenshot       |
