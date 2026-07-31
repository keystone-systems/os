# Send Status Email

## Objective

Send the composed status digest email to the human operator using himalaya.

## Task

Read the draft email body from status_draft.md (produced by the gather_status step) and send it to the human operator.

### Process

1. **Read the draft**
   - Read status_draft.md from the gather_status step

2. **Send the email**
   - Read SOUL.md for the agent's name and email (From address)
   - Read HUMAN.md for the recipient's email (To address)
   - Follow the himalaya email convention from the common job info
   - Subject line: `Daily Status - YYYY-MM-DD` (today's date)
   - Body: contents of status_draft.md

3. **Write confirmation**
   - Record whether the send succeeded or failed in send_confirmation.md
   - If it failed, include the error output

## Output Format

### send_confirmation.md

**Structure (success)**:

```markdown
# Send Confirmation

**Status**: Sent
**To**: [recipient from HUMAN.md]
**Subject**: Daily Status - [YYYY-MM-DD]
**Sent at**: [timestamp]
```

**Structure (failure)**:

```markdown
# Send Confirmation

**Status**: Failed
**To**: [recipient from HUMAN.md]
**Subject**: Daily Status - [YYYY-MM-DD]
**Error**: [error message from himalaya]
```

## Quality Criteria

- Email was sent using the himalaya pipe-stdin convention
- Confirmation file accurately reflects the send outcome
- Subject line includes today's date

## Context

This is the final step. The email has already been composed and reviewed for accuracy in gather_status. This step handles delivery only.
