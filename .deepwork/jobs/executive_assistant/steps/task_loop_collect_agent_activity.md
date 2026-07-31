# Collect Agent Activity

## Objective

Summarize what each participating agent owner is actively working on and how
that maps back to task notes in the notes repos.

Use `shared/task_note_frontmatter.md` as the reference shape for owner mirrors
and shared-surface fields.

## Task

Inspect owner notes repos and live zellij session state to build a single view
of delegated work, stale assignments, blockers, and missing mirrors.

### Process

1. **Read prior context**
   - Use `notes_repo_inventory.md` for owner roles and paths.
   - Use `active_task_notes.md` for the current task inventory.

2. **Run the zellij fleet survey**

   This is the fastest way to see what agents are actually doing right now.
   Run it first — it takes seconds and often reveals activity not yet in notes.

   ```bash
   # Step 1 — list active (non-EXITED) sessions
   zellij list-sessions 2>/dev/null | grep -v EXITED

   # Step 2 — dump every active session's focused pane in parallel
   for session in <active_session_names>; do
     zellij --session "$session" action dump-screen /tmp/zellij-dump-${session}.txt
   done

   # Step 3 — read each dump to see what the pane contains
   ```

   **Interpreting the output:**
   - A Claude Code prompt (`❯`) with no running tool → agent is idle
   - An active tool call or `✳ Embellishing…` line → agent is working
   - A shell prompt → no agent running in that pane
   - DeepWork MCP tool call JSON → identifies exactly which job/step/workflow
   - `agentctl <owner> claude` line → you can see which agent was launched

   **Limitations:**
   - `dump-screen` captures only the **focused pane** of each session.
   - For multi-pane sessions, use `zellij --session <name> action dump-layout`
     first to understand the pane structure, then target accordingly.
   - Session names are often named after the project being worked on
     (e.g., `keystone-tui`, `catalyst`, `plant-caravan`), which gives context
     before you even read the dump.

3. **Check owner-specific task mirrors**
   - For each agent owner repo that exists:
     - search for notes assigned to that owner
     - identify mirrored task notes that correspond to the human repo's task set
     - note whether the mirror is current, missing, or stale
   - Cross-reference with zellij session names — an idle agent whose session
     name matches a project repo is a strong signal the agent is waiting for work.

4. **Classify delegated work**
   - For each active assignment, record:
     - task note path
     - assigned owner
     - last visible progress signal (from notes git log or zellij dump)
     - blocker status
     - whether follow-up is needed today

5. **Flag missing mirrors or drift**
   - Note tasks assigned to an owner that do not yet have a mirror note in that
     owner's repo.
   - Note owner repos that have local task notes with no human coordination
     backlink.

## Output Format

### agent_activity.md

```markdown
# Agent Activity

## Fleet Survey

| Session | Status | Summary |
|---------|--------|---------|
| keystone-tui | idle | drago at Claude Code prompt (Opus 4.6), no active task |
| catalyst | idle | empty pane |
| unsupervised-deepwork-frontend | active | agent running deepwork/learn on mech_engineer job, step 3m 28s |

## Owner Status

### drago

- **Notes Repo**: /abs/path/to/drago/notes
- **Active Session**: keystone-tui (idle at prompt)
- **Assigned Tasks**: 2
- **Needs Follow-Up Today**: yes

#### Active Items

1. **Prepare investor update**
   - **Human Note**: /abs/path/to/ncrmro/notes/...
   - **Owner Mirror**: /abs/path/to/drago/notes/...
   - **Last Signal**: Updated 2026-03-28 08:10 with milestone status draft.
   - **Status**: in progress
   - **Blocker**: none

### luce

- **Notes Repo**: /abs/path/to/luce/notes
- **Active Session**: none found
- **Assigned Tasks**: 0
- **Needs Follow-Up Today**: no

## Drift

- Task `prepare-investor-update` has a human note but no mirror in luce's repo.
```

## Quality Criteria

- Every participating agent owner gets an explicit status.
- Delegated tasks map back to concrete note paths when available.
- Missing mirrors and stale assignments are called out directly.

## Context

The daily priority step needs a clear view of delegated work so it can decide
whether to follow up, reassign, or leave the task alone.
