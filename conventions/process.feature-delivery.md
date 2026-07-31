## Code Delivery

This convention defines the end-to-end lifecycle of delivering features and fixes via code changes: from milestone/issue through to merged PR. It orchestrates existing conventions rather than duplicating them.

## Upstream Dependencies

1. Feature delivery MUST originate from an issue belonging to a milestone.
2. Requirements MUST be documented as specs before implementation begins.
3. If no milestone exists, one MUST be created per `process.product-engineering-handoff`.

## Issue as Plan

4. The issue body MUST serve as the plan of record — no separate `plan.md` files.
5. The issue body MUST include a checklist of deliverables derived from the spec.
6. Large issues MUST be decomposed into sub-issues, each becoming its own branch and PR.
7. Sub-issues MUST reference the parent issue (e.g., "Part of #42").
8. The issue body SHOULD be updated as the plan evolves; comments supplement but do not replace it.

## Branch and Early PR

9. A branch MUST be created from the default branch using `process.version-control` naming conventions (semantic prefix + short description).
10. All implementation work MUST be done in a git worktree at `$HOME/repos/{owner}/{repo}/worktrees/{branch}` per `process.git-repos`. The main checkout at `{repo-root}/` MUST remain on the default branch.
11. On GitHub, if the active issue's milestone is known but not set on the issue, the authoring agent MUST repair it before or during PR creation with `gh issue edit <issue_number> --milestone "<milestone_name>"`.
12. On GitHub, if the issue's milestone has a project board, the issue MUST be present on that board. If auto-add is not enabled or did not add it, the authoring agent MUST add it with `gh project item-add <project_number> --owner <owner_name> --url <issue_url>`. Board discovery, field lookup, and status transitions remain governed by `process.project-board`.
13. A dummy commit MUST be created immediately after branching (e.g., empty commit or minimal scaffold) to enable opening a PR.
14. A draft PR MUST be opened immediately after the dummy commit (Forgejo: `WIP:` title prefix per `tool.forgejo`; GitHub: `--draft` flag).
15. On GitHub, if a milestone is available for the issue, the authoring agent MUST also set the same milestone on the PR with `gh pr edit <pr_number> --milestone "<milestone_name>"`.
16. The PR body MUST include a `# Tasks` section containing the task breakdown as markdown checkboxes mirroring the issue's deliverable checklist.
17. The draft PR SHOULD make the plan visible to reviewers before implementation begins.

## PR Body Format

18. The PR body MUST follow the `process.pull-request` convention (`# Goal`, `# Changes`, `# Demo` sections) plus the `# Tasks` section from rule 16.
19. The PR title MUST follow conventional commit format per `process.version-control` (e.g., `feat(api): add search endpoint`).
20. The PR body MUST include `Closes #N` or `Fixes #N` to auto-close the originating issue on merge.

## Implementation

21. Commits MUST follow `process.version-control` commit discipline (early, often, one logical change per commit).
22. Changes MUST NOT exceed the scope of the issue's acceptance criteria.
23. All tasks in the PR body's `# Tasks` section MUST be updated in real-time as each sub-task is completed (see `process.vcs-context-continuity`). All tasks MUST be checked off before marking the PR ready for review.

## Review and Merge

24. Appropriate reviewers MUST be assigned before marking the PR ready for review.
25. Reviewers MUST be assigned per the ownership matrix in `process.code-review-ownership`. On both GitHub and Forgejo, CODEOWNERS handles automatic reviewer assignment when a PR is created or undrafted, provided the repo has branch protection requiring code owner review enabled. If auto-request is not enabled, the authoring agent MUST manually request reviewers per the ownership matrix.
26. On Forgejo, `tool.forgejo` rule 18 (repo owner as reviewer) is satisfied by including the repo owner in the CODEOWNERS file. Forgejo supports CODEOWNERS natively; no separate manual assignment is needed when CODEOWNERS is configured.
27. Copilot SHOULD also be requested as a supplementary reviewer per `process.copilot-agent`.
28. Review feedback MUST be addressed per `process.copilot-agent` conversation resolution rules (fix or explain every comment). For human reviewer feedback, agents MUST also follow `process.pr-review-response` for the full response lifecycle (fetch comments, push fixes, reply, re-request review).
29. PRs MUST be squash-merged per `process.pull-request`.
30. Agents MUST shepherd PRs end-to-end per `process.pr-shepherding` — from draft through CI stabilization, undraft, review, merge queue, and post-merge verification.

