# Finalize Event Plan

## Objective

Review the draft event plan with the user, incorporate their feedback, and produce the final approved plan ready for execution.

## Task

Present the draft plan to the user, gather feedback on each section, and produce a final version with all decisions locked in and no remaining open questions.

### Process

1. **Present the draft**
   - Read event_plan.md from the previous step
   - Summarize key decisions and ask the user to review

2. **Gather feedback**
   - Ask structured questions about each major section:
     - Is the venue selection acceptable?
     - Any changes to the agenda?
     - Catering adjustments?
     - Invitation text revisions?
     - Budget concerns?
   - Use the AskUserQuestion tool for clear, structured feedback collection

3. **Incorporate changes**
   - Update all sections based on feedback
   - Resolve any open questions from the draft
   - Ensure all decisions are final (no "Option A or B" — pick one)

4. **Add execution checklist**
   - Convert the timeline into a concrete checklist with checkboxes
   - Assign owners where possible
   - Add dates as absolute dates (not relative)

## Output Format

### final_event_plan.md

The finalized, approved event plan.

**Structure**:

```markdown
# Final Event Plan: [Event Name]

**Status**: Approved
**Approved Date**: [date]

## Event Summary

- **What**: [event description]
- **When**: [confirmed date and time]
- **Where**: [confirmed venue with address]
- **Who**: [attendee count and key attendees]
- **Budget**: [confirmed total budget]

## Venue

[Final venue details — no alternatives, just the decision]

## Catering

[Final catering plan]

## Agenda

[Final time-blocked agenda]

## Logistics

[Final logistics plan]

## Budget

| Category  | Amount |
| --------- | ------ |
| [item]    | $X     |
| **Total** | **$X** |

## Invitation

[Final invitation text]

## Execution Checklist

- [ ] [Task] — by [date] — [owner]
- [ ] [Task] — by [date] — [owner]
```

## Quality Criteria

- The plan contains clear decisions (not options) for every logistics item
- A checklist of next actions with owners and deadlines is included
- All open questions from the draft are resolved
- Budget total is confirmed and within range
- Invitation text is finalized and ready to send

## Context

This is the final deliverable of the event planning workflow. After this step, the plan transitions from planning to execution. Every item should be actionable with no ambiguity.
