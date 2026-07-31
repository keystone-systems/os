# Convention: Pull Request (process.pull-request)

Standards for summarizing work and providing validation evidence in pull requests.
See `process.prose` for general writing style and clarity rules.

## Required Sections

1. Every PR description MUST include three sections: **Goal**, **Changes**, and **Demo**.
2. The **Goal** section MUST state what the PR achieves and why.
3. The **Changes** section MUST summarize what was modified.
4. The **Demo** section MUST provide evidence that the work is correct and instructions for validation. Evidence MUST be updated in real-time as implementation progresses (see `process.vcs-context-continuity`).

## Demo Section

5. The demo SHOULD include a preview environment link when feasible.
6. The demo MUST include screenshots and/or video of the result.
7. The demo MUST include specific instructions for a human or agent to recreate and validate the work.
8. For CLI tool changes, terminal output SHOULD be included as a code block.
9. For infrastructure changes where screenshots are not applicable, reproduction commands MUST be provided.

## Merge Strategy

10. PRs MUST be squash merged — not regular merge or rebase merge.
11. The agent MUST review the PR content before merging.

## General

12. The PR title MUST be concise (under 70 characters) — use the description for details.
13. The Goal section SHOULD NOT restate the diff — explain the motivation, not the mechanics.
14. The Demo section MUST NOT rely solely on "tests pass" — demonstrate observable behavior.
