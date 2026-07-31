# Continue or Finish

## Objective

After a group has been committed, check whether additional unprocessed change
groups remain. If they do, ask the user whether to continue and loop back to
`plan_commits`. If none remain (or the user says stop), produce a final summary.

## Inputs

- `wrap_up_progress.json` — from `commit_and_document`
- `wrap_up_scan.json` — from `scan_context`
- `.deepwork/tmp/wrap_up_state.json` — shared session state

## Steps

### 1. Read current state

```bash
cat .deepwork/tmp/wrap_up_scan.json
cat .deepwork/tmp/wrap_up_state.json 2>/dev/null || echo '{}'
```

Rebuild the set of processed and claimed group keys (same logic as `plan_commits`
step 2, including stale session release).

### 2. Count remaining groups

From `wrap_up_scan.json` `change_groups`, count groups whose key is not yet
processed or actively claimed by a non-stale session.

### 3. Decide

**If 0 remaining groups:**

- Print the completion summary (see below).
- Write `wrap_up_summary.json` with `finished: true`.
- Complete the workflow.

**If ≥ 1 remaining groups:**

- Show the user how many groups remain and a one-line preview of each
  (suggested commit message only — not full file lists).

- Ask: **"Process the next group? (yes / no / stop)**
  - `yes` → call `go_to_step` with `step_id: "plan_commits"` to loop.
  - `no` / `stop` → print partial summary and complete the workflow with
    `finished: false`.

### 4. Completion summary

Print a table of everything committed this session:

```
Wrap-up complete for this session.

Committed groups:
  ✓  <commit_sha_short>  <branch>  <commit_message>  (<repo short name>)
  ...

Remaining (not processed this session):
  -  <key>  <suggested_message>  (<repo short name>)
  ...

Run /project.wrap_up in another session or tab to continue.
```

### 5. Write output

Write `wrap_up_summary.md` in the working directory:

```markdown
# Wrap-up Summary

**Session**: <session_id>
**Date**: <YYYY-MM-DD>

## Committed This Session

| SHA       | Branch     | Message                          | Repo               |
| --------- | ---------- | -------------------------------- | ------------------ |
| `abc1234` | `feat/...` | `feat(terminal): add wrap-up...` | ncrmro/keystone    |
| ...       | ...        | ...                              | ...                |

## Notes Reports Created

- <path or "none">

## Issues / PRs Commented

- <URL or "none">

## Remaining (not processed this session)

| Key                    | Suggested Message        | Repo            |
| ---------------------- | ------------------------ | --------------- |
| `keystone/modules/...` | `chore(deps): update...` | ncrmro/keystone |
| ...                    | ...                      | ...             |

Run `/project.wrap_up` to continue processing remaining groups.
```

If `finished` is `true` and no groups remain, omit the "Remaining" section.

## Output Format

### wrap_up_summary.md

Written to the working directory (`.deepwork/tmp/wrap_up_summary.md`).

## Quality Criteria

- Remaining group count is correct (accounts for groups claimed by other active sessions)
- If groups remain and the user said yes, `go_to_step plan_commits` is called
- The summary lists every group committed this session with its commit SHA
- `finished` is `true` only when no unclaimed groups remain
