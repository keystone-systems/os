# Keystone System Job

This job manages the keystone NixOS module development lifecycle.

## Slash Commands

The workflows are accessible as Claude Code slash commands:

- `/ks.develop <goal>` — Full development lifecycle (plan → implement → review → build → merge → deploy → validate)
- `/ks.convention <topic>` — Create or update a convention (draft → cross-reference → apply → commit to main)
- `/ks.update` — Deploy pending keystone changes: survey fleet, triage, fix, build, deploy, validate
- `/ks.doctor [context]` — Standalone fleet health check across all hosts

See `.claude/commands/ks.develop.md`, `.claude/commands/ks.convention.md`, `.claude/commands/ks.update.md`, and `.claude/commands/ks.doctor.md`.

## Workflows

| Workflow     | Steps                                                                                | Purpose                       |
| ------------ | ------------------------------------------------------------------------------------ | ----------------------------- |
| `develop`    | plan → implement → review → build → merge → deploy → validate                        | Full lifecycle                |
| `update`     | survey_fleet → plan_update → execute_fixes → preflight_build → run_update → validate | Catch-up deploy               |
| `convention` | draft_convention → cross_reference → apply_convention → commit_convention            | Convention CRUD               |
| `doctor`     | survey_fleet → validate                                                              | Standalone fleet health check |

## Key Conventions

- **All work in worktrees**: Never commit directly to main. See `steps/plan.md` for branch naming.
- **Fast-path builds**: Use `ks build` (home-manager only) when changes don't touch OS modules. See `steps/build.md` for the tiered verification strategy.
- **Multi-host validation**: After deploy, check ALL affected hosts, not just the current one. See `steps/validate.md`.
- **Human-in-the-loop deploy**: Only `steps/deploy.md` requires sudo — everything else is agent-driven.

## Bespoke Learnings

### v1.1.0 — Initial creation (2026-03-20)

- The workflow is designed for non-trivial multi-step development. Trivial 1-line fixes (like the SC2155 shellcheck fix) can bypass the workflow.
- `nix-instantiate --parse` only works on `.nix` files — don't use it for shell scripts. Use `shellcheck` for `.sh` files.
- After merge, worktrees are cleaned up. If validation fails and requires a fix, a new worktree is created via the plan step — this is by design (clean worktree per change).

### v1.2.0 — Doctor run learnings (2026-03-20)

- The validate step must check **agent health**, not just host services. Use `agentctl <agent> status/tasks/email` and check Tailscale status for offline agents.
- Tailscale offline agents (e.g., agent-drago offline 13d) should be flagged as needing attention.

### v1.4.0 — Convention workflow (2026-03-21)

- The convention workflow commits directly to main (no worktree) because conventions are documentation files.
- Cross-reference bidirectionality is enforced by the quality gate — if convention A references B, B must reference A.
- When pushing to main, the remote may have new commits from other workflows. The commit step must handle rebase (stash → pull --rebase → stash pop → push).
- When asking which archetypes to wire into, show the user which roles already reference related conventions to help them make informed placement decisions.
- The convention workflow scanned 38 conventions for overlap on first test — the cross-reference step is thorough but found only 2 cross-ref opportunities (no duplicates), which is expected for a genuinely new domain.

### v1.8.0 — Archive doctor reports to zk notes (2026-03-24)

- **Doctor reports belong in the configured notes dir, not in the keystone open-source repo**: fleet_survey.md and validation_report.md contain personal deployment data (host names, IPs, generations, service failures) specific to the user's keystone deployment — not the open-source project. After completing the validate step, archive a summary to `NOTES_DIR` (`~/notes` for Keystone human users) using `zk --notebook-dir "$NOTES_DIR" new ...`.
- **The configured notes dir is the primary zk notebook** — on Keystone systems, `NOTES_DIR` resolves to `keystone.notes.path` (`~/notes` for human users). It has `journal/`, `notes/`, `inbox/`, and other directories. The zk config auto-names notes as `YYYYMMDDHHMM slug-title.md`. The note should contain a concise summary (not the full raw output files).
- **The `.deepwork/jobs/` folder is scratch space** — it's fine for working files during execution but is not the final destination for personal system data.

### v1.9.2 — Issue workflow output hygiene (2026-03-30)

- **Use a unique slug-based filename per issue**: `.deepwork/tmp/keystone-issue-<slug>.md`, not a generic `keystone-issue.md`. Multiple issues filed in the same session will silently overwrite a shared name.
- **Archive issues to notes if notes are enabled**: After `gh issue create`, check if `keystone.notes` is enabled and create a brief `zk` note in `NOTES_DIR` with the issue URL and a one-paragraph summary. This mirrors how doctor reports are archived (see v1.8.0 learning). See `steps/write_issue.md` step 5 for the exact commands.

### v1.8.1 — Issue workflow correction (2026-03-24)

- **`keystone_system/issue` creates GitHub issues, not standalone specs**: the authoritative output is a GitHub issue on `ncrmro/keystone` whose body contains the RFC 2119 requirements, architecture diagram, affected modules, and implementation checklist.
- **The issue body is the plan of record**: it should be written so the eventual PR description can reuse the same requirements and deliverables with minimal rewriting.
- **Include user stories, plural**: when the feature affects more than one actor or workflow, the issue body should have a `## User stories` section with multiple bullets rather than a single generic story.
- **A local markdown file may exist only as a staging artifact** for `gh issue create --body-file`; do not leave the workflow framed as "create `specs/REQ-XXX/.../requirements.md`" unless the user explicitly asked for a committed spec file too.