## Traceability

30. Every PR MUST reference its issue; every issue MUST belong to a milestone.
31. Issues MUST be closed via PR merge keywords (`Closes`, `Fixes`) — not manually.
32. After merge, demo artifacts MUST be posted on the issue per `process.product-engineering-handoff`.

## Golden Example

End-to-end walkthrough for implementing issue #12 ("Add search endpoint") from milestone "v1.0":

```bash
# 1. From the main checkout, create a branch and worktree (rules 9-10)
cd "$HOME/repos/acme/api"
git fetch origin
git branch feat/add-search-endpoint origin/main
git worktree add "$HOME/repos/acme/api/worktrees/feat/add-search-endpoint" feat/add-search-endpoint

# 2. Work in the worktree
cd "$HOME/repos/acme/api/worktrees/feat/add-search-endpoint"

# 3. Dummy commit to enable PR creation (rule 13)
git commit --allow-empty -m "chore: start work on search endpoint"

# 4. On GitHub, repair milestone and board linkage before or during PR creation (rules 11-12)
gh issue edit 12 --repo acme/api --milestone "v1.0"
gh project item-add 7 --owner acme --url https://github.com/acme/api/issues/12

# 5. Push and open draft PR with tasks in body (rules 14-16)
git push -u origin feat/add-search-endpoint
```

**Forgejo:**

```bash
fj pr create "WIP: feat(api): add search endpoint" \
  --head feat/add-search-endpoint --base main \
  --body "$(cat <<'EOF'
# Goal

Add a search endpoint to the API so users can query items by keyword.
Closes #12

# Tasks

- [ ] Add search route handler
- [ ] Add input validation
- [ ] Add integration tests
- [ ] Update API documentation

# Changes

(to be filled during implementation)

# Demo

(to be filled before review)
EOF
)"
```

**GitHub:**

```bash
gh pr create --draft \
  --title "feat(api): add search endpoint" \
  --body "$(cat <<'EOF'
# Goal

Add a search endpoint to the API so users can query items by keyword.
Closes #12

# Tasks

- [ ] Add search route handler
- [ ] Add input validation
- [ ] Add integration tests
- [ ] Update API documentation

# Changes

(to be filled during implementation)

# Demo

(to be filled before review)
EOF
)"
gh pr edit 34 --repo acme/api --milestone "v1.0"
```

```bash
# 6. Implement in the worktree, committing early and often (rules 21-22)
git add src/routes/search.ts
git commit -m "feat(api): add search route handler"

git add src/routes/search.test.ts
git commit -m "test(api): add search integration tests"

# 7. Update PR body — check off all tasks (rule 23)
# Forgejo: fj pr edit <number> --body "..." or use the web UI
# GitHub: gh pr edit <number> --body "..."

# 8. Remove WIP prefix / mark ready, assign reviewer (rules 24-25)
# Forgejo: edit PR title to remove "WIP: " prefix, then assign reviewer
# GitHub: gh pr ready <number>, then request Copilot review

# 9. Address review feedback, squash merge (rules 27-29)
# Forgejo: fj pr merge <number> --method squash --delete
# GitHub: gh pr merge <number> --squash --delete-branch

# 10. Clean up worktree after merge
cd "$HOME/repos/acme/api"
git worktree remove "$HOME/repos/acme/api/worktrees/feat/add-search-endpoint"

# 11. Post demo artifacts on the issue (rule 32)
```
