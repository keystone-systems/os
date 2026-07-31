# Scan Context and Cluster Changes

## Objective

Discover every uncommitted change across the specified repos, filter out work
already handled by other sessions, and cluster remaining changes into logical
commit groups so the next step can present a clean plan to the user.

## Inputs

- `repos` — space-separated repo paths from the user, or current working directory if blank.
- `.deepwork/tmp/wrap_up_state.json` — shared session state (may not exist yet).

## Shared State Schema

The shared state file lives at `.deepwork/tmp/wrap_up_state.json`:

```json
{
  "sessions": {
    "<session_id>": {
      "claimed_group_key": "<key>",
      "status": "claiming|committing|done",
      "last_seen": "<ISO-8601 timestamp>"
    }
  },
  "processed_groups": [
    {
      "key": "<group_key>",
      "commit_sha": "<sha>",
      "repo": "<path>",
      "processed_by": "<session_id>",
      "processed_at": "<ISO-8601 timestamp>"
    }
  ]
}
```

A session is **stale** if `last_seen` is more than 30 minutes ago. Release
stale session claims before reading active ones.

## Steps

### 1. Resolve repos

If `repos` is blank, use the current working directory. Otherwise split on
spaces to get a list of paths. For each path, verify it is a git repo:

```bash
git -C <path> rev-parse --is-inside-work-tree 2>/dev/null
```

Skip non-git paths with a warning.

### 2. Read shared state

```bash
cat .deepwork/tmp/wrap_up_state.json 2>/dev/null || echo '{}'
```

Parse out:
- Active (non-stale) session claims → set of claimed group keys to exclude.
- Processed groups → set of file paths already committed this session → exclude from discovery.

### 3. Discover changes per repo

For each repo, run:

```bash
git -C <path> status --short
git -C <path> rev-parse --abbrev-ref HEAD          # current branch
git -C <path> symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's|origin/||'  # default branch
git -C <path> rev-list --left-right --count HEAD...@{upstream} 2>/dev/null  # ahead/behind
```

Collect all modified, new, deleted, and untracked files.

### 4. Filter processed and claimed files

Remove any file that appears in a processed group or is claimed by an active
(non-stale) session.

### 5. Cluster remaining changes into logical groups

Use the following heuristics (apply in order; stop when a file is assigned):

1. **Modified files with related names**: files sharing a directory prefix and
   modified in the same apparent feature (e.g., `conventions/process.wrap-up.md`
   and `modules/terminal/agent-assets/wrap-up-skill.template.md` → same group).

2. **New files alongside a modified parent**: a new step instruction file
   alongside a modified `job.yml` → same group.

3. **Dependency updates alone**: `flake.lock`, `package-lock.json`,
   `go.sum`, etc. → their own group with `chore(deps):` prefix.

4. **Catch-all**: remaining files with no clear relationship → one group per
   top-level directory (e.g., one group for all remaining `modules/` changes).

For each group, write:
- `key`: a stable slug derived from the repo path + first file (e.g., `keystone/conventions`)
- `repo`: absolute path to the repo
- `files`: list of affected paths relative to repo root
- `suggested_message`: a Conventional Commits message summarising the group
- `branch`: current branch name
- `default_branch`: detected default branch
- `ahead`: commits ahead of remote
- `behind`: commits behind remote

### 6. Write output

Write `wrap_up_scan.json` with this structure:

```json
{
  "repos_scanned": ["<path>", ...],
  "active_sessions": [{"session_id": "...", "claimed_group_key": "..."}],
  "processed_groups": [{"key": "...", "commit_sha": "..."}],
  "change_groups": [
    {
      "key": "keystone/conventions",
      "repo": "/home/ncrmro/.keystone/repos/ncrmro/keystone",
      "files": ["conventions/process.wrap-up.md"],
      "suggested_message": "feat(conventions): add wrap-up convention",
      "branch": "main",
      "default_branch": "main",
      "ahead": 0,
      "behind": 0
    }
  ],
  "no_changes": false
}
```

If there are no change groups after filtering, set `no_changes: true` and note
this in the output so `plan_commits` can inform the user that everything is
already clean.

### 7. Handle edge cases

- **On default branch with unstaged work**: note it clearly — the user may want
  to create a feature branch first. Do not refuse; just record it.
- **Untracked files**: include them in grouping. The commit step will handle
  `git add`.
- **Repos with uncommitted merges or rebase in progress**: flag them in
  `change_groups[*].notes` and skip committing for that repo — let the user
  resolve manually.
