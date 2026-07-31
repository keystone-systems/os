# Merge

## Objective

Merge the worktree branch into keystone main and push to origin, making the changes available for deployment.

## Task

Merge the completed, reviewed, and built changes from the worktree into the main branch and push.

### Process

1. **Pre-merge checks**
   - Confirm the build step passed (read build_result.md)
   - Ensure all commits in the worktree are pushed to the branch
   - Check if main has advanced since the worktree was created: `git log main..origin/main`

2. **Merge to main**
   - Switch to main: `git checkout main`
   - Pull latest: `git pull`
   - Merge the branch: `git merge <branch-name>`
   - If merge conflicts arise: resolve them, then re-run `nix flake check --no-build` to verify
   - Do NOT use `--squash` — preserve individual commits for history

3. **Push**
   - Push main to origin: `git push`
   - Verify the push succeeded

4. **Clean up worktree**
   - Remove the worktree: `git worktree remove .claude/worktrees/<branch-name>`
   - Delete the branch: `git branch -d <branch-name>`
   - Note: if validation later fails and requires a fix, a new worktree will be created in the plan step — this is by design (clean worktree per change)

5. **Document the merge**
   - Record the final commit hash on main
   - Note the branch that was merged

## Output Format

### merge_result.md

```markdown
# Merge Result

## Branch Merged

- **Branch**: `<branch-name>`
- **Commits**: [number of commits merged]
- **Final commit on main**: `<hash>`

## Merge Details

- **Conflicts**: [none | resolved — description]
- **Push status**: [success | failed — reason]

## Cleanup

- **Worktree removed**: [yes/no]
- **Branch deleted**: [yes/no]

## Ready for Deploy

The changes are now on keystone main at commit `<hash>`.
The human can now run `ks update --lock` in nixos-config to deploy.
```

## Quality Criteria

- The merge completed without unresolved conflicts and the branch was pushed to origin/main
- The worktree and branch were cleaned up
- The final commit hash is recorded for traceability

## Context

After this step, the changes are on keystone main but NOT yet deployed. The deploy step requires human intervention (`ks update --lock` needs sudo). The merge result provides the commit hash the human needs to verify they're deploying the right changes.