### v1.7.0 — Doctor report quality (2026-03-24)

- **Always cross-reference issues with GitHub before flagging as new**: When the doctor finds failed units or health problems, search GitHub first (`gh issue list --search "<keyword>" --repo ncrmro/keystone` and `ncrmro/nixos-config`). There is already an existing GitHub issue for the `syncoid-rpool-to-*` ZFS backup sync failures — link to it rather than treating it as new.
- **Agent health needs task-level detail**: The report should show each agent's task queue depth, recent job names, and any blocking issues — not just "services running." Use `agentctl <agent> jobs` (or equivalent) to get recent activity.
- **Tailscale offline for agents is expected (TODO)**: Agent Tailscale integration is a planned feature, not yet implemented. Tailscale offline status for agent nodes should be documented as informational, not flagged as an alert. Only flag host-level Tailscale nodes going offline.

### v1.6.0 — Doctor recursion fix (2026-03-24)

- **`ks doctor` is an AI entrypoint, not a shell tool**: Running `ks doctor` inside a workflow step launches a new `/ks.doctor` slash command session — recursive and wrong. Use `systemctl --failed`, `systemctl is-system-running`, and `journalctl -p err --since '1 hour ago'` for direct host health checks instead.
- This affected both `survey_fleet.md` (step 3) and `validate.md` (step 1) — both have been corrected.
- The same applies to any other `ks` AI entrypoints (`ks switch`, etc.) — never call them as shell commands from within a workflow.

### v1.5.0 — Update workflow (2026-03-23)

- **Always use `ks update --lock` explicitly** — never omit `--lock` even though it's the default. The user expects the explicit flag for clarity and the workflow's goal is reaching a locked state.
- **Present the full command with hosts**: The run_update step must output the exact command including host list, e.g., `ks update --lock ncrmro-workstation,ocean,mercury,maia`. Don't make the user figure out which hosts to include.
- **Preflight build is essential**: Always run `ks build <hosts>` before the human-in-the-loop deploy. This catches eval errors without requiring sudo and saves the human from wasted time on failed builds.
- **De-risk updates: one host at a time, `--boot` for risky changes**: When changes touch Secure Boot (lanzaboote), bootloader, kernel, or systemd-boot config, recommend the human deploy to ONE local host first (laptop/workstation where they have physical access) with `--boot`, reboot, verify it works, THEN deploy to remote hosts. A past lanzaboote update broke Secure Boot on ocean and required physical BIOS intervention. Remote servers should NEVER be the first host to receive bootloader changes.
- **Reboot resume instructions**: When `--boot` is used and a reboot is required, the session is lost. Before the reboot, write `.deepwork/tmp/resume_context.md` with the current workflow state (step, deployed hosts, remaining hosts, verification checklist, next command) and output instructions for the human on how to resume in a new claude/gemini session. The resume file survives the reboot and gives the next agent full context.
- **LFS history rewrites inflate commit counts**: When keystone history is rewritten (e.g., to remove LFS), `git log locked..main` shows the entire rewritten history. Use `--since=<lock-date>` to find the real delta instead of relying on `locked..main` when commit counts seem unreasonably high.
- **The survey_fleet step is reused by doctor**: Both `update` and `doctor` workflows now start with survey_fleet, making it the standard fleet state collection step.
- **Config repo path standardization**: `nixos-config` will become `keystone-config`. Use `~/.keystone/repos/nixos-config` as canonical path with fallbacks.

## Nix Eval for System Context

The standard way to get hosts/users/agents/services is via `nix eval` against `~/.keystone/repos/nixos-config`. This is the canonical path — agents MUST use this, not hardcoded paths.

### Agents (compact)

```bash
nix eval ~/.keystone/repos/nixos-config#nixosConfigurations.<HOST>.config.keystone.os.agents \
  --json --apply 'a: builtins.mapAttrs (_: v: {
    fullName = v.fullName; host = v.host or null;
    archetype = v.archetype; desktop = v.desktop.enable;
    mail = v.mail.provision; chrome = v.chrome.enable;
  }) a'
```

### Users (compact)

```bash
nix eval ~/.keystone/repos/nixos-config#nixosConfigurations.<HOST>.config.keystone.os.users \
  --json --apply 'u: builtins.mapAttrs (_: v: { fullName = v.fullName or ""; }) u'
```

### Hosts

```bash
nix eval -f ~/.keystone/repos/nixos-config/hosts.nix --json
```

### Enabled Services

```bash
nix eval ~/.keystone/repos/nixos-config#nixosConfigurations.<HOST>.config.keystone.server._enabledServices \
  --json 2>/dev/null
```

Replace `<HOST>` with the host key from `hosts.nix` (e.g., `ncrmro-workstation`, `ocean`).

**Future improvement**: These evals should be wrapped into a single `ks status` command. See `packages/ks/ks.sh:770` (`build_user_table`) for the existing partial implementation.

## Editing Guidelines

1. **Use workflows** for structural changes (adding steps, modifying job.yml)
2. **Direct edits** are fine for minor instruction tweaks
3. **Run `/deepwork learn`** after executing the workflow to capture new learnings
