<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->

# Convention: Refactor Discipline (process.refactor)

This convention ensures that significant refactors are tracked, reviewed, and merged independently from feature work.

## When to Separate

1. Significant refactors MUST have a dedicated issue opened before work begins.
2. A refactor is significant if it renames public APIs, moves files across directories, restructures modules, changes data models, or touches more than approximately three files for structural reasons unrelated to a feature.
3. Minor incidental cleanup (renaming a local variable, fixing a typo, extracting a small helper within the same file) MAY be included in a feature PR.

## Refactor Issues

4. The refactor issue MUST describe what is being restructured, why, and the expected end state.
5. The issue title MUST follow conventional format: `refactor(scope): description`.
6. The issue SHOULD belong to the same milestone as the feature that motivated it.

## Refactor PRs

7. Refactor work MUST be done on its own branch and PR, separate from feature work.
8. The refactor PR MUST be merged before the feature PR that depends on it.
9. The refactor PR title MUST use the `refactor(scope):` conventional commit type per `process.version-control`.
10. Refactor PRs MUST NOT introduce behavioral changes — tests before and after SHOULD produce the same results.

## Agent Behavior

11. When an agent discovers that a refactor is needed during feature implementation, it MUST stop and open a refactor issue rather than bundling the refactor into the feature PR.
12. The feature issue or PR SHOULD reference the refactor issue as a prerequisite.
13. Agents MUST NOT perform speculative refactors — every refactor MUST be motivated by a concrete need (current task blocked, code unmaintainable, or upcoming feature requires it).

## Golden Example

Agent is implementing issue #30 ("Add user search endpoint") and discovers the route
registration is tangled — all routes are in a single file. The refactor is structural
(moving routes into separate modules), so it must be separated.

```bash
# 1. Agent stops feature work and opens a refactor issue (rules 1, 4-5)
gh issue create --repo ncrmro/catalyst \
  --title "refactor(api): split monolithic routes.ts into per-resource modules" \
  --body "$(cat <<'EOF'
## What

Split `src/routes.ts` (currently ~400 lines with all route handlers) into
per-resource modules under `src/routes/`.

## Why

Adding the search endpoint (issue #30) requires adding another handler to
the already-overloaded routes file. Splitting first makes the feature PR
clean and reviewable.

## Expected end state

```

src/routes/
index.ts — re-exports all route registrations
users.ts — /api/users handlers
products.ts — /api/products handlers
health.ts — /api/health handler

```

All existing tests pass unchanged.

Prerequisite for #30.
EOF
)"

# 2. Note the dependency on the feature issue (rule 12)
gh issue comment 30 --repo ncrmro/catalyst \
  --body "Blocked on #31 (route restructure) — will resume after merge."

# 3. Create refactor branch and implement (rules 7, 9)
cd "$HOME/repos/ncrmro/catalyst"
git fetch origin
git branch refactor/split-routes origin/main
git worktree add "$HOME/repos/ncrmro/catalyst/worktrees/refactor/split-routes" refactor/split-routes

# ... implement the refactor, verify tests still pass ...

# 4. Open refactor PR (rule 9)
gh pr create --draft \
  --title "refactor(api): split monolithic routes.ts into per-resource modules" \
  --body "Closes #31 ..."

# 5. After refactor merges, resume feature work (rule 8)
# Rebase feature branch onto updated main, then continue with #30
```
