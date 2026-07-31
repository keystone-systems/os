---
description: Run DeepWork .deepreview rules against the current changes and fix findings
argument-hint: [optional focus]
---

Run the DeepWork review system against the current changes.

Use the DeepWork MCP tools directly:

1. Call `mcp__deepwork__get_review_instructions`
   - If the user gave extra context in `$ARGUMENTS`, use it to focus your review and fixes
   - Otherwise review the current branch diff or current worktree changes
2. Execute all returned review tasks
   - Prefer parallel execution when multiple review tasks are returned
3. Collect findings and act on them
   - Fix obviously correct issues immediately
   - For substantive issues, inspect the affected files, apply fixes, and verify them
   - If a finding is not applicable, document a brief justification
4. Re-run affected reviews until all findings are fixed or explicitly justified
5. Summarize:
   - which reviews ran
   - what findings were fixed
   - what findings were skipped with justification
   - whether the final review state is clean

This is a standalone DeepWork review entrypoint, not a full workflow. Use it when the user asks to review current changes, run `.deepreview` checks, or clean up review findings before commit or merge.
