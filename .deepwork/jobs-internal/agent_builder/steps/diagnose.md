# Diagnose Issues

## Objective

Correlate the health snapshot and log analysis to identify root causes of each failure. Produce a structured diagnosis for each issue.

## Inputs

- `health_snapshot.md` from `check_health` — current state of timers, prerequisites, git, locks
- `log_analysis.md` from `analyze_logs` — extracted errors, warnings, and patterns

## Task

### 1. Cross-reference health and logs

For each issue in the health snapshot's "Issues Found" section, find the corresponding log evidence. For each error pattern in the log analysis, check whether the health snapshot explains the symptom.

### 2. Apply the diagnostic decision tree

For each issue, walk through this decision tree to identify the root cause:

**Timer inactive/failed:**

- Is the service unit file present? → NixOS config may not have been applied
- Did it fail with exit code? → Check the specific error in logs
- Is it masked or disabled? → Intentional or accidental `systemctl mask`

**Auth failures (gh/fj/rbw):**

- Token expired? → Needs re-authentication (credential rotation)
- Wrong username? → SOUL.md mismatch
- Network unreachable? → DNS or firewall issue
- Vault locked? → rbw needs unlock (session expired)

**Git/sync failures:**

- Rebase conflict? → Manual conflict resolution needed
- Permission denied? → SSH key not loaded or not authorized
- Remote not found? → Forgejo repo deleted or renamed

**Task loop failures:**

- Flock held? → Previous run still active or zombie process
- Timeout? → Task took >1h, may need `maxTasks` reduction
- Step failure? → Specific task error (check per-task logs)

**Scheduler failures:**

- YAML parse error? → Malformed SCHEDULES.yaml
- No tasks created? → Schedule conditions not matching (check day/date logic)

### 3. Classify each issue

For each diagnosed issue, assign:

- **Severity:** critical (agent non-functional), warning (degraded), info (cosmetic)
- **Category:** auth, git, timer, config, resource, task
- **Affected components:** which timers/services are impacted
- **Root cause:** the underlying reason (not the symptom)
- **Evidence:** specific log lines or status output supporting the diagnosis

## Output Format

Write `diagnosis.md`:

```markdown
# Diagnosis: agent-{name}

**Date:** {timestamp}
**Overall Assessment:** {summary sentence}

## Issues

### Issue 1: {descriptive title}

- **Severity:** critical / warning / info
- **Category:** auth / git / timer / config / resource / task
- **Affected:** {components}
- **Symptom:** {what was observed in health check / logs}
- **Root Cause:** {underlying reason}
- **Evidence:**
  - {specific log line or status output}
  - {another piece of evidence}

### Issue 2: {title}

...

## Dependency Graph

{If issues are related, describe the chain. E.g.: "SSH key not loaded → notes-sync fails → task-loop can't fetch → stale TASKS.yaml"}

## No Issues Found

{If the agent is healthy, state: "No issues detected. All timers active, all prerequisites passing, no errors in recent logs."}
```

## Quality Criteria

- Every failure from the health snapshot has a corresponding diagnosis entry
- Each issue has a plausible root cause, not just a symptom restatement
- Evidence includes specific log lines or status outputs from the prior steps
- The dependency graph captures cascading failure chains when present

## Context

This step synthesizes the health snapshot and log analysis into actionable root causes. The prescribe step depends on accurate diagnoses — a wrong root cause leads to wrong fixes. When uncertain, state the uncertainty and list alternative causes.
