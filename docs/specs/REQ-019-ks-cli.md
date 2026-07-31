# REQ-019: ks CLI

The `ks` CLI is the primary interface for building, deploying, and
managing keystone NixOS infrastructure. This spec consolidates
requirements previously scattered across inline comments in `ks.sh`,
REQ-016, and REQ-018.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Affected Modules

- `packages/ks/ks.sh` — CLI script
- `packages/ks/default.nix` — Nix packaging

## Commands

| Command | Description |
|---------|-------------|
| `ks build [--lock] [HOSTS]` | Build home-manager profiles (default) or full system (`--lock`) |
| `ks update [--dev] [--boot] [--pull] [--lock] [HOSTS]` | Pull, lock, build, push, and deploy to hosts |
| `ks agents <pause|resume|status> <agent|all> [reason]` | Control agent task-loop pause state |
| `ks switch [--boot] [HOSTS]` | Fast deploy current state without pull/lock/push |
| `ks sync-host-keys` | Populate `hostPublicKey` in `hosts.nix` from live hosts |
| `ks agent [--local [MODEL]] [args...]` | Launch AI agent with keystone OS context |
| `ks doctor [--local [MODEL]] [args...]` | Launch diagnostic AI agent with system state |
| `ks help [command]` | Show top-level or command-specific help |

`HOSTS` is a comma-separated list of host names. Defaults to the current
machine's hostname as resolved from `hosts.nix`.

## Requirements

### Repo Discovery

**REQ-019.1** `ks` MUST discover the consumer flake repository root using
the following priority chain:

1. `--flake <path>` CLI flag (explicit override)
2. `/run/current-system/keystone-system-flake` pointer file (written at NixOS activation time by `keystone.systemFlake`)
3. Hard error with guidance

**REQ-019.1a** The pointer file MUST contain the absolute path to the consumer
flake followed by a newline. It is written by `system.systemBuilderCommands`
in `modules/shared/system-flake.nix` using the value of `keystone.systemFlake.path`.
The same `systemBuilderCommands` block writes
`/run/current-system/keystone-update-channel` from
`config.keystone.update.channel` so detached graphical-session apps have a
stable channel source without depending on shell env propagation.

**REQ-019.1b** A valid consumer flake MUST contain `flake.nix` AND either
`hosts/` (mkSystemFlake layout) or `hosts.nix` (legacy layout). A bare
`hosts.nix` without `flake.nix` is rejected.

**REQ-019.2** All discovered paths MUST be resolved via `std::fs::canonicalize`
to eliminate symlinks, because Nix `path:` flake URIs break on symlinks.

### Help and usage

**REQ-019.2a** `ks` MUST support top-level help via `ks --help`, `ks -h`, and `ks help`.

**REQ-019.2b** `ks` MUST support command-specific help via `ks help <command>`,
`ks <command> --help`, and `ks <command> -h`.

**REQ-019.2c** `ks` MUST provide help text for every public command:
`build`, `update`, `agents`, `switch`, `sync-host-keys`, `grafana`,
`agent`, and `doctor`, plus the nested `grafana dashboards` command
surface.

**REQ-019.2d** Help output MUST include a usage line, a concise purpose
statement, documented flags and positional arguments, and at least one
example invocation.

**REQ-019.2e** Help requests MUST exit successfully. Invalid usage and
unknown commands MUST remain non-zero.

### Build

**REQ-019.3** `ks build` without `--lock` MUST build only home-manager
activation packages for all managed users and agents on each target host
(fast iteration, no sudo required).

**REQ-019.4** `ks build --lock` MUST build the full NixOS system toplevel
for all target hosts.

**REQ-019.5** `ks` MUST always use local repo checkouts (per REQ-018)
as `--override-input` when those directories exist, regardless of mode.

**REQ-019.6** `ks` MUST build all target hosts before deploying any of
them (fail-fast ordering). `ks update` and `ks switch` MUST capture
the built store paths from the parallel build phase and use them
directly for deployment to prevent redundant Nix evaluations.

**REQ-019.7** `ks` MUST pass `--no-link` to `nix build` to prevent
`./result` symlinks in the caller's working directory.

### Lock Mode (repo management)

