# REQ-024: PR Review Response

Keystone agents author PRs as part of engineering workflows, but currently lack
a convention and ingest guidance for acting on reviewer feedback received on
those PRs. The fetch scripts (`fetch-github-sources`, `fetch-forgejo-sources`)
already discover review comments via the notifications API, and the task loop
passes them to the ingest step. However, the ingest step has no explicit
handling for `github-pr-reviews` / `forgejo-pr-reviews` data, so Haiku may
create vague or missing tasks. There is also no convention telling the
executing agent how to check out the branch, address each comment, push fixes,
and reply on the PR.

This spec closes the loop: reviews are ingested as first-class tasks, executed
via a defined convention, and dismissed from the notifications queue to prevent
duplicates.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## User Story

As an OS agent that authors PRs, I want review feedback to be automatically
ingested as actionable tasks with full comment context so that I can address
each reviewer comment, push fixes, and re-request review without human
intervention.

## Architecture

```
                          GitHub / Forgejo
                          ┌──────────────────────────────────┐
                          │  PR #42 (agent-authored)         │
                          │  ┌─────────────────────────────┐ │
                          │  │ Review: CHANGES_REQUESTED   │ │
                          │  │  comment: src/api.ts:34     │ │
                          │  │  comment: src/api.ts:78     │ │
                          │  └─────────────────────────────┘ │
                          └──────────┬───────────────────────┘
                                     │ notifications API
                                     ▼
┌─────────────────────────────────────────────────────────────┐
│  fetch-{github,forgejo}-sources                             │
│  Phase 4: PR reviews on agent-authored PRs                  │
│  Output: { "github-pr-reviews": [...] }                     │
└──────────┬──────────────────────────────────────────────────┘
           │ JSON
           ▼
┌─────────────────────────────────────────────────────────────┐
│  task-loop.sh → Step 2: Ingest (Haiku)                      │
│  parse_sources step (job.yml)                               │
│                                                             │
│  NEW: Explicit pr-review handling                           │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ source: "github-pr-review"                             │ │
│  │ source_ref: "{pr_url}#review-{review_id}"              │ │
│  │ description: includes repo, branch, file paths,        │ │
│  │              comment bodies, review state               │ │
│  │ workflow: "review/respond" (if available)               │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────┬──────────────────────────────────────────────────┘
           │ TASKS.yaml
           ▼
┌─────────────────────────────────────────────────────────────┐
│  task-loop.sh → Step 4: Execute                             │
│                                                             │
│  Convention: process.pr-review-response                     │
│  1. Clone/checkout repo + branch                            │
│  2. Fetch full review comments via API                      │
│  3. Address each comment (fix or explain)                   │
│  4. Push fix commits                                        │
│  5. Reply to each review comment on PR                      │
│  6. Re-request review                                       │
│  7. Dismiss notification                                    │
└─────────────────────────────────────────────────────────────┘
```

## Affected Modules

- `conventions/process.pr-review-response.md` — **new** convention for responding to PR review feedback
- `.deepwork/jobs/task_loop/job.yml` — add explicit PR review ingest rules to the `parse_sources` step
- `packages/fetch-github-sources/bin/fetch-github-sources` — add `pr_branch` field to review output
- `packages/fetch-forgejo-sources/bin/fetch-forgejo-sources` — add `pr_branch` field to review output
- `conventions/process.feature-delivery.md` — update rule 25 to reference `process.pr-review-response`
- `conventions/archetypes.yaml` — wire `process.pr-review-response` into relevant archetypes

## Requirements

### Fetch Script Enrichment

**REQ-024.1** `fetch-github-sources` MUST include the PR's `head.ref` (branch name) in each review entry as the `pr_branch` field.

**REQ-024.2** `fetch-forgejo-sources` MUST include the PR's `head.ref` (branch name) in each review entry as the `pr_branch` field.

**REQ-024.3** Fetch scripts MUST NOT include bulky fields like `diff_hunk` in review comment output. The executing agent fetches full review context (including diff hunks) directly from the platform API at execution time.

### Ingest (parse_sources step)

**REQ-024.4** The ingest step MUST recognize `github-pr-reviews` and `forgejo-pr-reviews` as distinct source categories in the pre-fetched JSON.

**REQ-024.5** For each PR review entry, the ingest step MUST create a task with:

