# REQ-018: Keystone Home Directory and Repo Management

Standardize all keystone-managed repo checkouts under `~/repos/`. Replace
the fragile git-submodule pattern with a declarative repo registry
(`keystone.repos`) and a convention-based directory layout. Unify notes
paths for both human users and OS agents under the canonical `notes/` path in
their home directory, while keeping non-keystone project repos under a
separate `$HOME/code/` tree.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Affected Modules

- `packages/ks/ks.sh` — repo discovery, pull, push, override-input, lock
- `modules/notes/default.nix` — user notes path default
- `modules/os/agents/types.nix` — agent notes path default
- New: `modules/repos.nix` — `keystone.repos` option declaration

## Directory Layout

```
~/repos/
├── ncrmro/
│   ├── ks-config/               # flakeInput: (self — the consumer flake)
│   ├── keystone/                # flakeInput: "keystone"
│   └── agenix-secrets/          # flakeInput: "agenix-secrets"
└── Unsupervisedcom/
    └── deepwork/                # flakeInput: "deepwork" (via keystone)

$HOME/code/
└── owner/
    └── repo/                    # non-keystone project repo checkout

~/notes/                         # user's notes repo (synced via cron)

/home/agent-{name}/repos/

/home/agent-{name}/code/
└── owner/
    └── repo/                    # non-keystone project repo checkout

/home/agent-{name}/notes/        # agent's notes repo (synced via cron)
```

## Requirements

### Keystone Home

**REQ-018.1** `~/repos/` MUST be the root directory for all
keystone-managed local repo checkouts. The path MUST be derivable from the
user's home directory, not hardcoded as an absolute path in scripts.

**REQ-018.2** The keystone home convention MUST apply equally to human
users and OS agents. For agent `drago`, the repo root is
`/home/agent-drago/repos/`.

**REQ-018.2a** Home Manager activation MUST ensure the standard workspace
directories exist for both humans and agents:

- `~/repos/`
- the configured notes path (`~/notes` by default)
- `$HOME/code/`
- `$HOME/repos/{owner}/{repo}/worktrees/`

**REQ-018.2b** Home Manager MUST export standardized environment variables so
non-`ks` tooling can discover the shared workspace paths:

- `NOTES_DIR` — the configured notes path
- `CODE_DIR` — `$HOME/code`
- `WORKTREE_DIR` — `$HOME/repos/{owner}/{repo}/worktrees`

### Repo Registry

**REQ-018.3** A new option `keystone.repos` MUST declare managed
repositories as an attrset keyed by `owner/repo` (e.g.,
`"ncrmro/keystone"`) with the following per-repo options:

- `url` (string, REQUIRED) — git remote URL
- `flakeInput` (string, nullable, default `null`) — corresponding input
  name in the consumer's `flake.nix`. When set, `ks` generates
  `--override-input` flags in dev mode and locks this input in lock mode.
- `branch` (string, default `"main"`) — default branch for pull/push

**REQ-018.4** All managed repos MUST be cloned to
`~/repos/{owner}/{repo}/` following the `owner/repo` key
structure.

**REQ-018.4a** `~/repos/{owner}/{repo}/` is reserved for
keystone-managed repositories only, such as `ks-config`, `keystone`,
`agenix-secrets`, `deepwork`, and other repos explicitly declared in
`keystone.repos`.

**REQ-018.5** The registry MUST support repos that are NOT flake inputs
(e.g., repos used only for project context or reference). These repos
are pulled by `ks update --pull` but skipped during flake lock operations.

**REQ-018.5a** Non-keystone project repositories MUST live at
`$HOME/code/{owner}/{repo}/` for human users and `/home/agent-{name}/code/{owner}/{repo}/`
for OS agents.

**REQ-018.6** The following repos MUST be declared for core keystone
operation:

- `ncrmro/ks-config` — the consumer NixOS configuration
- `ncrmro/agenix-secrets` — encrypted secrets (`flakeInput: "agenix-secrets"`)
- `ncrmro/keystone` — keystone modules (`flakeInput: "keystone"`)

### Dev Mode

**REQ-018.7** When dev mode is active (`ks build` without `--lock`,
`ks update --dev`), `ks` MUST use local `~/repos/{owner}/{repo}/`
directories as `--override-input` for every repo that has a non-null
`flakeInput`, without requiring clean or pushed state.

**REQ-018.7a** When dev mode is active, Home Manager-managed user shell
entrypoints and repo-backed static user assets backed by checked-in repo files
MUST resolve from the local checkout path instead of immutable Nix store
copies whenever the target format supports direct linking. The initial link
setup MUST be performed automatically by NixOS or Home Manager activation.

**REQ-018.7b** After activation, editing a linked repo-backed shell script or
linked repo-backed static user asset in development mode MUST NOT require a
rebuild for the change to take effect.

