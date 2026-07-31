# Sync Changes

## Objective

Commit and push all remaining changes via the repo's git workflow.

## Task

1. Check for any uncommitted changes:

   ```bash
   git status
   ```

2. If there are uncommitted changes, stage and commit:

   ```bash
   git add -A
   git commit -m "chore(notes): inbox processing complete"
   ```

3. Push to remote:

   ```bash
   git push
   ```

   If push fails due to upstream changes, pull with rebase first:

   ```bash
   git pull --rebase
   git push
   ```

4. Report sync status.

## Output Format

Write `sync_status.md`:

```markdown
# Sync Status

- Uncommitted changes: yes/no
- Commit: <hash> (if any)
- Push: OK / failed (reason)
- Remote: <remote-url>
```
