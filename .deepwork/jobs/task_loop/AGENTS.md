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

### Infrastructure issues must be filed on keystone (v3.3.2)

When the execute step encounters a non-project infrastructure problem (auth expired, NixOS
config error, missing dev shell, service permission denied, Nix store path issues), the agent
MUST file an issue on `ncrmro/keystone` via `/deepwork agent_builder.issue` in addition to
documenting in ISSUES.yaml. The admin (`ncrmro`) needs visibility into infrastructure problems
that agents cannot fix themselves. Silently blocking a task with only a local ISSUES.yaml entry
means the admin never learns about the problem.

See `steps/execute.md` for the updated guidelines (step 7, "If the task is blocked by an
external issue" and the "Infrastructure issues go to keystone" guideline).

### agentctl vs direct commands

When the task loop runs as the agent user (which it always does via systemd), use direct
commands (`systemctl --user`, `journalctl --user`, `gh auth status`, `rbw unlocked`) rather
than `agentctl` wrappers which require sudo. See the `agent_builder` doctor workflow learnings
at `.deepwork/jobs/agent_builder/AGENTS.md` for the full context.
