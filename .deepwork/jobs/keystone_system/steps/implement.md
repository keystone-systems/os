# Implement

## Objective

Execute the implementation plan in the worktree — write code, test locally, and commit changes with clean conventional commits.

## Task

Read the plan from the previous step and execute each change in the worktree. Work methodically through the plan, committing logical units of work as you go.

### Process

1. **Switch to the worktree**
   - The worktree path is specified in the plan's "Branch" section
   - All file operations must happen in the worktree, NOT on main

2. **Execute each plan step in order**
   - Follow the plan's steps sequentially
   - Read each target file before modifying it — understand the existing code
   - Make the smallest change that achieves the goal
   - If you discover something the plan missed, note it but stay focused — don't scope-creep

3. **Commit as you go**
   - Use conventional commits: `feat(scope): description`, `fix(scope): description`, etc.
   - Group related changes into logical commits
   - Don't batch everything into one giant commit
   - Ensure each commit builds cleanly on its own when possible

4. **Quick-check as you go**
   - For Nix changes: run `nix flake check --no-build` after significant edits to catch syntax errors early
   - For shell scripts: check with `shellcheck` if available
   - Don't wait until the build step to discover basic errors

5. **Document what you did**
   - Track every file modified and why
   - Note any deviations from the plan with justification
   - Record any decisions made during implementation

## Output Format

### implementation_summary.md

```markdown
# Implementation Summary

## Branch

- **Name**: `<branch-name>`
- **Worktree**: `.claude/worktrees/<branch-name>`

## Changes Made

### Commit: `<short hash>` — `<commit message>`

- **Files**: `path/to/file1.nix`, `path/to/file2.nix`
- **What**: [Brief description of what this commit does]

### Commit: `<short hash>` — `<commit message>`

- **Files**: `path/to/file3.nix`
- **What**: [Brief description]

[Continue for all commits...]

## Plan Coverage

| Plan Step           | Status | Notes                                  |
| ------------------- | ------ | -------------------------------------- |
| 1. [step from plan] | Done   |                                        |
| 2. [step from plan] | Done   | Slightly different approach — [reason] |
| 3. [step from plan] | Done   |                                        |

## Deviations from Plan

- [Any changes not in the original plan, with justification]
- [Or "None — implemented as planned"]

## Change Type Confirmation

- **Scope**: [OS-level | home-manager-only | both]
- **Build strategy**: [full nix build | ks build]
```

## Quality Criteria

- All steps from the implementation plan are addressed — none are silently skipped
- Changes are committed with conventional commit messages and logical grouping
- The implementation stays focused on the plan — no scope creep or drive-by fixes
- The change type (OS-level vs home-manager-only) is confirmed for the build step

## Context

This step produces the actual code changes. The next step (review) will run DeepWork .deepreview rules against these changes, so clean commits and focused changes make review easier. If the build step later fails, the workflow will loop back here to fix issues.
