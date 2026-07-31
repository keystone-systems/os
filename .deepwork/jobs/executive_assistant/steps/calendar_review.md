# Review Calendar

## Objective

Fetch and document all calendar entries for the specified time range, producing a clear snapshot of the current schedule.

## Task

Access the specified calendar source and retrieve all entries within the requested time range. Produce a structured snapshot that can be analyzed for conflicts and optimization.

### Process

1. **Understand the request**
   - Read the time range and calendar source inputs
   - If the calendar source is unclear, ask structured questions to clarify which calendar account or tool to use (e.g., Google Calendar via API, local calendar file, etc.)

2. **Fetch calendar entries**
   - Use available calendar tools or APIs to retrieve entries in the time range
   - For each entry capture: title, date/time, duration, location, attendees, status
   - Note recurring events vs. one-time events

3. **Organize the snapshot**
   - Sort entries chronologically
   - Group by day for readability
   - Flag entries that appear problematic (no title, very long blocks, etc.)

4. **Document gaps and availability**
   - Note blocks of free time
   - Identify the overall utilization level for the period

## Output Format

### calendar_snapshot.md

A complete snapshot of the calendar for the specified period.

**Structure**:

```markdown
# Calendar Snapshot

- **Account**: [calendar source]
- **Period**: [start date] to [end date]
- **Total Entries**: [count]
- **Generated**: [timestamp]

## Schedule

### [Day, Date]

| Time     | Duration | Event        | Location | Attendees  |
| -------- | -------- | ------------ | -------- | ---------- |
| 9:00 AM  | 1h       | Team Standup | Zoom     | Alice, Bob |
| 11:00 AM | 30m      | 1:1 with CEO | Office   | Nicholas   |

**Free blocks**: 10:00-11:00, 11:30-1:00, 3:00-5:00

### [Next Day, Date]

[same structure]

## Summary

- **Busiest day**: [day]
- **Most free time**: [day]
- **Recurring events**: [list]
- **Observations**: [anything notable]
```

## Quality Criteria

- All entries in the time range are captured
- Each entry has complete details (time, duration, title, attendees where available)
- Entries are sorted chronologically and grouped by day
- Free time blocks are identified
- The snapshot is accurate — entries match the actual calendar

## Context

This snapshot is the foundation for calendar analysis. Accurate, complete data here ensures the conflict identification step can make reliable recommendations. Missing or incomplete entries lead to missed conflicts.
