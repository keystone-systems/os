<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->

# Convention: PR Review Response (process.pr-review-response)

This convention defines how an agent responds to reviewer feedback on PRs it has authored. It covers fetching review comments, addressing each one, pushing fixes, replying on the PR, and re-requesting review. It applies to both GitHub and Forgejo.

**Platform** refers to the git hosting service (GitHub or Forgejo).

## Fetching Review Comments

1. Before acting on review feedback, agents MUST fetch the full review comments from the platform API. The task description is a summary and MAY not contain complete context. The fetch scripts intentionally omit bulky fields like `diff_hunk` to keep the ingest payload small — the executing agent MUST fetch these directly.

**GitHub:**

```bash
gh api repos/{owner}/{repo}/pulls/{number}/reviews --jq '[.[] | select(.state == "CHANGES_REQUESTED" or .state == "COMMENTED") | {id: .id, reviewer: .user.login, state: .state}]'

# For each review, fetch line-level comments (includes diff_hunk for context):
gh api repos/{owner}/{repo}/pulls/{number}/reviews/{review_id}/comments --jq '[.[] | {id: .id, path: .path, body: .body, diff_hunk: .diff_hunk}]'
```

**Forgejo:**

```bash
curl -sf -H "Authorization: token $FORGEJO_TOKEN" \
  "$FORGEJO_HOST/api/v1/repos/{owner}/{repo}/pulls/{number}/reviews" \
  | jq '[.[] | select(.state == "REQUEST_CHANGES" or .state == "COMMENT") | {id: .id, reviewer: .user.login, state: .state}]'

# For each review, fetch line-level comments (includes diff_hunk for context):
curl -sf -H "Authorization: token $FORGEJO_TOKEN" \
  "$FORGEJO_HOST/api/v1/repos/{owner}/{repo}/pulls/{number}/reviews/{review_id}/comments" \
  | jq '[.[] | {id: .id, path: .path, body: .body, diff_hunk: .diff_hunk}]'
```

## Checking Out the Branch

2. Agents MUST check out the PR branch before making changes. If the repo is already cloned locally, agents MUST use an external worktree at `$HOME/repos/{owner}/{repo}/worktrees/{branch}` per `process.git-repos`:

```bash
cd {repo-root}
git fetch origin
git worktree add "$HOME/repos/{owner}/{repo}/worktrees/{branch}" origin/{branch}
cd "$HOME/repos/{owner}/{repo}/worktrees/{branch}"
```

3. If the PR branch has been deleted or the PR is merged/closed, agents MUST skip the task and mark it as `completed` with a note that the PR is no longer actionable.

## Addressing Comments

4. Agents MUST address every review comment — either by pushing a fix commit or by replying with an explanation of why the feedback was not applied.
5. Fix commits MUST be regular commits (not force-pushes) that preserve review history.
6. Each fix commit SHOULD reference the file and concern being addressed in the commit message (e.g., `fix(api): null check per review feedback on handler.ts:34`).
7. `CHANGES_REQUESTED` reviews SHOULD be addressed before `COMMENTED` reviews.

## Replying to Comments

8. After addressing a comment, agents MUST reply to that review comment on the PR describing the fix applied or the reason the feedback was not applied.

**GitHub:**

```bash
gh api repos/{owner}/{repo}/pulls/{number}/comments/{comment_id}/replies \
  -f body="Fixed in <commit-sha>: added null check as suggested."
```

**Forgejo:**

```bash
curl -sf -X POST -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  "$FORGEJO_HOST/api/v1/repos/{owner}/{repo}/pulls/{number}/comments/{comment_id}/replies" \
  -d '{"body": "Fixed in <commit-sha>: added null check as suggested."}'
```

9. Agents MUST NOT leave review comments unresolved — every comment MUST receive either a fix or an explanation.

## Pushing and Re-requesting Review

10. After all comments are addressed, agents MUST push the fix commits to the PR branch.
11. Agents MUST re-request review from the original reviewer(s).

**GitHub:**

```bash
git push origin {branch}
gh pr edit {number} --repo {owner}/{repo} --add-reviewer {reviewer}
```

**Forgejo:**

```bash
git push origin {branch}
# Re-request via API
curl -sf -X POST -H "Authorization: token $FORGEJO_TOKEN" \
  -H "Content-Type: application/json" \
  "$FORGEJO_HOST/api/v1/repos/{owner}/{repo}/pulls/{number}/requested_reviewers" \
  -d '{"reviewers": ["{reviewer}"]}'
```

## Notification Hygiene

12. After addressing all review comments on a PR, agents MUST mark the corresponding notification as read to prevent duplicate task creation in the next task loop run.

**GitHub:**

```bash
# Find the notification thread ID
THREAD_ID=$(gh api '/notifications?participating=true&all=true' \
  --jq ".[] | select(.subject.url | endswith(\"pulls/{number}\")) | .id")
gh api -X PATCH "/notifications/threads/$THREAD_ID"
```

**Forgejo:**

```bash
# Mark notification as read
NOTIF_ID=$(curl -sf -H "Authorization: token $FORGEJO_TOKEN" \
  "$FORGEJO_HOST/api/v1/notifications?limit=100" \
  | jq -r ".[] | select(.subject.url | endswith(\"pulls/{number}\")) | .id")
curl -sf -X PATCH -H "Authorization: token $FORGEJO_TOKEN" \
  "$FORGEJO_HOST/api/v1/notifications/threads/$NOTIF_ID"
```

## Interaction with Existing Conventions

13. This convention extends `process.feature-delivery` rule 25 for human reviewer feedback (not just Copilot).
14. The comment resolution rules (fix or explain every comment) are consistent with `process.copilot-agent` rules 13-15.
15. Agents operating in the `code-reviewer` role (reviewing others' PRs) follow `process.code-review-ownership` instead — this convention applies only to the **author** side.

## Golden Example

```
1. Task loop discovers: github-pr-review on PR #42, reviewer=ncrmro,
   state=CHANGES_REQUESTED, 2 comments (src/api.ts:34, src/api.ts:78)
2. Ingest creates task: address-review-fix-login-42
   source_ref: https://github.com/ncrmro/catalyst/pull/42#reviews
3. Agent checks out branch:
   cd $HOME/repos/ncrmro/catalyst
   git worktree add "$HOME/repos/ncrmro/catalyst/worktrees/fix/login-bug" origin/fix/login-bug
4. Agent fetches full review comments via gh api
5. Agent reads src/api.ts, addresses both comments with fix commits
6. Agent replies to both review comments on PR
7. Agent pushes, re-requests review from ncrmro
8. Agent marks notification as read
9. Task marked completed
```
