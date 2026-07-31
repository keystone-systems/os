# Check Health

## Objective

Produce a comprehensive health snapshot of an agent's systemd timers, service prerequisites, and operational state.

## Inputs

- `agent_name` — the agent to diagnose (e.g., `luce`, `drago`)

## Task

### 1. Determine agent home and notes path

```bash
agent_home="/home/agent-${agent_name}"
notes_dir="${agent_home}/notes"
```

Verify the notes directory exists and is a git repo.

### 2. Check systemd timer status

Run status checks for all three timers. Detect execution context first:

- **If running as the target agent user** (i.e., `whoami` matches `agent-${agent_name}`): use `systemctl --user` and `journalctl --user` directly
- **If running as root or another user with sudo**: use `agentctl ${agent_name} status`

Direct (as agent user):

```bash
systemctl --user status agent-${agent_name}-notes-sync.timer
systemctl --user status agent-${agent_name}-notes-sync.service
systemctl --user status agent-${agent_name}-task-loop.timer
systemctl --user status agent-${agent_name}-task-loop.service
systemctl --user status agent-${agent_name}-scheduler.timer
systemctl --user status agent-${agent_name}-scheduler.service
```

For each timer, record:

- Active state (active/inactive/failed)
- Last trigger time
- Next trigger time
- Result of last run (success/failure/timeout)

### 3. Check service prerequisites

Verify these prerequisites as the agent user:

| Check          | Command                          | Pass Criteria           |
| -------------- | -------------------------------- | ----------------------- |
| Git repo       | `ls ${notes_dir}/.git`           | Exists                  |
| SSH agent      | `ssh-add -l`                     | At least one key listed |
| rbw vault      | `rbw unlocked`                   | Exit 0                  |
| direnv         | `ls ${notes_dir}/.envrc`         | Exists                  |
| Nix flake      | `ls ${notes_dir}/flake.nix`      | Exists                  |
| gh CLI         | `gh auth status`                 | Authenticated           |
| fj CLI         | `fj whoami`                      | Returns username        |
| TASKS.yaml     | `ls ${notes_dir}/TASKS.yaml`     | Exists                  |
| SCHEDULES.yaml | `ls ${notes_dir}/SCHEDULES.yaml` | Exists                  |
| SOUL.md        | `ls ${notes_dir}/SOUL.md`        | Exists                  |

### 4. Check for lock contention

```bash
flock -n /tmp/agent-${agent_name}-task-loop.lock echo "free" || echo "locked"
```

### 5. Check git state

```bash
cd ${notes_dir} && git status --porcelain
cd ${notes_dir} && git log --oneline -5
```

Look for:

- Uncommitted changes (dirty working tree)
- Rebase in progress (`.git/rebase-merge/` or `.git/rebase-apply/`)
- Merge conflicts

## Output Format

Write `health_snapshot.md` with this structure:

```markdown
# Health Snapshot: agent-{name}

**Date:** {timestamp}
**Agent Home:** /home/agent-{name}
**Overall Status:** {HEALTHY | DEGRADED | UNHEALTHY}

## Timer Status

| Timer      | State  | Last Run | Result  | Next Run |
| ---------- | ------ | -------- | ------- | -------- |
| notes-sync | active | ...      | success | ...      |
| task-loop  | active | ...      | failure | ...      |
| scheduler  | active | ...      | success | ...      |

## Prerequisites

| Check     | Status | Detail         |
| --------- | ------ | -------------- |
| Git repo  | PASS   | ...            |
| SSH agent | FAIL   | No keys loaded |
| ...       | ...    | ...            |

## Git State

- Working tree: clean / dirty (N files)
- Rebase in progress: yes / no
- Last 5 commits: ...

## Lock State

- Task loop flock: free / locked (PID: ...)

## Issues Found

1. {brief description of each issue}
2. ...
```

Overall status rules:

- **HEALTHY** — all timers active with recent success, all prerequisites pass
- **DEGRADED** — some timers failed or some prerequisites missing, but agent is partially operational
- **UNHEALTHY** — critical failures (no SSH key, vault locked, timers inactive)

## Quality Criteria

- The snapshot includes status for all three timers: notes-sync, task-loop, and scheduler
- The snapshot includes pass/fail for all prerequisites: git repo, SSH agent, rbw vault, direnv, flake, gh CLI, fj CLI, TASKS.yaml, SCHEDULES.yaml, SOUL.md
- Each timer entry has all columns filled (state, last run, result, next run)
- The overall status accurately reflects the timer and prerequisite results

## Context

This is the first step of the doctor workflow. Its output drives all downstream analysis — if a timer or prerequisite is missed here, the later steps cannot diagnose it. Be thorough in running every check even if early checks suggest the agent is healthy.
