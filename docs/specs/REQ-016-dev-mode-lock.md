# REQ-016: Dev Mode Enhancement and Lock Workflow

Enhance the `ks` CLI dev mode to build only home-manager profiles (fast
iteration), add fork-fallback push to the lock workflow, and inform
`ks agent`/`ks doctor` about dev mode status.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Affected Modules

- `packages/ks/ks.sh` — dev mode build, lock workflow, agent prompt

## Requirements

### Dev Mode Build (home-manager only)

**REQ-016.1** `ks build` without `--lock` MUST build only home-manager
activation packages for all managed users and agents on each target host,
NOT the full NixOS system toplevel. This enables fast iteration on
terminal, desktop, and agent configurations.

**REQ-016.2** `ks update --dev` MUST build and activate ONLY home-manager
profiles (users + agents) across all target hosts, skipping the full
NixOS system rebuild.

**REQ-016.3** The home-manager-only build target MUST be:
`nixosConfigurations.<host>.config.home-manager.users.<user>.home.activationPackage`
for each home-manager-managed user on each target host.

**REQ-016.4** Dev mode deploy MUST activate home-manager profiles for
each user/agent on each target host:

- Local: run the activation script as the owning user
- Remote: SSH to the host, then run the activation script as the user

**REQ-016.5** Dev mode deploy SHOULD NOT require sudo, since home-manager
activation runs as the owning user. The sudo keepalive mechanism SHOULD
be skipped in dev mode.

**REQ-016.6** `ks update` without `--dev` (i.e., `--lock` mode, the
default) MUST continue to perform the full NixOS system rebuild and
deploy via `nixos-rebuild switch`, exactly as today.

### Lock Workflow Enhancement (Superseded by REQ-018)

> **Note**: REQ-016.7 through REQ-016.10 are superseded by
> REQ-018 (Keystone Home Directory and Repo Management), which
> generalizes the lock workflow to a declarative repo registry.
> REQ-016.9 (fork fallback) remains referenced by REQ-018.

**REQ-016.7** `ks build --lock` MUST be a new code path that performs:

1. Find local keystone repo and verify it is clean and on a branch
2. Rebase keystone onto upstream when possible, then push keystone (with fork fallback per REQ-016.9)
3. Lock flake inputs (`nix flake update keystone agenix-secrets`)
4. Commit `flake.lock` if changed
5. Build the full NixOS system toplevel for all targets
6. Push nixos-config

**REQ-016.8** `ks update --lock` (existing default behavior) MUST be
enhanced to include the keystone push with fork fallback (step 2 above)
after verifying repos are clean and before locking flake inputs.

**REQ-016.9** The lock workflow MUST detect whether the current user has
push access to the keystone GitHub repo by checking collaborator
permission via `gh api repos/{owner}/{repo}/collaborators/{user}/permission`.

- If the user has `write`, `maintain`, or `admin` permission → push
  directly to the keystone remote.
- Otherwise → fork the repo via `gh repo fork --clone=false` (if not
  already forked), push to the fork, and update the flake input to
  reference the fork.

**REQ-016.10** The lock workflow MUST build successfully before pushing
nixos-config, to prevent pushing a broken flake.lock.

### Agent/Doctor Dev Mode Awareness

**REQ-016.11** `ks agent` and `ks doctor` system prompts MUST include a
"Development Mode" section when a local keystone checkout is detected
(via `find_local_repo`).

**REQ-016.12** The dev mode section MUST report:

- Status: active/inactive
- Path to the local keystone checkout
- Current branch
- Whether there are uncommitted changes (dirty state)

**REQ-016.13** The dev mode section MUST document the dev-mode convention:

- `ks build` / `ks update --dev` rebuilds home-manager profiles only (fast)
- `ks build --lock` / `ks update` (default) performs full system rebuild
- Lock flow: commit + push keystone → lock flake → build → push nixos-config

## Edge Cases

- If `gh` CLI is not available, the lock workflow MUST fall back to
  a direct `git push` and emit a warning if push fails (suggesting
  the user install `gh` or push manually).
- If the keystone remote URL is SSH-based, the owner/repo extraction
  MUST handle both `git@github.com:owner/repo.git` and
  `ssh://git@github.com/owner/repo.git` formats.
- If no home-manager users exist for a target host, `ks build` (dev mode)
  MUST succeed with a warning rather than error.
- If `ks update --dev` targets a host with only system-level changes
  (no home-manager changes), the deploy SHOULD be a no-op for that host.
