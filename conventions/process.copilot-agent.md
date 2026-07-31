## Copilot Agent

## Assigning Copilot to Issues

1. Copilot MAY be assigned to an issue via `gh issue edit <number> --repo <owner>/<repo> --add-assignee @copilot`.
2. Before assigning, agents MUST check existing assignees via `gh issue view <number> --repo <owner>/<repo> --json assignees` to avoid duplicate assignment.

## Requesting Reviews

3. Before requesting a review, agents MUST check existing reviewers via `gh pr view <number> --repo <owner>/<repo> --json reviewRequests` to avoid duplicate requests.
4. Copilot reviews MUST be requested by commenting `@copilot review this PR` on the pull request when the agent lacks reviewer-request permissions on the upstream repo.
5. If the agent has reviewer-request permissions, Copilot reviews SHOULD be requested via `gh pr edit <number> --repo <owner>/<repo> --add-reviewer copilot`.
6. Copilot reviews MUST only be requested on PRs that have been pushed to a remote.

## Reading Review Feedback

7. Copilot review comments MUST be fetched via `gh api repos/{owner}/{repo}/pulls/{number}/comments` or `gh pr view <number> --repo <owner>/<repo> --comments`.
8. Copilot review status MUST be checked via `gh pr checks <number> --repo <owner>/<repo>` or `gh pr view <number> --repo <owner>/<repo> --json reviews`.
9. Agents SHOULD wait for the Copilot review to complete before acting on feedback — reviews are asynchronous and may take a few minutes.

## Responding to Feedback

10. Agents MUST address Copilot review comments by pushing fix commits, not by dismissing or ignoring them.
11. After pushing fixes, agents SHOULD re-request review by commenting `@copilot review this PR` again.
12. Agents MUST NOT force-push to rewrite history that Copilot has already reviewed.

## Resolving Review Conversations

13. When a review comment is addressed by a fix commit, agents MUST resolve the conversation by replying with a comment that describes the fix applied and any nuance encountered (e.g., edge cases discovered, pre-existing issues found, or deviations from the suggestion).
14. When a review comment is intentionally skipped, agents MUST reply with a comment explaining why (e.g., the suggestion is incorrect, the issue is pre-existing and out of scope, or the proposed fix would introduce a regression).
15. Agents MUST NOT leave review conversations unresolved — every comment MUST receive either a fix or an explanation.

## Capabilities

Copilot can review PRs, be assigned to issues, and respond to `@copilot` mentions in PR comments. Availability depends on the repository's GitHub plan and Copilot access settings.

16. Copilot MAY be invoked via `@copilot` in any PR comment to ask questions or request specific analysis.
17. Copilot MAY be assigned issues to work on — it can generate code, open PRs, and iterate on feedback.

## Limitations

18. Copilot availability depends on the GitHub user's account (individual Copilot subscription or org-level enablement) — agents MUST handle permission errors gracefully when Copilot features are unavailable.
19. Copilot reviews MAY miss domain-specific issues — agents SHOULD treat Copilot feedback as supplementary, not authoritative.
20. Copilot MUST NOT be requested as a reviewer on draft PRs unless the agent explicitly intends early feedback.
