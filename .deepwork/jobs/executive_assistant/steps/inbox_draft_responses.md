# Draft Responses

## Objective

Draft professional replies for all messages categorized as "Urgent" or "Needs Reply," ready for the user to review and approve before sending.

## Task

For each message that needs a response, read the full message content and draft an appropriate reply. All drafts are for review only — nothing is sent in this step.

### Process

1. **Read categorized inbox**
   - Parse categorized_inbox.md for messages in "Urgent" and "Needs Reply" categories
   - Note the action guidance for each message

2. **Read full message content**
   - For each message needing a reply, use `himalaya message read [ID]` to get the full content
   - Understand the context, question, or request

3. **Draft replies**
   - Write a professional, concise reply for each message
   - Address the specific points raised in the original message
   - Match the tone to the relationship (formal for external contacts, casual for close colleagues)
   - Include clear next steps or answers
   - Keep replies short — aim for 3-5 sentences unless the topic requires more

4. **Flag uncertain drafts**
   - If you're unsure about the right response, note it and suggest the user write this one manually
   - If the message requires information you don't have, note what's needed

## Output Format

### draft_replies.md

All draft replies, organized by urgency.

**Structure**:

```markdown
# Draft Replies

- **Total Drafts**: [count]
- **Drafts Needing Review**: [count — all of them, since none should be sent without review]

## Urgent Replies

### Reply to: [Subject] (ID: [id])

- **To**: [recipient email]
- **Original From**: [sender]
- **Original Date**: [date]
- **Context**: [1-sentence summary of what they asked/said]

**Draft**:

> [Full draft reply text]

**Notes**: [Any caveats, missing info, or suggestions for the user]

---

## Standard Replies

### Reply to: [Subject] (ID: [id])

- **To**: [recipient email]
- **Context**: [1-sentence summary]

**Draft**:

> [Full draft reply text]

**Notes**: [Any caveats]

---

## Skipped (Manual Reply Recommended)

### [Subject] (ID: [id])

- **Reason**: [Why this needs manual handling — e.g., requires information only the user has]
```

**Example draft**:

```markdown
### Reply to: Q1 Budget Review (ID: 142)

- **To**: alice@example.com
- **Context**: Alice asked for budget review before Thursday meeting

**Draft**:

> Hi Alice,
>
> Thanks for sending over the Q1 budget. I've reviewed it and have a few questions
> about the marketing line items — can we discuss those in Thursday's meeting?
>
> Best,
> Nicholas

**Notes**: User should verify the marketing concerns are accurate before sending.
```

## Quality Criteria

- All drafts use professional, concise language appropriate for the recipient
- Each draft addresses the sender's question or request with a clear next step
- Urgent replies are prioritized at the top
- Messages requiring manual handling are clearly flagged with reasons
- No draft is sent — all are for review only

## Context

These drafts save the user time by handling routine responses. The quality bar is "good enough to send with minor edits." Drafts that the user has to rewrite from scratch defeat the purpose.
