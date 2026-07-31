# Apply Inbox Actions

## Objective

Execute all inbox actions: send approved replies, archive messages, delete spam, and flag important items. Log every action taken.

## Task

Using the categorized inbox and draft replies, apply all planned actions. This step has side effects (sending emails, deleting messages), so confirm with the user before proceeding.

### Process

1. **Read inputs**
   - Parse categorized_inbox.md for archive/delete lists
   - Parse draft_replies.md for approved reply drafts

2. **Present action plan for approval**
   - Show the user a summary of all actions about to be taken:
     - Number of replies to send
     - Number of messages to archive
     - Number of messages to delete
   - Ask structured questions to confirm:
     - Are all reply drafts approved? Any edits needed?
     - Approve archive list?
     - Approve delete list?
   - Do NOT proceed without explicit user approval

3. **Send approved replies**
   - Use `himalaya message send` or `himalaya message reply` for each approved draft
   - Log each send with recipient and status

4. **Archive messages**
   - Use `himalaya message move` to move messages to archive folder
   - Log each archive action

5. **Delete messages**
   - Use `himalaya message delete` to remove spam/irrelevant messages
   - Log each deletion

6. **Flag important messages**
   - Use `himalaya flag add` for messages that need follow-up
   - Log flagging actions

## Output Format

### inbox_actions_log.md

Complete log of all actions taken.

**Structure**:

```markdown
# Inbox Actions Log

- **Date**: [timestamp]
- **Replies Sent**: [count]
- **Messages Archived**: [count]
- **Messages Deleted**: [count]
- **Messages Flagged**: [count]

## Replies Sent

| ID   | To      | Subject   | Status        |
| ---- | ------- | --------- | ------------- |
| [id] | [email] | [subject] | [sent/failed] |

## Messages Archived

| ID   | Subject   | From     | Reason     |
| ---- | --------- | -------- | ---------- |
| [id] | [subject] | [sender] | [category] |

## Messages Deleted

| ID   | Subject   | From     | Reason            |
| ---- | --------- | -------- | ----------------- |
| [id] | [subject] | [sender] | [spam/irrelevant] |

## Messages Flagged

| ID   | Subject   | Flag Reason        |
| ---- | --------- | ------------------ |
| [id] | [subject] | [follow-up needed] |

## Errors

[Any failed actions with details]

## Summary

- **Inbox before**: [count] messages
- **Inbox after**: [estimated count]
- **Time saved**: [rough estimate]
```

## Quality Criteria

- Every action taken is logged with message ID and result
- Only messages categorized as delete were deleted; important messages were preserved
- User approval was obtained before executing any actions
- Failed actions are documented with error details
- The summary provides a clear before/after picture

## Context

This is the action step of the inbox workflow. Sending emails and deleting messages are irreversible, so user confirmation is essential. The log ensures accountability and allows the user to verify what happened.
