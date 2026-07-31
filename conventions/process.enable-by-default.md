# Convention: Enable by Default (process.enable-by-default)

Keystone treats the entire fleet as a single system. Features are enabled by
default, configuration auto-derives from shared registries (`keystone.hosts`,
`keystone.services`, `keystone.domain`), and every host or agent receives the
full capability set unless explicitly opted out. This minimizes the total lines
of config across both keystone and nixos-config, preventing a sprawl of
per-host `enable = true` flags that must be maintained in lockstep.

## Default-On Principle

1. New keystone module options MUST default to `true` (enabled) unless there is
   a concrete reason to require opt-in (e.g., the feature needs external
   credentials, has a cost, or conflicts with other modules).
2. Options that only make sense when another option is set (e.g., `tasks.enable`
   when `mail` is configured) SHOULD auto-enable via `mkDefault true` when
   their prerequisite is met, rather than requiring a separate `enable = true`
   in nixos-config.
3. When a feature requires per-host credentials (e.g., mail password, API token),
   the feature MAY default to `false` but MUST document in its description what
   prerequisite enables it.
4. Developers MUST NOT add `enable = true` flags in nixos-config for features
   that are already default-on in keystone — redundant flags obscure which
   settings are actual overrides vs boilerplate.

## Fleet as a Single System

5. Module configuration MUST auto-derive from shared registries
   (`keystone.hosts`, `keystone.services`, `keystone.domain`) rather than
   requiring per-host declarations in nixos-config.
6. When a host registry field (e.g., `journalRemote = true`) determines
   behavior for the entire fleet, the module MUST consume that field directly
   — not require each host to also set `keystone.os.journalRemote.upload.enable`.
7. Cross-host concerns (e.g., journal forwarding, binary cache, DNS) SHOULD
   require exactly one declaration in the host registry; all other hosts
   MUST auto-configure from that single source of truth.
8. New modules MUST NOT require mirrored config in both keystone and
   nixos-config — the keystone module should derive everything it can from
   options already available in the evaluation context.

## Agent Environment Parity

9. Agents MUST receive the same terminal environment as human users — no
   cherry-picking individual tools or features. See `os.requirements` rules
   12-15 for the systemd-level enforcement of this principle.
10. When a terminal submodule is enabled for any user on a host, it SHOULD
    be enabled for all agents on that host unless the agent definition
    explicitly opts out.
11. Agent-specific overrides (e.g., different mail credentials) MUST use the
    agent submodule options, not separate module-level flags.

See `process.keystone-principal-parity` for the implementation discipline
(shared provisioning scripts, option symmetry, divergence documentation)
that enforces this parity at the code level.

## Config Reduction Reviews

12. During the `ks.develop` workflow review step, reviewers SHOULD check
    whether the change introduces new per-host config that could instead be
    auto-derived from existing registries.
13. When reviewing PRs, reviewers SHOULD flag `enable = true` lines in
    nixos-config that duplicate a keystone default — these SHOULD be removed.
14. Periodic config audits SHOULD scan nixos-config for options that merely
    restate keystone defaults and remove them.

## Exceptions

15. Features with external costs (e.g., cloud API calls, paid services) MAY
    default to `false`.
16. Features that conflict with each other (e.g., two mutually exclusive
    desktop compositors) MUST default to `false` with a clear selection
    mechanism.
17. Experimental or unstable features MAY default to `false` until they are
    considered production-ready.

## Golden Example

Before this convention — adding cfait (CalDAV tasks) to the fleet required
three separate changes:

```nix
# nixos-config/home-manager/ncrmro/base.nix (consumer config)
keystone.terminal.tasks.enable = true;    # manual opt-in

# nixos-config/hosts/ocean/default.nix (server config)
# nothing needed here, but the pattern invites it

# keystone/modules/terminal/tasks.nix (module definition)
enable = mkOption { default = false; ... };
```

After this convention — cfait auto-enables when its prerequisite (mail) is
configured:

```nix
# keystone/modules/terminal/tasks.nix
enable = mkOption {
  type = types.bool;
  default = mailCfg.enable;  # auto-on when mail is configured
  description = "Enable CalDAV task management TUI (cfait)";
};

# nixos-config — no change needed. The feature activates because
# mail is already configured. Zero config maintenance.
```

Similarly, journal-remote and ZFS backup auto-derive from `keystone.hosts`
(see also `os.zfs-backup` for the ZFS application of this pattern):

```nix
# nixos-config/hosts.nix — single declaration
ocean = { journalRemote = true; ... };

# Every other host auto-forwards. No per-host upload config needed.
# The module reads keystone.hosts and configures itself.
```
