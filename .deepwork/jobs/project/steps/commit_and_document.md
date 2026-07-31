# Commit and Document

## Objective

Stage and commit the approved file group, optionally push it, update the shared
state to mark the group as processed, and write a brief handoff note in the configured notes dir
(or update an existing open issue/PR with a check-in comment).

## Inputs

- `wrap_up_plan.json` — from `plan_commits`
- `.deepwork/tmp/wrap_up_state.json` — shared session state

## Steps

### 1. Read the plan

```bash
cat .deepwork/tmp/wrap_up_plan.json
```

If `all_done` is `true`, there is nothing to do — skip to step 7 and emit an
empty `commit_result.json`.

### 2. Stage files

```bash
cd <group.repo>
git add -- <file1> <file2> ...
```

Run `git status` to confirm only the intended files are staged. If unintended
files appear (e.g., auto-generated outputs), unstage them and note the deviation.

### 3. Commit

```bash
git -C <group.repo> commit -m "<group.commit_message>"
```

Capture the resulting commit SHA:

```bash
COMMIT_SHA=$(git -C <group.repo> rev-parse HEAD)
```

### 4. Push (if approved)

If `group.push` is `true`:

```bash
git -C <group.repo> push
```

If the branch has no upstream yet:

```bash
git -C <group.repo> push --set-upstream origin <group.branch>
```

### 5. Update shared state

Mark the group as processed. Use a read-modify-write to avoid clobbering other
sessions:

```bash
STATE=".deepwork/tmp/wrap_up_state.json"
TMPFILE="${STATE}.tmp.$$"
cat "$STATE" | jq \
  --arg sid "<session_id>" \
  --arg key "<group.key>" \
  --arg sha "<COMMIT_SHA>" \
  --arg repo "<group.repo>" \
  --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '
    .sessions[$sid].status = "done" |
    .sessions[$sid].last_seen = $now |
    .processed_groups += [{
      key: $key,
      commit_sha: $sha,
      repo: $repo,
      processed_by: $sid,
      processed_at: $now
    }]
  ' > "$TMPFILE" && mv "$TMPFILE" "$STATE"
```

### 6. Post a check-in comment (if there are open issues/PRs for this work)

For any open GitHub or Forgejo issues and PRs identified as relevant in the session
context or in `wrap_up_scan.json` notes, post a brief status comment using the
template from `process.wrap-up`:

```markdown
## Session check-in — <YYYY-MM-DD>

**Status:** committed — `<commit_sha_short>` on `<branch>`

### What happened

- Committed: `<commit_message>`
- Files: <count> file(s) in `<top-level dir>`

### Testing

<any testing notes, or "not tested in this session">

### Next steps

1. <next concrete action if known>

### Deferred

<files or work explicitly deferred — or "nothing deferred">

---
*Check-in from /wrap-up.*
```

Skip this step if no relevant issues/PRs are known.

### 7. Write output

Write `.deepwork/tmp/wrap_up_progress.json`:

```json
{
  "committed": true,
  "group_key": "<key>",
  "repo": "<absolute path>",
  "branch": "<branch>",
  "commit_sha": "<full SHA>",
  "commit_message": "<message>",
  "pushed": true,
  "files": ["<relative path>", ...],
  "notes_report_path": "<path to configured notes-dir report, or null>",
  "issues_commented": ["<URL>", ...]
}
```

If nothing was committed (`all_done` was true from the plan):

```json
{
  "committed": false
}
```

## Output Format

### wrap_up_progress.json

Written to `.deepwork/tmp/wrap_up_progress.json`.

## Quality Criteria

- The commit SHA is recorded in both `commit_result.json` and shared state
- Shared state `processed_groups` entry includes `key`, `commit_sha`, `repo`, `processed_by`, `processed_at`
- The session's `status` is updated to `"done"` in shared state
- Only the files from the approved plan are staged — no unintended files
