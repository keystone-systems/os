# Fetch Messages

## Objective

Retrieve messages from the specified inbox and produce a structured snapshot for categorization and action.

## Task

Use the himalaya CLI to fetch messages from the user's inbox. Produce a clean, parseable snapshot of all messages in the specified time range.

### Process

1. **Understand the request**
   - Read the inbox account, time range, and priority rules inputs
   - Determine which himalaya account and folder to query

2. **Fetch messages**
   - Use `himalaya envelope list` to retrieve message envelopes for the time range
   - For each message, capture: ID, sender, subject, date, flags (read/unread/flagged)
   - For messages that look important based on priority rules, fetch a brief preview using `himalaya message read`

3. **Produce the snapshot**
   - List all messages with metadata
   - Note the total count, unread count, and flagged count
   - Include the user's priority rules in the snapshot for the next step

## Output Format

### inbox_snapshot.md

A structured list of all messages in the inbox for the period.

**Structure**:

```markdown
# Inbox Snapshot

- **Account**: [email account]
- **Period**: [time range]
- **Total Messages**: [count]
- **Unread**: [count]
- **Flagged**: [count]
- **Fetched**: [timestamp]

## Priority Rules

[Copy of user's priority rules for reference by categorization step]

## Messages

### [ID]: [Subject]

- **From**: [sender name <email>]
- **Date**: [date and time]
- **Status**: [unread/read/flagged]
- **Preview**: [first 1-2 sentences if available]

### [ID]: [Subject]

[same structure, repeat for all messages]

## Quick Stats

- **Top senders**: [list of most frequent senders]
- **Threads**: [any notable multi-message threads]
```

**Example**:

```markdown
### 142: Q1 Budget Review

- **From**: Alice Chen <alice@example.com>
- **Date**: 2026-03-18 14:30
- **Status**: unread
- **Preview**: Hi team, please review the attached Q1 budget before our meeting Thursday...
```

## Quality Criteria

- All messages in the time range are captured
- Each message has complete metadata (ID, sender, subject, date, status)
- Priority rules are preserved for the categorization step
- Messages are sorted by date (newest first)
- Counts are accurate

## Context

This snapshot feeds the categorization step. Complete, accurate metadata ensures messages are correctly prioritized. The himalaya CLI is the primary tool for email access.