**REQ-018.7d** When a user-facing desktop control generates persistent state
that cannot reasonably live in the keystone source repo, that generated state
MUST be written into the user's personal keystone config repository
(`nixos-config` or equivalent) so it can be reviewed and committed there as the
source of truth.

**REQ-018.7c** `ks update --dev` MUST clone missing managed repos and pull
existing managed repos before building Home Manager profiles so newly
available local overrides (for example `Unsupervisedcom/deepwork` library
jobs) are reflected in the activated environment in the same run.

**REQ-018.8** Dev mode MUST NOT modify, commit, or push any managed repo.

**REQ-018.9** `ks doctor` and `ks agent` MUST report dev mode status for
each managed repo: path, branch, dirty state, commits ahead/behind remote.

### Lock Mode

**REQ-018.10** Lock mode (`ks build --lock`, `ks update` default) MUST,
for each repo with a non-null `flakeInput`:

1. Verify the local checkout is clean and on a branch before attempting lock-mode sync
2. Rebase onto upstream automatically when possible, then push if needed (with fork fallback per REQ-016.9)
3. Run `nix flake update <flakeInput>` to lock the input

**REQ-018.11** Lock mode MUST commit `flake.lock` changes and push
nixos-config only after a successful build (fail-safe ordering).

**REQ-018.12** `ks update --pull` MUST pull ALL managed repos (not just
keystone and agenix-secrets), including repos without a `flakeInput`.

### Notes Under `$HOME`

**REQ-018.13** `keystone.notes.path` (REQ-009.3) MUST default to
`~/notes`.

**REQ-018.14** Agent notes path (`keystone.os.agents.*.notes.path`) MUST
default to `/home/agent-{name}/notes`.

**REQ-018.15** The repo-sync cron job and timer (REQ-009) MUST continue
to function unchanged. Existing users who override `notes.path` MUST NOT be
affected.

### Migration from Submodules

**REQ-018.16** `ks` MUST support a migration path from the legacy
submodule layout. If `.submodules/keystone` or `agenix-secrets/` exist
inside the nixos-config repo, `ks` SHOULD emit a deprecation warning and
continue to use them via `--override-input`. `~/.keystone/repos/` MUST
take precedence when both exist.

**REQ-018.17** nixos-config's `flake.nix` MUST reference repos via
remote URLs (GitHub, Forgejo SSH), never via `path:` or
`git+file:...?submodules=1`. Local overrides are applied at build time
via `--override-input`, never baked into `flake.nix`.

### Future: Auto-Fork for Non-Collaborators

**REQ-018.18** (TODO) `ks` commands SHOULD automatically set up forks
for users who are not collaborators on a managed repo, using
`gh repo fork`. The fork remote SHOULD be configured alongside `origin`
so the user can push changes and submit pull requests upstream.

### Integration with Projects (REQ-010)

**REQ-018.19** Project repo declarations (REQ-010.11 `repos:` frontmatter)
MUST use full remote repository URLs. Tooling MUST normalize those URLs to
`owner/repo` and derive local paths by convention instead of storing absolute
filesystem paths in notes.

**REQ-018.19a** When a normalized `owner/repo` matches an entry in
`keystone.repos`, tooling SHOULD resolve that repo to
`~/.keystone/repos/{owner}/{repo}/`.

**REQ-018.19b** When a normalized `owner/repo` does not match an entry in
`keystone.repos`, tooling SHOULD resolve that repo to `$HOME/code/{owner}/{repo}/`
for humans and `/home/agent-{name}/code/{owner}/{repo}/` for agents.

## Supersedes

REQ-016.7 through REQ-016.10 (Lock Workflow Enhancement) are superseded
by this spec's repo registry and lock mode requirements (REQ-018.10
through REQ-018.12). REQ-016's dev mode requirements (REQ-016.1 through
REQ-016.6) and agent/doctor awareness (REQ-016.11 through REQ-016.13)
remain in effect.

## Edge Cases

- If `gh` CLI is not available, lock mode MUST fall back to direct
  `git push` and emit a warning if push fails.
- If a managed repo does not exist locally, `ks update --pull` MUST
  clone it. `ks build` MUST skip it with a warning rather than fail.
- Owner names are case-sensitive to match GitHub/Forgejo conventions
  (e.g., `Unsupervisedcom` not `unsupervisedcom`).
- Project repo URL normalization MUST support GitHub and Forgejo SSH and HTTPS
  remotes, strip an optional `.git` suffix, and fail on malformed paths instead
  of guessing.
- Notes path overrides: if a user sets a non-default `notes.path`, tooling
  SHOULD respect it and continue exporting that configured location via
  `NOTES_DIR`.
