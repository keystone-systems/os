# Update and Invite

## Objective

Apply the approved calendar changes and send meeting invitations, logging every action taken.

## Task

Execute the changes proposed in the calendar analysis. This step involves side effects (modifying calendar entries, sending invitations), so proceed carefully and log everything.

### Process

1. **Review proposed changes**
   - Read calendar_analysis.md for the list of changes to make
   - Confirm each change is still valid and desired

2. **Present changes for approval**
   - Before making any changes, present the full list of proposed actions to the user
   - Ask structured questions if any changes need user confirmation
   - Do NOT proceed with changes the user has not approved

3. **Apply calendar changes**
   - For each approved change:
     - Execute the change (reschedule, cancel, add buffer)
     - Log the result (success/failure)
     - Note any issues or warnings
   - Use available calendar tools or APIs

4. **Send invitations**
   - For new or rescheduled meetings, draft and send invitations
   - Include: event title, date/time, location, agenda/notes
   - Use himalaya or appropriate email tool for email-based invitations
   - Log each invitation sent with recipient and status

5. **Document all actions**
   - Create a complete log of every action taken
   - Include before/after state for each change

## Output Format

### calendar_changes.md

A log of all changes made and invitations sent.

**Structure**:

```markdown
# Calendar Changes Log

- **Date**: [when changes were applied]
- **Changes Applied**: [count]
- **Invitations Sent**: [count]

## Changes Applied

### Change 1: [Brief Description]

- **Action**: [reschedule / cancel / create / modify]
- **Event**: [event name]
- **Before**: [original time/details]
- **After**: [new time/details]
- **Status**: [success / failed / skipped]
- **Notes**: [any issues or comments]

### Change 2: [Brief Description]

[same structure]

## Invitations Sent

| Recipient | Event   | Date/Time | Method           | Status        |
| --------- | ------- | --------- | ---------------- | ------------- |
| [email]   | [event] | [when]    | [email/calendar] | [sent/failed] |

## Summary

- **Successful changes**: [count]
- **Failed changes**: [count with reasons]
- **Pending items**: [anything that still needs attention]
```

## Quality Criteria

- Every change logged corresponds to a suggestion from the calendar analysis
- All invitations sent are logged with recipient and confirmation status
- No calendar entries were modified or deleted beyond what was planned
- Failed actions are clearly documented with reasons
- User approval was obtained before executing changes

## Context

This is the action step of the calendar workflow. Changes here are real and potentially irreversible (invitations sent, meetings canceled). Accuracy and user confirmation are critical.