- `source`: `"github-pr-review"` or `"forgejo-pr-review"`
- `source_ref`: `"{pr_url}#review-{review_id}"` (unique per review, enables deduplication)
- `name`: kebab-case derived from the PR title (e.g., `address-review-fix-login-bug-42`)
- `description`: MUST include the repo, PR number, branch name, reviewer, review state, and a summary of each comment (file path + body). The description MUST preserve enough context for the executing agent to act without re-fetching the review.

**REQ-024.6** Reviews with state `CHANGES_REQUESTED` (GitHub) or `REQUEST_CHANGES` (Forgejo) MUST be ingested as tasks. Reviews with state `COMMENTED` SHOULD be ingested only if they contain actionable comments (not purely informational).

**REQ-024.7** The ingest step MUST deduplicate PR reviews by `source_ref`. If a task already exists for a given `{pr_url}#review-{review_id}`, the review MUST NOT create a duplicate task.

**REQ-024.8** When multiple reviews exist on the same PR, the ingest step SHOULD consolidate them into a single task per PR (keyed by `{pr_url}`) rather than one task per review, to avoid redundant branch checkouts. The `source_ref` for a consolidated task MUST use the PR URL (e.g., `"{pr_url}#reviews"`).

### Convention: process.pr-review-response

**REQ-024.9** A new convention `process.pr-review-response` MUST define the end-to-end flow for an agent responding to review feedback on its authored PRs.

**REQ-024.10** The convention MUST require agents to address every review comment — either by pushing a fix commit or by replying with an explanation of why the feedback was not applied (consistent with `process.copilot-agent` rules 13-15).

**REQ-024.11** The convention MUST require agents to fetch the full review comments from the platform API before acting, since the task description is a summary and MAY not contain complete context.

**REQ-024.12** The convention MUST require agents to push fix commits (not force-pushes) that reference the review comment being addressed.

**REQ-024.13** The convention MUST require agents to reply to each review comment on the PR with a description of the fix applied or the reason the feedback was not applied.

**REQ-024.14** The convention MUST require agents to re-request review from the original reviewer after addressing all comments.

**REQ-024.15** The convention MUST require agents to mark the notification as read after addressing the review, to prevent the next task loop run from creating a duplicate task.

**REQ-024.16** The convention SHOULD specify that `CHANGES_REQUESTED` reviews take priority over `COMMENTED` reviews.

**REQ-024.17** The convention MUST include platform-specific commands for both GitHub (`gh`) and Forgejo (`fj` / `curl`) for fetching comments, replying, re-requesting review, and dismissing notifications.

### Integration

**REQ-024.18** `process.feature-delivery` rule 25 MUST be updated to reference `process.pr-review-response` for human reviewer feedback, in addition to the existing `process.copilot-agent` reference for Copilot feedback.

**REQ-024.19** `conventions/archetypes.yaml` MUST wire `process.pr-review-response` into the `engineer` archetype (and any other archetype that authors PRs) as a referenced convention.

### Notification Hygiene

**REQ-024.20** After an agent addresses all review comments on a PR, it MUST mark the corresponding GitHub notification as read via `gh api -X PATCH /notifications/threads/{thread_id}` (or the Forgejo equivalent).

**REQ-024.21** The fetch scripts MUST NOT filter out already-read notifications in the current design (`all=true` parameter is intentional for discovery). Deduplication MUST happen at the ingest layer via `source_ref` matching.

### Edge Cases

**REQ-024.22** If the PR branch has been deleted or the PR is already merged/closed, the agent MUST skip the review task and mark it as `completed` with a note that the PR is no longer actionable.

**REQ-024.23** If the agent cannot push to the PR branch (e.g., permission denied, branch protection), the task MUST be marked `blocked` with a description of the access issue.

**REQ-024.24** If a reviewer leaves a review with no comments (body-only review), the agent MUST still create a task if the review state is `CHANGES_REQUESTED`.

## References

- `packages/fetch-github-sources/bin/fetch-github-sources` — Phase 4 (lines 68-115)
- `packages/fetch-forgejo-sources/bin/fetch-forgejo-sources` — equivalent review discovery
- `.deepwork/jobs/task_loop/job.yml` — ingest step instructions (`parse_sources`)
- `conventions/process.copilot-agent.md` — rules 10-15 (responding to Copilot feedback)
- `conventions/process.code-review-ownership.md` — reviewer assignment via CODEOWNERS
- `conventions/process.feature-delivery.md` — rule 25 (addressing review feedback)
- `conventions/process.pr-review-response.md` — the reviewer-side response flow
