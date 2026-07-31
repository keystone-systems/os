# Publish Next Actions

## Objective

Produce the final operator-facing summary for the run, including the updated
note paths and the concrete next actions for today.

## Task

Summarize the state after note rollover and sync. The operator should be able to
read this file and immediately know what to do now, what is delegated, and what
remains blocked.

### Process

1. **Read prior outputs**
   - `daily_priorities.md`
   - `executive_assistant_daily.md`
   - `owner_sync_log.md`

2. **Compress to operator view**
   - Keep the summary short.
   - Highlight:
     - the top 1-3 things the human should do now
     - the delegated tasks that are already in motion
     - any blockers or missing owner repos

3. **Include updated paths**
   - Name the daily note path.
   - List mirrored owner notes that were created or changed.

4. **State what the workflow did not do**
   - If a legacy TASKS.yaml ledger exists, note that this workflow did not read
     or update it.

## Output Format

### task_loop_summary.md

```markdown
# Task Loop Summary

- **Working Date**: 2026-03-28
- **Daily Note**: /abs/path/to/human/daily-note.md

## Do Now

1. Review the investor update talking points by 2026-03-28 12:00.
2. Follow up with drago on milestone status before the 2026-03-28 14:00 meeting.

## Delegated

- drago: investor update draft mirrored at /abs/path/to/drago/notes/...

## Blockers

- luce repo missing; assigned task could not be mirrored.

## Workflow Notes

- Mirrored 1 owner note.
- Did not read or update any legacy TASKS.yaml task ledger.
```

## Quality Criteria

- The summary is short and decision-ready.
- The updated daily note path is included.
- Delegated work and blockers are explicit.
- Each Do Now item names an explicit owner and a specific deadline or time reference.

## Context

This is the final deliverable the operator reads after the run. Optimize for
clarity and actionability, not exhaustiveness.
