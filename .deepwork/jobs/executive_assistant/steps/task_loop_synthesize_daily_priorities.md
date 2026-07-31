# Synthesize Daily Priorities

## Objective

Turn calendar pressure, active task notes, and agent activity into a single
ranked plan for the working day.

## Task

Produce a calendar-first priority list. Upcoming meetings, deadlines, and time-
bound commitments outrank nominal project ordering when they conflict.

### Process

1. **Read all inputs**
   - `calendar_context.md`
   - `active_task_notes.md`
   - `agent_activity.md`

2. **Build the Eisenhower matrix**

   Map every active project and open work item across the four quadrants:

   | | **Urgent** | **Not Urgent** |
   |---|---|---|
   | **Important** | Q1 — Do Now | Q2 — Schedule |
   | **Not Important** | Q3 — Delegate | Q4 — Icebox |

   - **Urgent**: has a calendar event, an imminent deadline, or is blocking an
     agent or human today
   - **Important**: directly advances a milestone, unblocks downstream work, or
     is aligned with the CEO's stated goals
   - Use project stats (open issues, last merge date, milestone state) from
     `active_task_notes.md` to inform the judgment — a project with no recent
     activity and no milestone may belong in Q4

3. **Apply the ranking policy**
   - Rank work in this order:
     1. Q1 (Do Now): calendar events + milestone-critical blockers
     2. Q2 (Schedule): important work with no immediate deadline — assign a date
     3. Q3 (Delegate): urgent but not important — assign to drago or luce now
     4. Q4 (Icebox): everything else — dispose gracefully (see step 5)

4. **Choose actions, not just status**
   - For each ranked item, specify:
     - owner
     - next action
     - why it is ranked here
     - whether it should be carried into the daily note

5. **Handle Q4 and low-priority work explicitly**

   Do not leave Q4 items as silent backlog. For each one, pick a disposal path:

   - **Defer** (Q2 boundary): important but genuinely not ready — add to a
     future milestone with a target date. Close any open issues and reopen under
     the future milestone.
   - **Delegate** (Q3 boundary): someone should do it, but not the CEO — assign
     to drago (engineering execution) or luce (product/scoping). Create a task
     note with `assigned_agent`.
   - **Icebox**: not ready and not worth scheduling — apply an `icebox` label on
     GitHub (create it if absent), unassign, remove from milestone, and leave a
     comment explaining why. Record the icebox action in the daily note.
   - **Delete**: truly irrelevant — close the issue as "not planned" with a
     brief explanation. No need to track further.

   The goal is a clean active surface. Every item that remains open should have
   a clear owner and a reason to exist today.

6. **Separate blocked and waiting work**
   - Items waiting on another person, another agent, or an external event should
     remain visible but should not crowd out immediate execution items.

7. **Decide carry-forward set**
   - Identify unfinished items from prior context that should remain active today.
   - Identify items that should stay linked for context but not be actively
     carried forward.

## Output Format

### daily_priorities.md

```markdown
# Daily Priorities

- **Working Date**: 2026-03-28

## Eisenhower Matrix

| | Urgent | Not Urgent |
|---|---|---|
| **Important** | Q1 — Do Now: investor update prep, keystone#175 review | Q2 — Schedule: meze milestone planning (2026-04-07) |
| **Not Important** | Q3 — Delegate: plant-caravan#44 → drago | Q4 — Icebox: trading research spike |

## Ranked Priorities

### Q1 — Do Now

1. **Prepare investor update**
   - **Owner**: ncrmro
   - **Next Action**: Review drago's milestone draft and finalize talking points by 2026-03-28 12:00.
   - **Why Now**: Supports calendar event at 2026-03-28 14:00.
   - **Carry Forward**: yes

### Q2 — Schedule

2. **Meze milestone planning**
   - **Owner**: ncrmro
   - **Next Action**: Create first milestone after meze#643 merges. Target: 2026-04-07.
   - **Why Now**: No milestone exists; last merge was 5 weeks ago.
   - **Carry Forward**: yes

### Q3 — Delegate

3. **Plant Caravan Phase 2 start (plant-caravan#44)**
   - **Owner** → drago
   - **Next Action**: Assign drago on GitHub; create task note with assigned_agent: drago.
   - **Why Now**: Work is defined; CEO doesn't need to execute this.

### Q4 — Icebox

4. **Trading research spike**
   - **Disposal**: icebox
   - **Action**: Apply `icebox` label on GitHub, remove from milestone, comment "parking until Q3 2026".

## Waiting / Blocked

- **Update legal review note**
  - **Status**: waiting
  - **Reason**: Waiting on external counsel response expected 2026-03-29.
```

## Quality Criteria

- Calendar-critical work is ranked above lower-urgency backlog.
- Every ranked item has an owner and a concrete next action.
- Blocked and waiting work stays visible but separate from immediate execution.
- An Eisenhower matrix is present and maps all active projects to quadrants.
- Every Q4 item has an explicit disposal action (defer, delegate, icebox, or delete).

## Context

This file becomes the decision engine for the daily note and the sync step. It
must be concise, concrete, and operator-ready.
