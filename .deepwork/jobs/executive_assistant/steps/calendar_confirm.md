# Confirm Calendar

## Objective

Verify that all planned calendar changes were applied correctly and produce a final summary of the calendar's state.

## Task

Cross-reference the changes log against the actual calendar to confirm everything is in order. Produce a clean summary of the final calendar state.

### Process

1. **Read the changes log**
   - Parse calendar_changes.md for all changes that were applied
   - Note any that failed or were skipped

2. **Verify changes**
   - Re-check the calendar to confirm each change took effect
   - Verify invitation delivery where possible
   - Flag any discrepancies between planned and actual state

3. **Produce final summary**
   - Show the updated calendar for the period
   - Highlight what changed from the original snapshot
   - Note any remaining issues or follow-up items

## Output Format

### calendar_summary.md

Final calendar summary confirming all changes are in place.

**Structure**:

```markdown
# Calendar Summary

- **Period**: [date range]
- **Changes Verified**: [count of count]
- **Status**: [all clear / issues remaining]

## Verification Results

| #   | Change        | Expected         | Actual         | Verified |
| --- | ------------- | ---------------- | -------------- | -------- |
| 1   | [description] | [expected state] | [actual state] | [yes/no] |

## Updated Schedule

### [Day, Date]

| Time    | Duration | Event        | Status          |
| ------- | -------- | ------------ | --------------- |
| 9:00 AM | 1h       | Team Standup | unchanged       |
| 2:00 PM | 30m      | 1:1 with CEO | **rescheduled** |

[Repeat for each day in the period]

## Remaining Items

- [Any follow-up actions needed]
- [Any failed changes that need manual attention]

## Summary

[1-2 sentences confirming the calendar is in order or noting issues]
```

## Quality Criteria

- All planned changes from the analysis are accounted for in verification
- The summary gives a clear picture of the calendar's final state
- Discrepancies are flagged with explanations
- Changed entries are visually distinguished from unchanged ones

## Context

This confirmation step closes the loop on the calendar management workflow. It ensures no changes were lost and gives the user confidence that their calendar is accurate.
