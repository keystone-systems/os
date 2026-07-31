# Analyze Logs

## Objective

Fetch and parse recent logs from all agent services, extracting errors, warnings, and failure patterns.

## Inputs

- `health_snapshot.md` from the `check_health` step — use this to know which agent and which services need log analysis. Focus deeper analysis on services marked as failed or degraded.

## Task

### 1. Read the health snapshot

Parse the agent name and identify which timers/services had failures or issues.

### 2. Fetch journalctl logs

For each of the three services (see common job info for timer names), fetch the last 100 lines. Use `journalctl --user` when running as the agent user, or `agentctl journalctl` when running as root.

```bash
# As agent user:
journalctl --user -u agent-${agent_name}-notes-sync -n 100 --no-pager
journalctl --user -u agent-${agent_name}-task-loop -n 100 --no-pager
journalctl --user -u agent-${agent_name}-scheduler -n 100 --no-pager
```

### 3. Fetch file-based logs

Check for recent log files in the state directories listed in common job info. Read the most recent log file from each directory that had failures in the health snapshot.

### 4. Extract and classify log entries

For each service, extract:

- **Errors** — lines containing `error`, `Error`, `ERROR`, `FATAL`, `panic`, non-zero exit codes
- **Warnings** — lines containing `warn`, `Warning`, `WARN`, `timeout`, `retry`
- **Structured tags** — extract phase/task identifiers from structured log tags
- **Timestamps** — when errors first appeared and whether they're recurring

### 5. Identify patterns

Look for:

- **Recurring errors** — same error appearing across multiple runs
- **Cascading failures** — one service failure causing downstream failures (e.g., notes-sync failure blocking task-loop)
- **Time correlation** — errors that started at a specific time (suggests external change)
- **Resource issues** — timeout messages, memory errors, disk space warnings

## Output Format

Write `log_analysis.md` with this structure:

```markdown
# Log Analysis: agent-{name}

**Analysis Date:** {timestamp}
**Log Window:** last 100 journal entries per service + recent log files

## {Service Name}

### Errors

- {timestamp} — {error message}
- ...

### Warnings

- ...

### Recent Task Failures

| Task | Step | Error | Timestamp |
| ---- | ---- | ----- | --------- |
| ...  | ...  | ...   | ...       |

### Pattern: {pattern name}

{description of recurring pattern}

{Repeat for each service}

## Cross-Service Patterns

- {any correlations between services}

## Summary

- Total errors found: {N}
- Services with errors: {list}
- Earliest error: {timestamp}
- Most frequent error: {description} (seen {N} times)
```

If a service has no errors or warnings, note it as clean: "No errors or warnings in the analyzed log window."

## Quality Criteria

- Every service marked as failed or degraded in the health snapshot has corresponding log entries extracted
- Actual error messages are quoted from logs, not paraphrased or summarized without evidence
- Log entries include timestamps for temporal correlation
- The summary section accurately counts and categorizes findings

## Context

This step bridges raw status checks and root cause analysis. The diagnose step depends on having real log evidence to work with — vague summaries like "some errors found" are not actionable. Always quote the actual log lines.
