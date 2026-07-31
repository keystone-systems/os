# Convention: Hyprland autostart (os.hyprland-autostart)

The Hyprland `exec-once` list is a security-critical boot chain. Its first
user-visible command MUST be the configured startup lock command
(`keystone.desktop.startupLockCommand`, default `keystone-startup-lock`),
which launches the lock screen and kills the session if the lock surface
fails to appear. Dropping or reordering this entry exposes an unlocked
desktop after reboot — a fail-open security defect.

This convention exists because a priority collision between `mkDefault`
(priority 1000) and `mkAfter` (priority 100) silently replaced the entire
base exec-once list, dropping the lock screen, D-Bus setup, polkit agent,
and clipboard manager.

## Boot chain context

```
greetd (auto-login) → UWSM → Hyprland → exec-once → keystone-startup-lock → hyprlock
```

If `keystone-startup-lock` is missing from `exec-once`, or if hyprlock fails
to present a lock surface, the script terminates the session rather than
exposing an unlocked desktop. This is a fail-closed design. See
`modules/desktop/home/scripts/keystone-startup-lock.sh`.

## Base list ownership

1. The base `exec-once` list MUST be defined exclusively in
   `modules/desktop/home/hyprland/autostart.nix`.
2. The base list MUST use bare assignment (normal priority 100) — MUST NOT
   use `mkDefault`. `mkDefault` (priority 1000) is weaker than `mkAfter`
   (priority 100), causing `mkAfter` entries to replace rather than append.
3. The base list MUST contain `keystone-startup-lock`, appearing after D-Bus
   environment setup and before all other user-visible entries.
4. A build-time assertion MUST verify `keystone-startup-lock` appears in the
   final resolved `exec-once` list.

## Adding commands from other modules

5. Modules that add entries to `exec-once` MUST use `mkAfter [ ... ]` so
   their commands append after the base list.
6. Modules MUST NOT use bare assignment (`exec-once = [ ... ]`) — bare
   assignment at normal priority collides with the base list and produces
   undefined merge order.
7. Modules MUST NOT use `mkDefault` on `exec-once` — it is silently ignored
   at best, or replaces the base list if the base is accidentally weakened.
8. Modules MUST NOT use `mkOverride`, `mkForce`, or any priority stronger
   than 100 on `exec-once` — these override the base list and drop the
   startup lock.
9. Each module's `mkAfter` addition SHOULD be guarded by `mkIf` on the
   relevant feature flag so disabled features do not leave dead entries.

## Consumer flake additions

10. Consumer flakes (e.g., `nixos-config`) that need additional autostart
    commands MUST use `wayland.windowManager.hyprland.extraConfig`, not
    `settings.exec-once`.
11. `extraConfig` is string-based and appended after all settings — it cannot
    displace the base exec-once list.

## Customizing the lock command

12. Consumer flakes MAY override `keystone.desktop.startupLockCommand` to use
    a different lock binary. The assertion checks for whatever command is
    configured — not a hardcoded string.
13. Any replacement command MUST implement fail-closed semantics: present a
    lock surface or terminate the session.

## Golden example

Module adding audio defaults at session start (correct):

```nix
# modules/desktop/home/scripts/default.nix
wayland.windowManager.hyprland.settings.exec-once =
  mkIf (cfg.audio.defaults.sink != null)
    (mkAfter [
      "env KEYSTONE_AUDIO_DEFAULT_SINK='...' keystone-audio-menu apply-config-defaults"
    ]);
```

Consumer flake adding a workspace dispatch (correct):

```nix
# nixos-config — uses extraConfig, not settings
wayland.windowManager.hyprland.extraConfig = ''
  exec-once = hyprctl dispatch workspace 2
'';
```

Anti-pattern that caused the incident:

```nix
# WRONG — mkDefault on the base list allows mkAfter to replace it
exec-once = mkDefault [
  "keystone-startup-lock"
  # ...
];
```
