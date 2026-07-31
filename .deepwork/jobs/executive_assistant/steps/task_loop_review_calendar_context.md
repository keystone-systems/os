# Review Calendar Context

## Objective

Gather the near-term calendar events that should influence task prioritization
for the current run.

## Task

Inspect the requested calendar source and translate events into priority
signals. This workflow is calendar-first: if a meeting, deadline, or time-bound
commitment is imminent, related work should move to the top.

### Process

1. **Read the repo inventory**
   - Use `notes_repo_inventory.md` to confirm the working date and human owner.
   - Use `focus_window` when provided. Default to `today plus the next 48 hours`
     when it is omitted.

2. **Fetch calendar data**
   - Use the available calendar tooling for `calendar_source`.
   - Capture event title, start time, end time, attendees, location, and any
     notes that imply preparation work.
   - Use absolute dates and times in the output.

3. **Interpret task impact**
   - For each event, decide whether it:
     - creates urgent preparation work
     - requires follow-up on delegated work
     - creates a blocking dependency
     - is informative only
   - When an event obviously maps to a project or repo, record that link.

4. **Identify hard priority signals**
   - Elevate items such as:
     - events happening today
     - deadlines within the focus window
     - calendar entries that require a deliverable, agenda, review, or decision
   - Note free windows that could absorb focused work.

5. **Do not mutate the calendar**
   - This step is read-only. It informs prioritization but does not reschedule
     anything.

## Output Format

### calendar_context.md

```markdown
# Calendar Context

- **Working Date**: 2026-03-28
- **Calendar Source**: primary
- **Focus Window**: 2026-03-28 through 2026-03-30

## Priority Signals

### 1. Investor update review

- **When**: 2026-03-28 14:00-14:30
- **Project**: catalyst
- **Priority Impact**: promote
- **Why**: Requires updated milestone status and assigned-agent follow-up before the meeting.

### 2. Weekly planning block

- **When**: 2026-03-29 09:00-10:00
- **Priority Impact**: monitor
- **Why**: Good slot for backlog review if urgent prep work is already done.

## Free Windows

- 2026-03-28 10:30-12:00
- 2026-03-28 15:00-17:00

## Summary

- Today's strongest driver is the investor update review at 2026-03-28 14:00.
- No other event should outrank preparation for that meeting.
```

## Quality Criteria

- Every cited event uses an absolute date and time.
- The report explains how each important event changes work priority.
- Informational events are distinguished from urgent preparation items.

## Context

This step provides the calendar-first weighting used by the priority synthesis
step. It should stay concise and operational.
