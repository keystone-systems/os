# Plan Commits

## Objective

Read the scan results, present the next unprocessed change group to the user for
review and approval, confirm the commit message, and claim the group in shared state
so other sessions know it is in progress.

## Inputs

- `wrap_up_scan.json` — output from `scan_context`
- `.deepwork/tmp/wrap_up_state.json` — shared session state

## Steps

### 1. Read scan results

```bash
cat .deepwork/tmp/wrap_up_scan.json
```

If `no_changes` is `true`, skip to step 5 (nothing to do).

### 2. Refresh shared state

Re-read `.deepwork/tmp/wrap_up_state.json` (it may have been updated by other
sessions since `scan_context` ran):

```bash
cat .deepwork/tmp/wrap_up_state.json 2>/dev/null || echo '{}'
```

- Release stale session claims (last_seen > 30 minutes ago).
- Rebuild the set of:
  - **Claimed** group keys (active sessions with non-stale claims).
  - **Processed** group keys (already committed this session or prior).

### 3. Select the next group

From `change_groups` in `wrap_up_scan.json`, find the first group whose key is
not in the claimed or processed set.

If no unclaimed group remains → all work is done. Set `all_done: true` in
`wrap_up_plan.json` and skip to step 6.

### 4. Present the group to the user

Show a concise summary:

```
Repo:    <repo absolute path>
Branch:  <branch>  (default: <default_branch>  ahead: <N>  behind: <N>)
Files:
  - path/to/file.ext
  - path/to/other.ext
Suggested commit:
  <suggested_message>
```

If the group notes indicate a merge or rebase is in progress, flag it and skip
it (do not claim it).

Ask the user:

1. **Approve the file list?** (yes / edit — if edit, let the user remove files
   they want to defer; removed files stay in `wrap_up_scan.json` as unclaimed)
2. **Commit message?** (accept suggested / provide a replacement)
3. **Push after commit?** (yes / no — default yes)

### 5. Claim the group

Write the claim to shared state **before** proceeding. This prevents another
session from picking up the same group:

```json
{
  "sessions": {
    "<session_id>": {
      "claimed_group_key": "<key>",
      "status": "claiming",
      "last_seen": "<ISO-8601 now>"
    }
  },
  "processed_groups": [ ... ]
}
```

Use a read-modify-write pattern to avoid clobbering other sessions:

```bash
STATE=".deepwork/tmp/wrap_up_state.json"
TMPFILE="${STATE}.tmp.$$"
cat "$STATE" 2>/dev/null | jq \
  --arg sid "<session_id>" \
  --arg key "<group_key>" \
  --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '.sessions[$sid] = {claimed_group_key: $key, status: "claiming", last_seen: $now}' \
  > "$TMPFILE" && mv "$TMPFILE" "$STATE"
```

### 6. Write output

Write `wrap_up_plan.json`:

```json
{
  "all_done": false,
  "group": {
    "key": "<key>",
    "repo": "<absolute path>",
    "files": ["<relative path>", ...],
    "commit_message": "<approved message>",
    "branch": "<branch>",
    "push": true
  }
}
```

If `all_done` is `true`:

```json
{
  "all_done": true
}
```

## Output Format

### wrap_up_plan.json

Written to `.deepwork/tmp/wrap_up_plan.json`.

## Quality Criteria

- The plan file is written with the group key, repo path, approved file list, and commit message
- The session claim is written to shared state before the output file
- Files the user deferred are NOT in the plan's file list
- If no groups remain, `all_done: true` is set
