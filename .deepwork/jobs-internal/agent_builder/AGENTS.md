# Job Management

This folder and its subfolders are managed using `deepwork_jobs` workflows.

## Recommended Workflows

- `deepwork_jobs/new_job` - Full lifecycle: define → implement → test → iterate
- `deepwork_jobs/learn` - Improve instructions based on execution learnings
- `deepwork_jobs/repair` - Clean up and migrate from prior DeepWork versions

## Directory Structure

```
.
├── .deepreview        # Review rules for the job itself using Deepwork Reviews
├── AGENTS.md          # This file - project context and guidance
├── job.yml            # Job specification (created by define step)
├── steps/             # Step instruction files (created by implement step)
│   └── *.md           # One file per step
├── hooks/             # Custom validation scripts and prompts
│   └── *.md|*.sh      # Hook files referenced in job.yml
├── scripts/           # Reusable scripts and utilities created during job execution
│   └── *.sh|*.py      # Helper scripts referenced in step instructions
└── templates/         # Example file formats and templates
    └── *.md|*.yml     # Templates referenced in step instructions
```

## Editing Guidelines

1. **Use workflows** for structural changes (adding steps, modifying job.yml)
2. **Direct edits** are fine for minor instruction tweaks

## Learnings

### Agent-space repo root IS the working directory (v2.0.0)

The agent-space repo root contains all files directly (SOUL.md, AGENTS.md, PROJECTS.yaml,
etc.) — there is NO `notes/` subdirectory. The `notes` directory seen at
`/home/agent-drago/notes/` is a symlink FROM the home directory TO the agent-space repo,
not a subdirectory within it. See `.repos/drago/agent-space/` for the canonical layout.

### Submodule is `.agents/` directly, not nested (v2.3.0)

The `ncrmro/agents` submodule lives at `.agents/` — NOT `.agents/ncrmro/agents/`.
This matches the Nix flake pattern where `.agents` is the submodule root.

### Symlink paths are relative to symlink location

- `.deepwork` at repo root → `.agents/.deepwork` (no `../`)
- `agents_repo` in `manifests/modes.yaml` → `../.agents` (one `../` from manifests/)

### Existing repos may already have git initialized

Always check for `.git` before running `git init`. Users often pre-create repos on
Forgejo with remotes already configured.

### Nix dev shell is shared via copies, not symlinks (v2.2.0)

The shared agents repo (`ncrmro/agents`) provides `flake.nix` with the dev shell
(deepwork, yq, etc.). Each agent-space **copies** `flake.nix` and `flake.lock` from the
submodule. Symlinks don't work because Nix flakes require all paths to be tracked in
the repo's git tree — symlinks into submodules cause "not tracked by Git" errors.
A real `.envrc` file (`use flake`) is created for direnv, then `direnv allow` is run.

### AGENTS.md is a symlink, not a generated file (v2.3.0)

`AGENTS.md` MUST be a symlink to `.agents/AGENTS_TEMPLATE.md` (the shared template in the
submodule). This ensures all agents automatically get template updates when the submodule
is updated. The template uses Claude Code `@` includes (`@SOUL.md`, `@HUMAN.md`,
`@SERVICES.md`, `@.agents/ARCHITECTURE.md`) which resolve relative to the repo root
(where the `CLAUDE.md` symlink lives). Do NOT generate `AGENTS.md` as a custom file.

Symlink chain: `CLAUDE.md → AGENTS.md → .agents/AGENTS_TEMPLATE.md`

### Ask before committing in interactive mode

When running interactively (not `claude -p`), agents MUST ask the user before committing
and pushing changes — especially to the shared agents library (`.agents/` submodule) which
has branch protection on `main`. Do not auto-commit convention updates, job file changes,
or any submodule modifications without explicit user confirmation.

### Quality reviews on scaffold step cause timeouts

The scaffold step produces many files (14+). Step-level quality reviews on this many
files time out. Reviews are disabled for scaffold — verification is built into the
step instructions (step 13).

### Convention Sync: .agents/ <-> keystone (v3.0.0)

Conventions live in two locations that must be kept in sync:

- `.agents/conventions/` — agent-space submodule (used by compose.sh to build AGENTS.md)
- `.repos/ncrmro/keystone/conventions/` — upstream shared library (canonical source)

The wire_mode step includes a sync instruction (step 7) to copy new conventions to keystone.

#### Out-of-sync conventions (as of 2026-03-19)

These conventions exist in `.agents/conventions/` but not yet in keystone:

- `process.blocker.md`
- `process.code-review-ownership.md`
- `process.deepwork-job.md`
- `process.refactor.md`

### Wiring Mechanism (v3.0.0)

This agent space uses `archetypes.yaml` (not `manifests/modes.yaml`) for convention wiring.
The wire_mode step should update `archetypes.yaml` at the `.agents/` repo root, adding the
convention to the appropriate archetype's `referenced_conventions` or role `conventions` list.

### SSH Key Signing Setup (v3.0.0)

- SSH key signing must be set up for both GitHub and Forgejo during onboarding
- Use Chrome DevTools MCP browser as the primary method for adding signing keys (especially on Forgejo where CLI support is limited)
- Always confirm the agent can log into the web UI before attempting to add SSH keys
- GitHub: `gh ssh-key add --type signing` works via CLI; browser fallback at `github.com/settings/ssh/new`
- Forgejo: Use browser at `git.ncrmro.com/user/settings/keys` — both auth and signing keys managed there

### Dependency Validation (v3.0.0)

Every `from_step` file input must have the corresponding step in `dependencies` — transitive
dependencies through the workflow DAG are not enough for validation.

### agentctl requires sudo — use direct commands when running as agent (v3.1.1)

The doctor workflow's `check_health` step originally used `agentctl` for all commands, but
`agentctl` requires sudo which isn't available when running as the agent user directly
(which is how task-loop sessions and interactive Claude Code sessions work). Use `systemctl
--user` and `journalctl --user` instead. Direct commands like `rbw unlocked`, `gh auth status`,
`ssh-add -l`, and `fj whoami` also work without agentctl wrappers.

See `steps/check_health.md` and `steps/analyze_logs.md` for the updated patterns.

### Quality reviews timeout with additional_review_guidance (v3.1.1)

Doctor workflow reviews that use `additional_review_guidance` to cross-reference prior step
outputs consistently hit the 240s timeout. This is because the reviewer must read multiple
files. Keep review criteria simple for intermediate steps and reserve cross-referencing
reviews for final outputs only, or accept that overrides may be needed.
