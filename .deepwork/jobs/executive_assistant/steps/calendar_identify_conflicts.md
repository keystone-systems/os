# Identify Conflicts

## Objective

Analyze the calendar snapshot to find conflicts, double-bookings, scheduling inefficiencies, and suggest specific resolutions.

## Task

Review the calendar snapshot systematically for issues and optimization opportunities. Produce actionable suggestions, not just a list of problems.

### Process

1. **Read the calendar snapshot**
   - Parse all entries from calendar_snapshot.md
   - Build a mental model of the schedule

2. **Identify conflicts**
   - Double-bookings: two events at the same time
   - Tight transitions: back-to-back meetings with no buffer
   - Overloaded days: too many meetings leaving no focus time
   - Location conflicts: physically impossible transitions (e.g., two in-person meetings across town 15 minutes apart)

3. **Identify optimization opportunities**
   - Meetings that could be consolidated or shortened
   - Days that could benefit from meeting-free blocks
   - Recurring meetings that could be rescheduled for better flow

4. **Propose specific resolutions**
   - For each conflict, suggest a concrete fix: reschedule, cancel, combine, add buffer
   - Provide alternative time slots when suggesting reschedules
   - Prioritize: which conflicts are urgent vs. nice-to-fix

## Output Format

### calendar_analysis.md

Analysis of conflicts and suggested changes.

**Structure**:

```markdown
# Calendar Analysis

- **Period Analyzed**: [date range]
- **Conflicts Found**: [count]
- **Optimizations Suggested**: [count]

## Conflicts

### Conflict 1: [Brief Description]

- **Type**: [double-booking / tight transition / overload / location conflict]
- **Events**: [event A] vs. [event B]
- **When**: [date and time]
- **Severity**: [high / medium / low]
- **Suggested Resolution**: [specific action to take]
- **Alternative Slot**: [proposed new time if rescheduling]

### Conflict 2: [Brief Description]

[same structure]

## Optimization Suggestions

### Suggestion 1: [Brief Description]

- **Current State**: [what it looks like now]
- **Proposed Change**: [what to do]
- **Benefit**: [why this helps]

## Proposed Changes Summary

| #   | Action     | Event   | Current Time | New Time   | Status  |
| --- | ---------- | ------- | ------------ | ---------- | ------- |
| 1   | Reschedule | [event] | [old time]   | [new time] | Pending |
| 2   | Cancel     | [event] | [time]       | —          | Pending |
| 3   | Add buffer | [event] | [time]       | [adjusted] | Pending |
```

## Quality Criteria

- All identified conflicts correspond to actual overlapping entries in the snapshot
- Suggested resolutions are specific and actionable (not "consider rescheduling" but "move to Tuesday 2pm")
- Severity levels are reasonable — double-bookings are high, nice-to-haves are low
- The proposed changes summary table provides a clear action plan

## Context

This analysis feeds directly into the update step, where changes will be applied. Clear, specific recommendations reduce back-and-forth and ensure the right changes are made.