**REQ-019.8** Lock mode (`ks build --lock`, `ks update` default) MUST:

1. Pull nixos-config, keystone, and agenix-secrets before building
2. Verify managed lock repos are clean and on a branch before lock-mode sync
3. Rebase managed lock repos onto upstream when Git can do so without conflicts, then push any remaining ahead commits, using keystone fork fallback per REQ-016.9 when needed
4. Update `flake.lock` via `nix flake update` BEFORE building (not after)
5. Build all target hosts
6. Commit and push `flake.lock` only AFTER a successful build

**REQ-019.9** `ks update --pull` MUST pull all managed repos (per REQ-018.12)
without building or deploying.

### Deployment

**REQ-019.10** `ks` MUST deploy hosts sequentially (not in parallel) to
limit blast radius.

**REQ-019.11** `ks` MUST obtain sudo credentials before any other work
(pull, lock, build) when a local host is targeted, so the user is not
interrupted mid-run.

**REQ-019.12** `ks` SHOULD keep sudo credentials alive for the duration
of the run.

**REQ-019.13** `ks update --dev` MUST build and activate only home-manager
profiles (users + agents) across all target hosts, skipping the full
NixOS system rebuild. Keystone policy MAY still require an approval flow
before this command runs.

**REQ-019.14** `ks update --boot` and `ks switch --boot` MUST set the
NixOS configuration for next boot without activating it immediately.

**REQ-019.15** `ks switch` MUST provide a fast-iteration deployment
workflow by building and activating the current local state immediately,
skipping the pull, lock, and push phases required by `ks update`.

**REQ-019.16** Smart Deploy: `ks update` and `ks switch` MUST automatically
detect if an update only modifies home-manager profiles by comparing the
newly built `toplevel` against the currently running system.

- It MUST compare `sw`, `kernel`, `initrd`, and `/etc` (excluding `per-user`).
- If only home-manager files changed (no core OS changes), it MUST bypass
  the slow `switch-to-configuration switch` and instead activate the
  home-manager profile directly, followed by a fast `switch-to-configuration boot`
  to register the generation.

### Dev Mode

**REQ-019.15** Dev mode (`ks build` without `--lock`, `ks update --dev`)
MUST skip pull, flake-update, commit, and push phases.

**REQ-019.16** Dev mode MAY be used with uncommitted local repo changes.

### Dev Mode — Local Script Execution

**REQ-019.17** `ks` MUST be runnable directly from the local keystone
checkout at `~/.keystone/repos/{owner}/keystone/packages/ks/ks.sh`
(per REQ-018) without requiring a Nix rebuild. This enables testing
changes to the script immediately.

**REQ-019.18** `ks` MUST NOT depend on Nix-time variable substitutions
(`replaceVars` / `@placeholder@` patterns). All dependencies MUST be
resolved at runtime via `PATH` or explicit discovery functions.

**REQ-019.19** The keystone terminal module SHOULD add the local keystone
`packages/ks/` directory to the user's `PATH` when a local checkout
exists at the REQ-018 standard location, so the dev version of `ks`
takes precedence over the Nix-built version.

**REQ-019.20** Scripts that require Nix-time substitutions (e.g.,
`agentctl` with `replaceVars` for agent metadata and tool paths) MUST
be rebuilt via `ks build` (home-manager) or `nixos-rebuild` (system-level)
to pick up changes. This distinction MUST be documented in the project's
`CLAUDE.md`.

### Agent / Doctor Prompt Handling

**REQ-019.21** `ks agent` and `ks doctor` MUST launch Claude Code with
a system prompt containing host tables, agent status, conventions, and
(for doctor) live system state.

**REQ-019.22** The system prompt MUST NOT be passed as a single
command-line argument to `claude` or `agentctl`, because large prompts
(fleet health + agent tasks + conventions) exceed the Linux execve
`ARG_MAX` limit (~4MB including environment). Prompts MUST be written
to a temp file and passed via a mechanism that avoids `ARG_MAX`:

- Write to a checksummed temp file (`/tmp/ks-prompt-{hash}`)
- Pass to `claude` via `--append-system-prompt "@/tmp/ks-prompt-{hash}"` (the `@path` syntax instructs Claude Code to read the file from disk, keeping the argv small)

