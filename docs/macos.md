# macOS

Keystone runs on macOS through `mkDarwinInventoryHost` in `lib/templates.nix`.
Today that path is **standalone home-manager only** — no nix-darwin, no
system-level config. This page describes what that means, what changes when
nix-darwin is adopted, and the trade-offs involved.

Tracking issue: [#554 — Adopt nix-darwin in mkDarwinInventoryHost](https://github.com/ncrmro/keystone/issues/554)
(milestone v1.1).

## What you get today

`mkDarwinInventoryHost` produces a `homeConfigurations.<user>@<host>` entry
that builds a standalone home-manager closure. Activation is:

```
nix run home-manager/master -- switch --flake ~/repos/ncrmro/nixos-config#<user>@<host>
```

What this covers:

- Everything under `keystone.terminal.*` — shell, editor, zellij, AI
  extensions, conventions install, agent-assets, mcp configs, secrets-CLI
  wrappers.
- Per-user files in `$HOME` (config files, scripts, layouts, agent assets).
- Per-user `~/.config/nix/nix.conf` — but only via home-manager `home.file`
  writes, not via `nix.settings`. The existing Darwin block in
  `modules/terminal/shell.nix` writes flake/nix-command experimental features
  this way.

What it does **not** cover:

- Anything under `keystone.os.*` — those modules live in `modules/os/` and
  assume `systemd.services`, `nix.settings`, `users.users`, `age.secrets`,
  and friends. None of those option namespaces exist in standalone
  home-manager.
- launchd daemons / user agents.
- `system.defaults` (Finder, Dock, keyboard, screencapture, screensaver
  preferences as Nix).
- Touch ID for sudo, sshd activation, system-level user/group management,
  dscl, declarative Homebrew.
- agenix-darwin — no system-level secret decryption. Anything that would
  read `/run/agenix/<name>` on a NixOS host has to be re-engineered on
  Darwin to read from `gh auth token`, the macOS Keychain, or a manually
  managed file path.

This asymmetry is why `keystone.terminal.githubTokenNix` exists with
`source = "gh-auth"` as its default: there is no agenix on the macbook to
materialize the file, so the home-manager activation script shells out to
`gh` instead.

## What nix-darwin would give keystone

A new `darwinConfigurations.<host>` flake output produced by calling
`nix-darwin.lib.darwinSystem` from `mkDarwinInventoryHost`, alongside (or
in place of) the existing `homeConfigurations` entry. Activation becomes:

```
darwin-rebuild switch --flake ~/repos/ncrmro/nixos-config#<host>
```

Symmetric system surface with NixOS:

- **`launchd.daemons` and `launchd.user.agents`** — keystone os modules
  that today write `systemd.services.<name>` (e.g. the
  `nix-github-access-token.service` oneshot from
  `keystone.os.githubTokenNix`) gain a Darwin code path emitting a launchd
  daemon with `RunAtLoad = true` and an equivalent script body.
- **`agenix.darwinModules.default`** — declares `age.secrets.<name>` at the
  system level, identifies the macbook by an SSH host key, and decrypts to
  `/etc/agenix/<name>` (default) or `/run/agenix/<name>` (with a tmpfs
  option). Per-host recipient sets work the same as Linux.
- **System `nix.settings`** — managed `/etc/nix/nix.conf` instead of just
  per-user. Closes the per-user/per-daemon split; the nix-daemon picks up
  `access-tokens` from system config.
- **`system.defaults`** — Finder/Dock/keyboard/screencapture/screensaver
  declared in Nix rather than via `defaults write com.apple.…` rituals.
- **Touch ID for sudo** (`security.pam.enableSudoTouchIdAuth = true`).
  Slots into the future `keystone.security.privilegedApproval` per
  `process.privileged-approval`.
- **Declarative Homebrew** (`homebrew.brews/casks/taps`) — a Brewfile in
  Nix for closed-source casks nixpkgs cannot reach.
- **`environment.systemPackages`** — system-wide packages instead of
  per-user only.
- **sshd activation**, hostname, `users.users.<name>`, groups, dscl —
  bootstrapped declaratively instead of manually.

Concrete keystone-side example, post-adoption:

```nix
keystone.os.githubTokenNix.enable = true;
```

Would work identically on a NixOS desktop and on the macbook: on Linux it
writes `/etc/nix/access-tokens.conf` via a systemd oneshot; on Darwin it
writes the same file via a launchd daemon. The home-manager
`keystone.terminal.githubTokenNix` workaround stays available for adopters
who don't want nix-darwin.

## Impact

| Cost dimension | Cold cache | Warm cache |
|---|---|---|
| Eval (per Darwin host) | +5–10s for module-system pass | +1–3s |
| Build (closure delta) | +500MB–1.5GB store paths (system-toplevel + nix-darwin modules + agenix-darwin) | unchanged on home-manager-only edits |
| Activation (`darwin-rebuild switch`) | +5–15s wall-clock vs home-manager switch | same |
| Disk steady-state | +500MB–2GB (retained generations) | — |

The important property: **most everyday edits touch home-manager**
(terminal config, AI extensions, conventions, mcp configs). Those rebuilds
do **not** re-derive the system-toplevel — they evaluate and activate at
home-manager speed. The system layer only re-evaluates when system-level
modules change.

## Operational cost

- **`sudo` required.** `darwin-rebuild switch` is privileged; today
  `home-manager switch` runs as user. New approval surface — should be
  routed through `keystone.security.privilegedApproval` once that
  module lands.
- **Recovery is harder than NixOS.** macOS has no easy boot-into-previous-
  generation path from outside the OS. If activation bricks the system
  the only remedies are recovery boot + manual `darwin-rebuild rollback`
  or, worst case, reinstallation. Mitigation: always
  `darwin-rebuild build` before `switch`; `keystone-dev --build` should
  gain a Darwin parallel.
- **Upstream stability.** nix-darwin has its own release cadence and
  occasional breaking changes around launchd / `system.defaults`. Less
  stable than nixpkgs proper.
- **Migration effort in keystone.** `mkDarwinInventoryHost` needs to
  branch on whether the host opts into nix-darwin and call
  `nix-darwin.lib.darwinSystem` accordingly. Per-host configs grow a
  small `darwin.nix` layer (system-side options). Existing standalone
  home-manager hosts can stay as-is until they need a system-level
  feature.

## When to adopt

The breakpoint comes the moment you want **any** of:

- agenix-darwin (root-readable secrets on the macbook)
- Declarative `system.defaults`
- Touch ID for sudo
- Declarative Homebrew
- Symmetric `keystone.os.*` between NixOS and Darwin (e.g. running
  `keystone.os.githubTokenNix` natively on the macbook instead of the
  home-manager workaround)
- System-level sshd, hostname, users

If only one of those is wanted and the home-manager workaround is
acceptable, defer. If two or more are likely within a few months,
adopting nix-darwin sooner is cheaper than paying the migration cost
piecemeal later.

## Migration outline

Tracked in detail under issue #554. High-level steps:

1. Add `inputs.nix-darwin` to `flake.nix`.
2. Branch `mkDarwinInventoryHost` to call `nix-darwin.lib.darwinSystem`
   and emit `darwinConfigurations.<host>` for hosts that opt in. Keep the
   standalone `homeConfigurations` path for hosts that don't.
3. Wire `agenix.darwinModules.default` and pick a system identity (e.g.
   the macbook's `/etc/ssh/ssh_host_ed25519_key.pub`, generated once via
   `launchctl start com.openssh.sshd-keygen-wrapper`; or a manually
   managed key).
4. Add a Darwin code path to `keystone.os.githubTokenNix` (launchd daemon
   parallel to the systemd oneshot). Use this module as the smoke test
   for system-level convergence.
5. Migrate one macbook host end-to-end in `ncrmro/nixos-config` as the
   canonical reference adopter.
6. Document the new dual mode in this file and `process.keystone-development`.

## Today's workaround for adopters

Until nix-darwin lands, macbooks use the home-manager-only path. To get
authenticated GitHub flake fetches:

```nix
# in the macbook's home-manager profile
keystone.terminal.githubTokenNix = {
  enable = true;
  # source defaults to "gh-auth" — reads from `gh auth token` at
  # activation time, writes ~/.config/nix/access-tokens.conf, and adds
  # !include to ~/.config/nix/nix.conf.
};
```

This is the documented bridge — symmetric in *effect* with the NixOS
`keystone.os.githubTokenNix` (authenticated nix-daemon GitHub access),
asymmetric in *implementation* (per-user file vs system file; gh CLI vs
agenix).

See `conventions/tool.nix.md` "Darwin parity (per-user nix.conf)" for the
authoritative convention.
