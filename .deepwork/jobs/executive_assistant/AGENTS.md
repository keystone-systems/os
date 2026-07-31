# Job Management

This folder and its subfolders are managed using `deepwork_jobs` workflows.

## Recommended Workflows

- `deepwork_jobs/new_job` - Full lifecycle: define → implement → test → iterate
- `deepwork_jobs/learn` - Improve instructions based on execution learnings
- `deepwork_jobs/repair` - Clean up and migrate from prior DeepWork versions

## Directory Structure

```
.
├── .deepreview        # Review rules for the job itself using Deepwork Reviews
├── AGENTS.md          # This file - project context and guidance
├── job.yml            # Job specification (created by define step)
├── steps/             # Step instruction files (created by implement step)
│   └── *.md           # One file per step
├── hooks/             # Custom validation scripts and prompts
│   └── *.md|*.sh      # Hook files referenced in job.yml
├── scripts/           # Reusable scripts and utilities created during job execution
│   └── *.sh|*.py      # Helper scripts referenced in step instructions
└── templates/         # Example file formats and templates
    └── *.md|*.yml     # Templates referenced in step instructions
```

## Editing Guidelines

1. **Use workflows** for structural changes (adding steps, modifying job.yml)
2. **Direct edits** are fine for minor instruction tweaks

## Job-Specific Context

### Primary interface

- `executive_assistant/task_loop` is the primary entrypoint for new work that
  needs cross-project coordination.
- Use the other workflows when the task is narrowly about event planning,
  inbox cleanup, calendar edits, event discovery, or portfolio review.
- Presentation work now lives in the standalone `presentation` job. Do not add
  `presentation` or `slide_deck` workflows back into this job.

## Last Updated

- 2026-03-30: Split presentation workflows into `.deepwork/jobs/presentation/`
  so executive assistant remains focused on operator coordination tasks.

### Notes model

- This job uses zk notes as the source of truth for task coordination.
- For this job's task-loop workflow, do not read from or write to legacy
  YAML task ledgers such as `.deepwork/jobs/task_loop/TASKS.yaml`.
- Keep tags within the approved namespaces from `process.notes`:
  - `project/<slug>`
  - `repo/<owner>/<repo>`
  - `status/<value>`
  - `source/<value>`
- Store milestone, issue, pull request, assignee, and deduplication references
  in frontmatter fields instead of inventing new tag namespaces.

### Daily rollover

- The human operator's notes repo is the coordination source of truth.
- The executive-assistant task loop maintains one dated daily note per day and
  carries unfinished work forward by linking existing task notes.
- Agent-owner notes repos should receive only assigned-work mirror notes plus
  backlinks to the human daily note.

### Learnings from task_loop rollout (2026-03-28)

1. After adding or restructuring a job, run a DeepWork MCP validation pass on
   the job itself. `deepwork_jobs/learn` is the right fit for instruction and
   schema review.
2. `deepwork_jobs/repair` is not a general job-review workflow. It expects a
   workspace `.claude/settings.json` and is not applicable when that file is
   absent.
3. The executive-assistant task loop now relies on a shared task-note
   frontmatter contract at `steps/shared/task_note_frontmatter.md`. Keep task
   discovery, rollover, and owner mirroring aligned with that file.
4. The current `ncrmro/notes` notebook may contain project hub notes with
   `project:` frontmatter but without `status/active`. When that happens, the
   canonical zk active-hub query returns zero notes. Treat this as notebook
   drift, use the frontmatter notes as provisional hubs, and report the need
   for normalization.
5. During the smoke test, `zk new reports/ ...` only worked reliably when run
   from inside the notebook workdir. Future note-creation steps should not rely
   on relative note-group creation from an arbitrary cwd, even when a notebook
   path is otherwise known.

### Zellij fleet survey (added 2026-03-28)

6. **The most efficient way to see what agents are doing right now is the zellij
   fleet survey** — it takes seconds and reveals live activity not yet captured
   in notes repos or git log:

   ```bash
   # List non-EXITED sessions
   zellij list-sessions 2>/dev/null | grep -v EXITED

   # Dump focused pane of each active session in parallel
   for session in <names>; do
     zellij --session "$session" action dump-screen /tmp/zellij-dump-${session}.txt
   done
   ```

   Interpreting dumps:
   - Claude Code idle prompt (`❯`) → agent waiting for work
   - DeepWork MCP tool call JSON in the pane → identifies job/step/workflow exactly
   - `agentctl <owner> claude` launch line → identifies which agent is running
   - Shell prompt with no agent → session is human-operated or unoccupied

7. **Session naming conventions on this keystone host:**
   - Sessions named after projects (`keystone`, `catalyst`, `plant-caravan`) are
     usually human or agent workspaces for that project's repo.
   - Sessions named `<project>-<feature>` (e.g., `keystone-tui`,
     `keystone-ks-web-docs`) are agent sessions for a specific feature branch.
   - Sessions named after owners (`luce-catalyst`, `drago-pull-request`) are
     agent sessions scoped to that agent.
   - `notes` is typically the human operator's current session.

8. **`dump-screen` captures only the focused pane.** For multi-pane sessions,
   run `dump-layout` first to understand the structure, then interpret the dump
   accordingly. Single-pane claude agent sessions are unambiguous.

### Eisenhower matrix + project stats (added 2026-03-28)

9. **The `synthesize_daily_priorities` step now produces an Eisenhower 2x2
   matrix.** Projects with no recent merges, no active milestone, or no
   assignee are strong Q4 candidates. Use project stats from
   `collect_active_task_notes` to make the placement defensible, not just
   intuitive.

10. **Q4 disposal vocabulary** (agreed with operator 2026-03-28):
    - **Defer** — important but not ready; add to a future milestone with date
    - **Delegate** — assign to drago (engineering) or luce (product/scoping)
    - **Icebox** — apply `icebox` GitHub label, remove from milestone, leave a comment
    - **Delete** — close as "not planned" with a one-line explanation

11. **Known active projects on this keystone instance** (for Eisenhower placement):
    - `gh:ncrmro/keystone` — infrastructure platform; high importance always
    - `gh:ncrmro/catalyst` — revenue-generating SaaS; high importance
    - `gh:ncrmro/plant-caravan` — active milestone; medium importance
    - `gh:ncrmro/meze` — no milestone, stalled; review each run — may be Q4
    - `gh:ncrmro/ks.systems` — marketing/docs site; low urgency unless launch imminent
    - `Unsupervised.com` — separate org; check separately via `gh:Unsupervisedcom`
