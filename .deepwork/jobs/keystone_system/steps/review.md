# Review

## Objective

Run DeepWork `.deepreview` rules against the worktree changes and fix all findings before proceeding to build.

## Task

Use the DeepWork review system to validate the changes made in the implement step. Fix all actionable findings, document any skipped findings with justification.

### Process

1. **Run the reviews**
   - Call `mcp__deepwork__get_review_instructions` (no arguments — it auto-detects the branch diff)
   - This returns review tasks to run in parallel

2. **Execute all review tasks**
   - Launch each review task as a parallel sub-agent
   - Collect all findings

3. **Act on findings**
   - **Obviously correct fixes** (typos, missing imports, formatting): fix immediately
   - **Substantive findings** (architectural issues, missing tests, spec drift): fix in the worktree and commit
   - **False positives or not applicable**: document why in the review report

4. **Re-run until clean**
   - After fixing findings, re-run the reviews
   - Repeat until all reviews pass or remaining findings are explicitly skipped with justification
   - Only reviews that had findings need re-running

5. **Document results**
   - Record what was found and how each finding was resolved

## Output Format

### review_report.md

```markdown
# Review Report

## Reviews Run

- [review_name_1]: [PASSED | X findings]
- [review_name_2]: [PASSED | X findings]

## Findings Addressed

### Finding: [brief description]

- **Review**: [which review rule]
- **Action**: Fixed — [what was changed]
- **Commit**: `<hash>` — `<message>`

### Finding: [brief description]

- **Review**: [which review rule]
- **Action**: Skipped — [justification for why this is not applicable]

## Final Status

- **Total findings**: X
- **Fixed**: Y
- **Skipped**: Z (with justification)
- **All reviews passing**: [yes/no]
```

## Quality Criteria

- Every review finding is either fixed or has a documented justification for skipping
- Fixes are committed in the worktree with descriptive commit messages
- The final review run shows all reviews passing (or only skipped findings remain)

## Context

This is the quality gate before build. Catching issues here (docs drift, spec mismatches, code style) is much cheaper than finding them after merge and deploy. The review rules in `.deepreview` are specifically tuned for keystone conventions.
