## Advanced VCS

## Temporary state preservation

1. When agents need to clear the worktree temporarily to inspect another branch,
   switch context, or retry an operation, they MUST use `git stash push` and
   later restore with `git stash pop` as the default path.
2. Agents SHOULD use `git stash push -u` when untracked files are part of the
   temporary state that must be preserved.
3. Agents MUST NOT move tracked or untracked work into ad hoc temporary
   directories as a substitute for `git stash` unless `git stash` cannot
   represent the required state.
4. Agents MUST treat destructive cleanup commands such as `git reset --hard`,
   `git checkout -- <path>`, or equivalent history-discarding operations as a
   last resort, not a routine workflow.
5. In an interactive session, agents MUST ask for confirmation before running a
   destructive cleanup command that would discard or overwrite local work.
6. When the user has not explicitly approved destructive cleanup, agents MUST
   assume `git stash` and `git stash pop` are the golden path for preserving
   temporary worktree state.

## Branch Analysis

7. When understanding changes between branches, agents MUST use `git diff <base>..HEAD` rather than reading files individually through editor tools.
8. When reviewing upstream changes before a rebase, agents MUST use `git diff <merge-base>..origin/main -- <path>` to understand what changed upstream in specific files.
9. Agents MUST use `git log --oneline <base>..HEAD -- <path>` to identify which commits touched a file rather than reading entire file histories.
10. For understanding what a branch introduces, agents SHOULD run `git log --oneline origin/main..HEAD` and `git diff origin/main..HEAD --stat` before exploring individual files.

## Bug Finding with Bisect

11. When a regression is identified but the introducing commit is unknown, agents SHOULD use `git bisect` to binary-search for the offending commit.
12. Before starting bisect, agents MUST identify a clear test condition, a known-bad ref, and a known-good ref.
13. When a reproducible test command exists, agents SHOULD use `git bisect run <test-command>` for fully automated bisection.
14. After bisect completes, agents MUST run `git bisect reset` to return to the original HEAD.

## Rebase Conflict Resolution

15. When rebasing and encountering conflicts on generated files (lock files, migration files, compiled outputs), agents MUST accept the upstream version, complete the rebase, then regenerate the files in a separate commit.
16. Lock file conflicts MUST NOT be resolved by manual three-way merge — agents MUST accept upstream (`git checkout --theirs <lockfile>`), regenerate (e.g., `npm install`, `cargo generate-lockfile`), and commit separately.
17. Migration conflicts (e.g., Django, Rails, Alembic) MUST be resolved by accepting upstream migrations, completing the rebase, then regenerating the feature branch's migrations from the stable base.
18. After resolving generated-file conflicts, the regeneration commit MUST use a descriptive message (e.g., `chore(deps): regenerate lockfile after rebase`).

## Token-Efficient Git Operations

19. Agents MUST NOT read entire files to understand what changed — use `git diff`, `git show <commit>:<path>`, or `git log -p` to see only relevant changes.
20. When investigating a specific change, agents SHOULD use `git log -S '<term>'` (pickaxe) to find commits that introduced or removed a string.
21. Agents SHOULD use `git log --oneline --graph` for quick branch topology understanding rather than exploring commit-by-commit.
22. When only file names are needed, agents MUST use `git diff --name-only` or `git diff --stat` instead of full diffs.

## Golden Example

### Efficient branch analysis before rebase

```bash
# Preserve temporary work before switching context
git stash push -u -m "wip before branch inspection"

# See what upstream changed since we branched
git fetch origin
git diff HEAD..origin/main --stat
#  flake.lock          | 42 +++---
#  modules/os/agents.nix | 85 ++++++++----

# Inspect only the files that matter
git diff HEAD..origin/main -- modules/os/agents.nix

# See what our branch introduces
git log --oneline origin/main..HEAD
#  f255ece fix(agent): address Copilot review feedback
#  63a2d85 refactor(agent): split monolithic agents.nix

# Restore the temporary work when done
git stash pop
```

### Rebase with lockfile conflict

```bash
# Start the rebase
git rebase origin/main

# Conflict on flake.lock — accept upstream, don't manually merge
git checkout --theirs flake.lock
git add flake.lock
git rebase --continue

# After rebase completes, regenerate the lockfile
nix flake update
git add flake.lock
git commit -m "chore(deps): regenerate flake.lock after rebase"
```

### Bisect to find a regression

```bash
git bisect start
git bisect bad HEAD          # current commit is broken
git bisect good v1.2.0       # this tag was working

# Automated: let the test command drive bisection
git bisect run nix flake check

# When done
git bisect reset
```
