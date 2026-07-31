# Convention: Keystone Development Mode (process.keystone-development-mode)

Keystone development mode (`keystone.development`) enables rapid iteration by
using local repository checkouts instead of immutable Nix store copies. When
enabled, modules derive local paths from the `keystone.repos` registry at
`~/repos/{owner}/{repo}/`.

## Top-Level Toggle

1. `keystone.development` is a NixOS boolean that defaults to `false`. This is
   an exception to the default-on principle (see `process.enable-by-default`
   rule 17) because development mode requires local repo checkouts to function
   — enabling it without repos present would break builds.
2. Setting `keystone.development = true` MUST NOT, by itself, change any
   behavior unless `keystone.repos` declares at least one repository with a
   matching `flakeInput`.

## Repository Registry

3. `keystone.repos` is an attrset keyed by `owner/repo` (e.g.,
   `"ncrmro/keystone"`) that declares managed repositories.
4. Each entry MUST specify a `url` (git remote) and MAY specify `flakeInput`
   (the corresponding flake input name) and `branch` (default: `"main"`).
5. Repositories are expected at `~/repos/{owner}/{repo}/` — this
   path is computed, never hardcoded per-user.

## Path Resolution

6. When `keystone.development = true`, modules that consume Nix store copies
   (conventions, deepwork jobs, claude-code commands, repo-backed shell
   entrypoints) MUST resolve to the local checkout path derived from
   `keystone.repos` entries whose `flakeInput` matches the relevant flake
   input.
7. When `keystone.development = false` (default), all paths MUST resolve to
   immutable Nix store copies — behavior is identical to a locked build.

## Terminal Module

8. `keystone.terminal.development` is bridged from the NixOS-level
   `keystone.development` option by `users.nix`.
9. `keystone.terminal.repos` is bridged from `keystone.repos` by `users.nix`.
   Terminal modules look up local checkout paths by `flakeInput` name.
10. DeepWork library jobs (`DEEPWORK_ADDITIONAL_JOBS_FOLDERS`) swap to local
    checkouts when `keystone.terminal.development` is true and the
    corresponding repo is registered.
11. When `keystone.development = true`, AI instruction files (`AGENTS.md`,
    `CLAUDE.md`, `GEMINI.md`), curated AI command files, and managed Codex
    skills MUST be refreshable from the live keystone checkout without a full
    rebuild.
12. `ks sync-agent-assets` is the supported no-sudo refresh path for these
    generated development-mode assets. `ks switch` and `ks update --dev` MUST
    also run the same refresh path during activation.
13. Development-mode refreshes MUST write generated outputs into user-home tool
    paths, not into repo checkouts under `keystone.repos`.

## Desktop Module

14. Desktop and terminal user-facing shell scripts backed by checked-in `.sh`
    files MUST be linked into the user's PATH from the local checkout when
    `keystone.development = true`. After activation, edits to the repo script
    MUST take effect without rebuild.
15. When a linked repo-backed script depends on adjacent non-executable assets
    such as CSS, templates, or static config files, the script MUST resolve
    those assets from the live checkout at runtime. Build-time substituted
    paths alone are insufficient because the linked dev-mode script bypasses
    Nix substitution.
16. Desktop theme and configuration files MAY use local checkouts for rapid
    iteration when `keystone.development = true`.

## Server Module

17. (Future) Server modules MAY use local checkouts for service configs when
    `keystone.development = true`.

For the Grafana-specific application of these development-mode rules, including
checked-in dashboard JSON and rapid apply flows, see
`process.grafana-dashboard-development`.

## Safety

18. `keystone.development` MUST only affect path resolution — it MUST NOT
    modify, commit, or push any repository (per REQ-018.8).
19. Modules MUST NOT write to paths derived from `keystone.repos` entries.
    Local checkouts are read-only from the module system's perspective.

## Agent Parity

20. Agents MUST inherit development mode from the global
    `keystone.development` setting via their home-manager config bridge (see
    `process.enable-by-default` rules 9-11).

## Diagnostics

21. `ks doctor` MUST report development mode status: whether it is enabled,
    which repos are declared, and whether their local checkouts exist (per
    REQ-023).
