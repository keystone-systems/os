# Commit Convention

## Objective

Commit all convention changes to the main branch and push to the remote. This is the final step — after this, the convention is live.

## Task

Review the change summary, stage only convention-related files, create a properly formatted commit, and push to origin/main.

### Process

1. **Read the change summary**
   - Read `.deepwork/tmp/change_summary.md` from the apply step
   - Extract the list of files changed

2. **Verify working tree state**
   - Run `git status` to see all modified/untracked files
   - Confirm that only convention-related files are changed:
     - `conventions/*.md` (created or modified)
     - `conventions/archetypes.yaml` (modified)
   - If there are unrelated changes in the working tree, do NOT stage them — only stage convention files

3. **Review the diff**
   - Run `git diff` on the files to be committed
   - Verify the changes match what the change summary describes
   - Check for accidental whitespace changes, encoding issues, or unintended edits

4. **Create the commit**
   - Stage only the convention files listed in the change summary
   - Write a commit message following conventional commits format:
     - If creating a new convention: `docs(conventions): add {prefix}.{topic} convention`
     - If also modifying existing conventions: `docs(conventions): add {prefix}.{topic} + deduplicate overlapping rules`
     - If only updating existing: `docs(conventions): update {conventions} with cross-references`
   - The commit body should list the key changes (new convention, rules moved, cross-refs added)

5. **Push to remote**
   - Push to `origin/main`
   - If the push is rejected because the remote has new commits, handle the rebase:
     1. Stash any unstaged changes: `git stash`
     2. Rebase on top of remote: `git pull --rebase origin main`
     3. Restore stashed changes: `git stash pop`
     4. Retry the push
   - Verify the push succeeded

6. **Clean up temp files**
   - Remove `.deepwork/tmp/convention_draft.md`
   - Remove `.deepwork/tmp/cross_reference_report.md`
   - Remove `.deepwork/tmp/change_summary.md`

## Output Format

### commit_result.md

Written to `.deepwork/tmp/commit_result.md`.

**Structure**:

```markdown
# Commit Result

## Commit

- **Hash**: {short hash}
- **Message**: {commit message first line}
- **Branch**: main
- **Pushed**: Yes/No

## Files in Commit

- `conventions/{prefix}.{topic}.md` (new)
- `conventions/{existing}.md` (modified)
- `conventions/archetypes.yaml` (modified)

## Verification

- `git status` clean: Yes/No
- Push to origin/main: Success/Failed
```

## Quality Criteria

- The commit message follows conventional commits format (`docs(conventions): ...`)
- The commit has been pushed to `origin/main` successfully
- The commit contains only convention-related files — no unrelated changes leaked in
- Temp files in `.deepwork/tmp/` are cleaned up

## Context

This is the final step in the convention workflow. Unlike the `develop` workflow which uses worktrees and requires human-in-the-loop deploys, conventions commit directly to main because they are documentation files that do not affect Nix builds or host deployments. The convention becomes available to agents after the next `ks build` or `ks update` regenerates the CLAUDE.md instruction files from `archetypes.yaml`.
