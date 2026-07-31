## Agent Cronjobs

**Status:** MUST follow (RFC 2119)

## Overview

Every OS agent provisioned via `keystone.os.agents.<name>` receives three systemd user timers that run automatically via lingering. These timers are defined in `.submodules/keystone/modules/os/agents.nix`.

## Timers

| Timer      | Unit Name                 | Default Schedule              | Purpose                                          |
| ---------- | ------------------------- | ----------------------------- | ------------------------------------------------ |
| Notes Sync | `agent-{name}-notes-sync` | `*:0/5` (every 5 min)         | Git fetch/commit/push for the agent's notes repo |
| Task Loop  | `agent-{name}-task-loop`  | `*:0/5` (every 5 min)         | Autonomous work execution cycle                  |
| Scheduler  | `agent-{name}-scheduler`  | `*-*-* 05:00:00` (daily 5 AM) | Reads `SCHEDULES.yaml`, creates due tasks        |

All timers use:

- `wantedBy = [ "default.target" ]` — auto-start with user session (lingering)
- `ConditionUser = agent-{name}` — only runs as the correct agent user
- `Persistent = true` — catches up if the system was offline during a scheduled run

## NixOS Configuration

```nix
keystone.os.agents.luce = {
  notes = {
    syncOnCalendar = "*:0/5";              # Every 5 minutes
    taskLoop.onCalendar = "*:0/5";         # Every 5 minutes
    taskLoop.maxTasks = 5;                 # Max pending tasks per run
    scheduler.onCalendar = "*-*-* 05:00:00"; # Daily at 5 AM
  };
};
```

Schedules use [systemd calendar syntax](https://www.freedesktop.org/software/systemd/man/systemd.time.html#Calendar%20Events).

## Notes Sync (`agent-{name}-notes-sync`)

- Runs `repo-sync` package: clone-if-absent, fetch, commit changes with `"vault sync"` prefix, rebase, push
- Environment: `SSH_AUTH_SOCK` from the agent's SSH agent socket
- Logs to `~/.local/state/notes-sync/logs/`

## Task Loop (`agent-{name}-task-loop`)

Five-phase cycle:

1. **Pre-fetch** — Sync external sources (Forgejo issues, email) into the agent home
2. **Ingest** — Parse new items into `TASKS.yaml`
3. **Prioritize** — Rank pending tasks
4. **Execute** — Run up to `maxTasks` pending tasks (invokes Claude Code per task)
5. **Commit** — Push results back

Key properties:

- `TimeoutStartSec = "1h"` — long timeout for LLM-driven tasks
- Uses `flock` for concurrency prevention (skips if already running)
- Honors a pause marker at `~/.local/state/agent-task-loop/state/paused`
- When paused, scheduled runs exit before pre-fetch and execution work
- Structured logging with `[step=X]` and `[task=Y]` tags
- State in `~/.local/state/agent-task-loop/state/`
- Logs in `~/.local/state/agent-task-loop/logs/`
- Per-task logs in `~/.local/state/agent-task-loop/logs/tasks/`
- `SyslogIdentifier = agent-{name}-task-loop`

## Scheduler (`agent-{name}-scheduler`)

- Pure bash, no LLM invocation
- Reads `SCHEDULES.yaml` from the agent's home directory
- Creates tasks in `TASKS.yaml` when schedule conditions match (day-of-week, day-of-month, date)
- Logs to `~/.local/state/agent-scheduler/logs/`
- `SyslogIdentifier = agent-{name}-scheduler`

## Monitoring & Debugging

```bash
# Check timer status
agentctl luce status agent-luce-notes-sync
agentctl luce status agent-luce-task-loop
agentctl luce status agent-luce-scheduler

# View logs
agentctl luce journalctl -u agent-luce-task-loop -n 50
agentctl luce journalctl -u agent-luce-scheduler -n 20

# Manually trigger
agentctl luce start agent-luce-task-loop

# Pause or resume the loop without disabling timers
agentctl luce pause "waiting for human input"
agentctl luce paused
agentctl luce resume
ks agents pause all "human focus block"
```

For fleet-wide journal queries across all hosts, see `tool.journal-remote`.

Alloy/Loki integration extracts `[step=X]` labels from structured log tags for observability dashboards.

## Source Reference

- Timer/service definitions: `keystone/modules/os/agents.nix` (lines 2082–2190)
- Option definitions: `keystone/modules/os/agents.nix` (lines 287–313)
- Task loop script: `keystone/modules/os/agents.nix` (lines 489–720)
- Scheduler script: `keystone/modules/os/agents.nix` (lines 721–843)
- Spec: `docs/specs/REQ-007-os-agents.md` (FR-010)
