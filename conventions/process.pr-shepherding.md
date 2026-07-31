<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->

# Convention: PR Shepherding (process.pr-shepherding)

Agents MUST act with agency when delivering pull requests. Shepherding means
the agent owns the PR lifecycle end-to-end — from draft creation through merge
verification — without waiting for the user to nudge each step forward.

## Draft-First Delivery

1. PRs MUST be pushed as drafts initially (`--draft` on GitHub, `WIP:` prefix
   on Forgejo) per `process.feature-delivery` rule 14.
2. The agent MUST NOT undraft a PR until CI is green on the latest push.

## CI Stabilization

3. After every push, the agent MUST watch CI to completion per
   `process.continuous-integration` rule 2.
4. If CI fails, the agent MUST diagnose and fix per the CI failure loop
   (`process.continuous-integration` rules 11-15) before proceeding.
5. The agent MUST NOT undraft, request review, or merge while checks are
   in progress or failing.

## Issue Linkage

6. Every PR MUST link its originating issue in the body. Orphan PRs (no
   issue) MUST NOT be opened — create the issue first.
7. Closing keywords (`Closes #N`, `Fixes #N`, `Resolves #N`, case-insensitive)
   MUST be used ONLY when this PR fully resolves the referenced issue. On
   merge, the forge auto-closes the issue.
8. Plain references (`#N`, or the human-readable `Part of #N` /
   `Contributes to #N`) MUST be used when the PR implements only part of the
   issue, or is one of several PRs under a tracking issue or epic. The issue
   MUST remain open after merge so remaining work stays visible.
9. If multiple issues are addressed, each MUST be referenced explicitly. The
   closing-vs-plain rule applies per issue — a single PR MAY close one issue
   while plain-referencing another.
10. Cross-repo refs MUST use `owner/repo#N` (GitHub) or `org/repo#N`
    (Forgejo). Bare `#N` is ambiguous across repos.

## Milestone Assignment

11. When a milestone exists for the current work stream, the PR and its
    originating issue MUST be assigned to it. Milestones are the unit of
    stakeholder-visible progress — an unassigned PR is invisible on the
    project board (see `process.project-board`).
12. Milestones have NO closing keyword. Assignment is via the milestone field
    on the PR/issue (`gh pr edit N --milestone "<name>"`,
    `gh issue edit N --milestone "<name>"`), NOT the PR body.
13. Forges close milestones only when every contained issue is closed —
    merging a PR does not close its milestone directly.
14. If no milestone fits, the engineering agent MUST check with the product
    agent before creating one. Milestones are a product artifact owned by the
    product archetype (see `process.agentic-team`), not an engineering
    convenience.

## Undraft and Review

15. Once CI is green and all PR-body tasks are checked off, the agent MUST
    mark the PR ready for review (`gh pr ready` on GitHub, remove `WIP:`
    prefix on Forgejo).
16. The agent MUST request reviewers per `process.code-review-ownership`.
    Copilot SHOULD also be requested as a supplementary reviewer per
    `process.copilot-agent`.
17. The agent MUST watch for review feedback and address every comment per
    `process.pr-review-response` — fixing or explaining each one, replying
    on the PR, and re-requesting review.
18. After pushing review fixes, the agent MUST re-watch CI to green before
    re-requesting review.

## Merge

19. When CI is green and approval exists, the agent SHOULD enable auto-merge
    via `gh pr merge --auto --squash --delete-branch` on GitHub, or merge
    explicitly on Forgejo per `process.continuous-integration` rules 23-24.
20. If the repository uses a merge queue, the agent MUST wait for the PR to
    enter and exit the queue successfully — not just for the merge button.
21. When the user has requested merge, the agent MUST stay engaged through
    the full merge lifecycle (queue entry, queue exit, default branch
    verification) and confirm completion.

## Post-Merge Verification

22. After merge, the agent MUST verify that the default branch CI is green
    on the merge commit. If post-merge CI fails, the agent MUST flag it
    immediately.
23. If the repository has a deploy pipeline, the agent SHOULD watch for
    successful deployment and report the outcome.
24. The agent MUST clean up the worktree after merge per
    `process.feature-delivery`.
