# Research: Desktop Session Startup Flow

**Relates to**: REQ-002 (Keystone Desktop)

## Boot Chain

```
Boot → greetd (auto-login) → UWSM → Hyprland → hyprlock (locked desktop)
```

### greetd

Minimal display manager. Bypasses greeter UI, starts UWSM directly:

```nix
services.greetd.settings.default_session = {
  command = "uwsm start -F Hyprland";
  user = cfg.user;
};
```

### UWSM (Universal Wayland Session Manager)

Wraps Hyprland for proper systemd integration: user service lifecycle, environment propagation, XDG autostart, `uwsm app --` for launching apps as systemd scopes. `-F` flag embeds full paths in unit files.

Enabled via `programs.hyprland.withUWSM = true`.

### Hyprland exec-once

Runs after compositor init: D-Bus environment export, `hyprlock` (immediate lock), hyprsunset, polkit agent, clipboard manager.

Lock-on-start ensures the desktop is never visible without authentication, while all components initialize behind the lock screen.

### PAM Configuration

```nix
security.pam.services.greetd.rules.session.systemd.settings = { type = "wayland"; };
```

Enables `loginctl lock-session` for proper session locking.

## Notes

- Hyprland 0.46+ warns when not started via `start-hyprland` wrapper, but UWSM provides equivalent session management. Suppress with `misc.disable_watchdog_warning = true`.
