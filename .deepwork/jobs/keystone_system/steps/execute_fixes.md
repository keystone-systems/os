# Execute Fixes

## Objective

Apply all ad-hoc fixes identified in the update plan and file GitHub issues for items that are too large or risky to fix before deployment.

## Task

Work through the update plan's triage lists: fix small issues in keystone worktrees and create tracked issues for larger problems. After this step, keystone main should be ready for a clean `ks update --lock`.

### Process

1. **Read the update plan**
   - Load update_plan.md from the plan_update step
   - Extract the ad-hoc fixes list and the needs-issue list

2. **Execute ad-hoc fixes**
   For each item in the "Ad-Hoc Fixes" table:
   - Create a worktree branch off keystone main:
     ```bash
     git worktree add ../keystone-fix-<short-name> -b fix/<short-name> main
     ```
   - Make the fix in the worktree
   - Run a quick build check: `nix flake check --no-build` from the worktree
   - Commit with conventional commit format: `fix(scope): description`
   - Merge back to main:
     ```bash
     git checkout main && git merge fix/<short-name> --ff-only
     ```
   - Clean up the worktree: `git worktree remove ../keystone-fix-<short-name>`
   - Push main: `git push origin main`

   **If a fix is more complex than expected** (> 30 min or introduces risk), stop and reclassify it as needs-issue instead. Do not force a bad fix.

3. **File issues for large items**
   For each item in the "Needs Issue" table:
   - Use the `keystone_system/issue` workflow via the DeepWork MCP tools as a nested workflow, OR
   - Create a GitHub issue directly:
     ```bash
     gh issue create --repo ncrmro/keystone --title "type(scope): description" \
       --body "## Problem\n\n[description]\n\n## Context\n\nIdentified during ks.update survey on [date].\nSeverity: [from plan]\n\n## Why Not Ad-Hoc\n\n[justification from plan]"
     ```
   - Record the issue URL for the report

4. **Handle pre-existing doctor issues**
   - If the plan identified pre-existing issues from `ks doctor`, determine if any can be fixed ad-hoc
   - Fix those that are simple (same worktree process as above)
   - File issues for complex ones
   - Some pre-existing issues may be expected/known — document those as "acknowledged"

5. **Verify keystone main is clean**
   - After all fixes are merged and pushed:
     ```bash
     git -C <keystone-path> status
     git -C <keystone-path> log origin/main..HEAD --oneline
     ```
   - Confirm no uncommitted changes and no unpushed commits
   - Run a final `nix flake check --no-build` from nixos-config to verify the latest keystone evaluates cleanly

6. **Assess readiness**
   - If all ad-hoc fixes are applied and no blockers remain → ready for run_update
   - If blockers exist (fix attempts failed, critical issues found) → document them and call `go_to_step` with `step_id: "plan_update"` to re-triage

**Maximum loop iterations**: If this is the 2nd attempt at execute_fixes, stop and present all remaining issues to the human for guidance rather than looping again.

## Output Format

### fixes_report.md

```markdown
# Fixes Report

**Date**: [date]
**Keystone main**: `[current main hash]`

## Ad-Hoc Fixes Applied

| #   | Fix                     | Commit    | Branch              | Status   |
| --- | ----------------------- | --------- | ------------------- | -------- |
| 1   | Add default for foo.bar | `abc1234` | fix/foo-bar-default | merged ✓ |
| 2   | Reset stale agent timer | `def5678` | fix/agent-timer     | merged ✓ |

## Issues Filed

| #   | Problem                 | Issue URL                                    | Severity |
| --- | ----------------------- | -------------------------------------------- | -------- |
| 1   | Service X API migration | https://github.com/ncrmro/keystone/issues/42 | medium   |

## Pre-Existing Issues

| #   | Issue                    | Resolution                           |
| --- | ------------------------ | ------------------------------------ |
| 1   | Agent-drago offline 13d  | Filed as issue (see above)           |
| 2   | Stale flake.lock warning | Will be resolved by ks update --lock |

## Readiness Assessment

- **Keystone main clean**: [yes | no]
- **All ad-hoc fixes merged**: [yes | no — details]
- **All issues filed**: [yes | no — details]
- **Blockers**: [none | list with details]
- **Ready for ks update --lock**: [yes | no — what's blocking]
```

## Quality Criteria

- Every item marked ad-hoc-fix in the plan is resolved — committed and pushed to keystone main
- Every item marked needs-issue has a GitHub issue URL linked in the report
- Any remaining blockers that would prevent ks update --lock from succeeding are documented with mitigation steps

## Context

This step bridges the gap between planning and deployment. By fixing small issues now, we reduce the risk of `ks update --lock` failing mid-deploy. By filing issues for large problems, we ensure nothing is forgotten. The key discipline is not over-scoping ad-hoc fixes — if a fix takes more than 30 minutes or introduces new risk, it becomes an issue for a proper development cycle via `ks.develop`.
