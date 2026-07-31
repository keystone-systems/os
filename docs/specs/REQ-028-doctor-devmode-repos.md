# REQ-028: ks doctor Dev Mode Repo Health Checks

Extend `ks doctor` to verify that all managed repositories under
`~/.keystone/repos/` are in a clean, deployable state when dev mode is
enabled. This prevents deploying from stale checkouts, detached HEADs,
or dirty working trees — problems that cause silent build failures or
deploy mismatches.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## User Story

As a Keystone operator using dev mode, I want `ks doctor` to verify that my
local repos (nixos-config, keystone, agenix-secrets) are all on their default
branch, pulled to latest, clean, and pushed, so that I can trust that
`ks update --lock` will deploy exactly what I expect.

## Architecture

```
ks doctor
    │
    ▼
gather_system_state()
    │
    ├── gather_fleet_health()      (existing)
    ├── gather_agent_health()      (existing)
    ├── gather_agent_tasks()       (existing)
    │
    └── gather_repo_health()       ◄── NEW
            │
            ├── ~/.keystone/repos/ncrmro/nixos-config/
            │     ├── on branch main?
            │     ├── clean working tree?
            │     ├── pulled to latest? (not behind remote)
            │     └── pushed? (not ahead of remote)
            │
            ├── ~/.keystone/repos/ncrmro/keystone/
            │     └── (same 4 checks)
            │
            ├── ~/.keystone/repos/ncrmro/agenix-secrets/
            │     └── (same 4 checks)
            │
            └── submodule checks
                  └── nixos-config/.submodules/keystone
                        ├── on a branch? (not detached HEAD)
                        └── matches origin/main?
```

## Affected Modules

- `packages/ks/ks.sh` — Add `gather_repo_health` function, integrate into `gather_system_state`
- `docs/specs/REQ-028-doctor-devmode-repos.md` — This spec

## Requirements

### Repo Discovery

**REQ-028.1** When dev mode is active (`keystonePath` is set or
`~/.keystone/repos/` exists), `ks doctor` MUST scan `~/.keystone/repos/`
for all git repositories (any directory containing `.git`).

**REQ-028.2** The scan MUST enumerate repos by walking
`~/.keystone/repos/OWNER/REPO/` paths (two levels deep), not recursively
searching the entire tree.

**REQ-028.3** Each discovered repo MUST be checked for the four health
conditions defined in the Repo Health Checks section.

### Repo Health Checks

**REQ-028.4** For each repo, `ks doctor` MUST check whether it is on its
default branch (`main` or `master`). A detached HEAD MUST be reported as
an error.

**REQ-028.5** For each repo, `ks doctor` MUST check whether the working
tree is clean (no uncommitted changes, no untracked files in tracked
directories). Dirty state MUST be reported as a warning.

**REQ-028.6** For each repo, `ks doctor` MUST run `git fetch` (or use
cached fetch results) and check whether the local branch is behind the
remote. Being behind MUST be reported as a warning with the number of
commits behind.

**REQ-028.7** For each repo, `ks doctor` MUST check whether the local
branch is ahead of the remote (unpushed commits). Being ahead MUST be
reported as a warning with the number of commits ahead.

### Submodule Checks

**REQ-028.8** If nixos-config contains a `.submodules/keystone` directory,
`ks doctor` MUST verify that the submodule is on a branch (not detached
HEAD). This implements the fix for GitHub issue #179.

**REQ-028.9** The submodule branch SHOULD match the keystone repo's default
branch. A mismatch SHOULD be reported as a warning.

### Output Format

**REQ-028.10** Repo health results MUST be included in the system state
gathered by `gather_system_state`, formatted as a table:

```
=== Repository Health ===
REPO                              BRANCH    CLEAN   BEHIND   AHEAD
nixos-config                      main      yes     0        0       OK
keystone                          main      yes     0        0       OK
agenix-secrets                    main      no      0        2       WARN: dirty, unpushed
nixos-config/.submodules/keystone main      yes     0        0       OK
```

**REQ-028.11** The status column MUST use: `OK` (all checks pass),
`WARN` (non-blocking issues), or `ERROR` (detached HEAD or other blocking
condition).

### Integration

**REQ-028.12** The repo health check MUST be implemented as a new function
`gather_repo_health` in `ks.sh`, called from `gather_system_state`.

**REQ-028.13** The function MUST be fast — total execution SHOULD complete
in under 5 seconds for up to 10 repos. Use `git fetch --all` once per repo
rather than per-branch fetches.

**REQ-028.14** When not in dev mode (no `~/.keystone/repos/` directory),
the repo health section SHOULD be omitted entirely rather than showing
an empty table.

### Git Identity and Signing

**REQ-028.17** `ks doctor` MUST verify that `ssh-add -l` returns at least
one loaded key. A missing key MUST be reported as an error (commit signing
will fail silently).

**REQ-028.18** `ks doctor` MUST verify that `git config --global user.signingkey`
is set and that `git config --global gpg.format` is `ssh`. Misconfiguration
MUST be reported as an error.

**REQ-028.19** For each configured git service (GitHub via `gh auth status`,
Forgejo via `tea login list` or session cookie presence), `ks doctor` MUST
verify authentication is active. Failed auth MUST be reported as a warning.

### PIM Tool Health

**REQ-028.20** When `keystone.terminal.mail` is enabled, `ks doctor` MUST
run `himalaya account list` (or equivalent) and verify the configured account
is reachable. A connection failure MUST be reported as a warning.

**REQ-028.21** When `keystone.terminal.calendar` is enabled, `ks doctor`
MUST run `calendula calendar list` (or equivalent) and verify the CalDAV
endpoint responds. A connection failure MUST be reported as a warning.

**REQ-028.22** When `keystone.terminal.tasks` is enabled, `ks doctor` MUST
verify that cfait can reach the CalDAV endpoint (e.g., by running `cfait`
in a mode that tests connectivity, or by performing a direct HTTP PROPFIND
against the configured URL). A connection failure MUST be reported as a
warning.

**REQ-028.23** PIM tool health results MUST be included in the system state
as a table:

```
=== PIM Tool Health ===
TOOL        STATUS   DETAILS
himalaya    OK       1 account, INBOX reachable
calendula   OK       CalDAV endpoint responds
cfait       WARN     Connection refused (is Stalwart running?)
```

### Relationship to Existing Checks

**REQ-028.15** The existing dev mode detection in `build_agent_prompt`
SHOULD be updated to use `gather_repo_health` output
instead of duplicating the keystone-only check.

**REQ-028.16** This spec extends REQ-018.9 ("ks doctor MUST report dev
mode status for each managed repo") with concrete health checks beyond
just reporting the path and branch.

## Edge Cases

- **No ~/.keystone/repos/ directory**: Skip repo health section entirely.
  This is the normal state for locked-mode deployments.
- **Repo exists but remote is unreachable**: Report fetch failure as a
  warning, still check branch and clean status locally.
- **Repo has multiple remotes**: Use `origin` as the canonical remote.
- **Submodule missing**: If `.submodules/keystone` doesn't exist, skip
  the submodule check (not all setups use submodules).
- **Empty repo**: Skip repos with no commits.

## References

- GitHub issue #179 — fix ks commands to verify submodules on branch
- REQ-018 — Repo Management (defines `~/.keystone/repos/` layout)
- `packages/ks/ks.sh` — existing `gather_system_state` and dev mode detection
- `process.enable-by-default` — fleet health should auto-check without per-repo config