**REQ-019.23** `ks agent` MUST pass through additional arguments to the
underlying claude invocation.

**REQ-019.24** `ks doctor` MUST gather current system state (NixOS
generation, failed units, disk usage, fleet health, agent health, agent
tasks) and include it in the prompt context.

**REQ-019.25** `ks agent` and `ks doctor` MUST support `--local [MODEL]`
to use Ollama instead of Claude Code (REQ-014.12-13).

### Host Key Sync

**REQ-019.26** `ks sync-host-keys` MUST SSH to each host in `hosts.nix`
that has an `sshTarget`, read `/etc/ssh/ssh_host_ed25519_key.pub`, and
update the `hostPublicKey` field in `hosts.nix`.

### Agent task-loop controls

**REQ-019.27** `ks` MUST provide an `agents` command group with the
subcommands `pause`, `resume`, and `status` for agent task-loop control.

**REQ-019.28** `ks agents pause <agent|all> [reason]` MUST create the
task-loop pause marker for one agent or all configured agents without
stopping or disabling the timer units.

**REQ-019.29** `ks agents resume <agent|all>` MUST remove the task-loop
pause marker for one agent or all configured agents.

**REQ-019.30** `ks agents status <agent|all>` MUST report whether the
target agent task loop is paused. It SHOULD include the pause timestamp,
pause actor, and pause reason when present.

### Supervised update flow (`ks update --approve`)

The supervised update path is the desktop-triggered, single-host channel-update
flow invoked by Walker → Update. Implementation: `packages/ks/src/cmd/update_approve.rs`.
Privileged elevation goes through `cmd::approve` (REQ-016 family) and is
narrow: only `ks activate <store-path>` runs as root. Channel resolution,
`nix build`, `nix flake update`, `git commit`, and `git push` all run in
the user's session.

**REQ-019.31** `ks update --approve` MUST run the following steps in order
on every invocation:

1. **Pre-flight in-sync check.** Refuse to start unless the consumer flake's
   working tree is clean AND the current branch resolves to the same SHA
   as `origin/<branch>`. The error MUST name the specific reason
   (uncommitted changes / ahead / behind) so the user can act without
   inspecting logs.
2. **Channel resolution.** Resolve the active channel
   (`keystone.update.channel`, REQ-019.1a runtime pointer + env override)
   to a concrete keystone rev via the GitHub API.
3. **Early polkit prompt (cache warm).** Trigger the `com.ncrmro.keystone.approve`
   action via `cmd::approve::run_and_wait` with a no-op activation payload
   targeting the running system. The orchestrator MUST canonicalize
   `/run/current-system` to its underlying `/nix/store/<closure>` path
   before constructing the `ks activate <path>` argv, because
   `cmd::activate::validate_store_path` rejects any argument not under
   `/nix/store/` as defense-in-depth. `ks activate` then short-circuits
   because the canonical closure already matches `/run/current-system`,
   producing zero side effects beyond the polkit prompt. The prompt MUST
   appear within ~2 s of Walker dispatch so the user can authenticate
   while still focused on the action. Polkit's `auth_admin_keep`
   (configured by `keystone.security.privilegedApproval`) then caches
   the credential for ~5 min, covering the build and activation steps
   without a second prompt.
4. **Build-phase notification.** Emit a `notify-send` "Keystone update:
   building <target>…" via `cmd::util::notify_send`, gated by
   `KS_UPDATE_NOTIFY=1` in the same way the launcher already sets the
   completion / failure notifications. This bridges the silent
   build-phase wait so the user has feedback after authenticating.
5. **Lock-first bump.** Update `flake.lock`'s `keystone` input to
   `github:ncrmro/keystone/<rev>` via
   `nix flake update keystone --override-input keystone github:.../<rev>`,
   then commit it with subject `chore: bump keystone to <target>`.
   Capture the resulting commit SHA as `bump_sha`. The commit MUST NOT
   be pushed yet — push is the final post-activation step.
6. **Build.** Run `nix build` against the consumer flake's
   `nixosConfigurations.<host>.config.system.build.toplevel`. The lock
   now points at the target rev, so no `--override-input` is needed for
   correctness; local file-source overrides (dev mode) MAY still be
   layered.
