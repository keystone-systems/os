# Categorize Messages

## Objective

Sort all inbox messages into actionable categories based on the user's priority rules, producing a clear action plan for each message.

## Task

Review every message in the inbox snapshot and assign it to a category. Apply the user's priority rules first, then use judgment for remaining messages.

### Process

1. **Read inputs**
   - Parse inbox_snapshot.md for all messages and priority rules
   - Understand the user's priority framework

2. **Apply priority rules first**
   - Match messages against the user's explicit rules (e.g., "flag anything from investors")
   - These rules take precedence over general categorization

3. **Categorize remaining messages**
   - **Urgent**: Time-sensitive, requires immediate response (deadlines, escalations)
   - **Needs Reply**: Requires a response but not time-critical
   - **FYI**: Informational, no action needed but worth reading
   - **Archive**: Read/processed, can be archived for reference
   - **Delete**: Spam, promotions, or irrelevant messages

4. **Add action notes**
   - For "Needs Reply" messages, note what the reply should address
   - For "Urgent" messages, note the deadline or urgency reason
   - For "Archive" and "Delete", note the rationale

## Output Format

### categorized_inbox.md

Messages organized by category with action notes.

**Structure**:

```markdown
# Categorized Inbox

- **Account**: [email account]
- **Total Messages**: [count]
- **Categorization Date**: [timestamp]

## Priority Rules Applied

[Copy of rules and how they were applied]

## Urgent ([count])

### [ID]: [Subject]

- **From**: [sender]
- **Date**: [date]
- **Why Urgent**: [reason]
- **Action Needed**: [what to do]
- **Deadline**: [if applicable]

## Needs Reply ([count])

### [ID]: [Subject]

- **From**: [sender]
- **Date**: [date]
- **Reply Should Address**: [key points to cover]

## FYI ([count])

### [ID]: [Subject]

- **From**: [sender]
- **Date**: [date]
- **Summary**: [1 sentence]

## Archive ([count])

| ID   | Subject   | From     | Reason        |
| ---- | --------- | -------- | ------------- |
| [id] | [subject] | [sender] | [why archive] |

## Delete ([count])

| ID   | Subject   | From     | Reason       |
| ---- | --------- | -------- | ------------ |
| [id] | [subject] | [sender] | [why delete] |
```

## Quality Criteria

- Every message from the snapshot is categorized (no messages dropped)
- The user's priority rules are reflected in the categorization
- "Urgent" and "Needs Reply" messages have clear action notes
- Categories are reasonable — important messages are not buried in Archive/Delete
- Counts in section headers match actual message counts

## Context

This categorization drives the next two steps: drafting responses for "Needs Reply" and "Urgent" messages, and applying bulk actions (archive/delete) for the rest. Miscategorization means missed responses or deleted important messages.