7. **Activation.** Drive `ks activate <store-path>` via the privileged
   broker (`cmd::approve::run_and_wait`). Polkit MUST hit the cached
   credential from step 3 and not re-prompt under normal conditions; if
   the cache has expired, the user MAY be prompted again as degraded
   UX, which is acceptable but SHOULD be rare.
8. **Push.** On activation success, `git push origin <branch>` is
   best-effort. A failed push is logged as a warning but does not fail
   the run — the local generation is already promoted and the lock
   matches it.
9. **Final notification.** `notify-send` "Keystone update complete" on
   success or "failed" on any failure path with a journal pointer.

**REQ-019.31a** Steps 1, 2, and 3 MUST run before any filesystem mutation
on the consumer flake. The user MAY cancel the polkit prompt to abort
the run cleanly with no side effects.

**REQ-019.31b** Steps 5 (lock bump) and 7 (activation) form the atomicity
contract. If activation fails — including any non-zero exit other than
the documented switch-to-configuration exit code 4 (success-with-warnings,
see `cmd::activate::switch_to_configuration`) — the orchestrator MUST
roll back the bump commit by verifying `HEAD` still equals `bump_sha`
and running `git reset --hard HEAD~1`. Rollback MUST refuse if `HEAD`
diverged from `bump_sha` between commit and failure (the user committed
in parallel) and surface a clear error rather than discarding their work.

**REQ-019.31c** Push failure (step 8) after a successful activation MUST
NOT trigger rollback. The local generation is on the new closure; the
lock matches; only the remote is behind. The user can resolve by hand.

**REQ-019.31d** All notifications emitted by the supervised flow MUST be
gated on `KS_UPDATE_NOTIFY=1`. The launcher (`cmd::update_menu::start_update_session`)
sets this; direct CLI invocations do not, so they remain quiet on the
desktop.

**REQ-019.31e** The polkit dialog's `Approval request:` line MUST name
the host (e.g., "Install Keystone update on ncrmro-laptop") so a user
with multiple machines can tell which host the dialog is for. The
allowlist `displayName` provides the static title; the per-request
`Requested reason:` carries the host context.

**REQ-019.31f** `ks update --approve --keystone <ref>` provides a
local-development override for the supervised flow. `<ref>` is any
value accepted by `nix flake update keystone --override-input keystone
<ref>` (typically `github:ncrmro/keystone/<branch-or-sha>` or
`path:/absolute/path/to/worktree`). When set:

1. Step 2 (channel resolution) is skipped; the flag value becomes the
   target ref and target label directly.
2. Step 5 advances `flake.lock` in the working tree only via
   `relock_keystone_input` — **no commit, no `bump_sha`**.
3. Step 8 (`git push`) is skipped unconditionally — the override is
   never published.
4. `restore_flake_lock` runs unconditionally at end-of-run (success or
   failure), restoring `flake.lock` from `HEAD` so the consumer flake
   ends clean.

The user explicitly accepts the temporary divergence: the running
system is activated against the override target while `flake.lock`
points at the channel rev. Re-running `ks update --approve` without
the flag brings the system back to the channel rev. The flag is
invalid alongside any non-`--approve` mode.

## Edge Cases

- If `gh` CLI is not available, lock mode MUST fall back to direct
  `git push` and emit a warning if push fails.
- If no home-manager users exist for a target host, `ks build` (dev mode)
  MUST succeed with a warning rather than error.
- Risky hosts SHOULD be deployed last when multiple hosts are targeted
  (user convention, not enforced).
- Remote URL parsing MUST handle both `git@github.com:owner/repo.git`
  and `ssh://git@host/owner/repo.git` formats, stripping `.git` suffix
  correctly (no double `.git.git`).

## Supersedes

- Inline RFC 2119 comments in `ks.sh` (lines 31-54) — formalized here
- REQ-016.7-10 (lock workflow) — consolidated into REQ-019.8
- REQ-014.1-13 (ks agent/doctor) — consolidated into REQ-019.21-25
- REQ-018.6-12 (dev mode + lock mode repo behavior) — referenced, not duplicated
