## Continuous Integration

## CI Status Checking

1. Before acting on CI results, agents MUST verify that the PR has CI checks configured (`gh pr view --json statusCheckRollup` on GitHub; commit status API on Forgejo).
2. Agents MUST watch CI to completion before proceeding (`gh pr checks --watch` on GitHub).
3. On Forgejo, agents SHOULD poll commit status via `tea api /repos/{owner}/{repo}/commits/{sha}/status` until all checks reach a terminal state.
4. Agents MUST NOT merge or mark a PR ready for review while checks are still in progress.

## CI Log Handling

5. Agents MUST NOT read full CI logs into conversation context — logs MUST be downloaded to a local file and searched offline.
6. On GitHub, logs MUST be downloaded via `gh run view $RUN_ID --log > /tmp/ci-$RUN_ID.log`.
7. On Forgejo, logs SHOULD be downloaded via `fj-ex actions logs job --repo {owner}/{repo} --latest --job-index <index> > /tmp/ci-{owner}-{repo}-job-<index>.log`.
8. If `fj-ex` cannot access the needed Actions endpoint, agents MUST fall back to `tea api` or `curl`.
9. Downloaded logs MUST be searched with `rg` rather than read into chat.
10. Agents SHOULD search logs for these patterns: `error`, `fail`, `fatal`, `FAILED`, `exit code`, `assertion`, `timeout`.

## CI Failure Diagnosis and Fix Loop

11. Before attempting a fix, agents MUST extract the specific error message, suspected root cause, and affected file paths from the downloaded logs.
12. Fix instructions dispatched to sub-agents or Copilot MUST include the error message, suspected cause, and file paths.
13. Each fix attempt MUST be a separate commit per `process.version-control` commit discipline.
14. After each fix push, agents MUST re-watch CI to completion before proceeding.
15. After 3 failed fix attempts on the same PR, agents MUST mark the task as blocked and post a summary of all attempts.

## CI Config Safety Checks

16. Before triggering CI on bot or third-party PRs, agents MUST verify that no CI config files were modified in the PR diff.
17. CI config files include: `.github/workflows/`, `.forgejo/workflows/`, `Makefile`, `.circleci/`, `.gitlab-ci.yml`, `Jenkinsfile`, `.travis.yml`, `Dockerfile`, `docker-compose.*`, `flake.nix`, `flake.lock`.
18. If a bot PR modifies any CI config file, agents MUST flag it for human review and MUST NOT approve.
19. Agents MAY push a dummy commit from the repo owner to bypass a first-time contributor gate, only after the safety check in rule 16 passes.

## Deploy Preview Verification

20. Agents SHOULD check PR comments for deploy preview URLs posted by platform bots (Cloudflare, Vercel, Netlify).
21. Deploy preview verification is informational — agents MUST NOT gate merging on deploy preview status.
22. Screenshots from deploy previews SHOULD be referenced in the PR Demo section per `process.pull-request`.

## Auto-Merge

23. When CI is green and approval exists, agents SHOULD enable auto-merge via `gh pr merge --auto --squash --delete-branch`.
24. On Forgejo (no auto-merge CLI), agents MUST poll CI status and merge explicitly via `fj pr merge` once checks pass.
25. Auto-merge MUST use the squash strategy per `process.feature-delivery`.

## CI Artifact Extraction

26. Agents MAY download CI artifacts via `gh run download` on GitHub, `fj-ex`, or the Forgejo artifacts API.
27. Downloaded artifacts SHOULD be saved to the task working directory for traceability.
28. Agents MUST NOT include binary artifacts in conversation context — reference by file path only.

## Golden Example

End-to-end walkthrough: CI fails on a PR, agent diagnoses and fixes.

### GitHub

```bash
# 1. Verify CI exists on the PR (rule 1)
gh pr view 42 --json statusCheckRollup --jq '.statusCheckRollup'

# 2. Watch CI to completion (rule 2)
gh pr checks 42 --watch
# CI reports failure

# 3. Find the failed run ID
RUN_ID=$(gh run list --branch feat/add-search -L 1 --json databaseId --jq '.[0].databaseId')

# 4. Download logs locally — do NOT read into chat (rules 5-6)
gh run view "$RUN_ID" --log > /tmp/ci-$RUN_ID.log

# 5. Search for errors with rg (rules 8-9)
rg -i 'error|fail|fatal|exit code' /tmp/ci-$RUN_ID.log

# 6. Fix the issue, commit separately (rule 12)
git add src/routes/search.ts
git commit -m "fix(api): handle null query parameter"
git push

# 7. Re-watch CI after the fix (rule 13)
gh pr checks 42 --watch
# CI passes

# 8. Enable auto-merge (rule 22)
gh pr merge 42 --auto --squash --delete-branch
```

### Forgejo

```bash
# 1. Get latest commit SHA for the PR branch
SHA=$(git rev-parse HEAD)

# 2. Poll CI status until terminal (rules 1, 3)
tea api --login forgejo /repos/{owner}/{repo}/commits/$SHA/status
# Repeat until all statuses are success/failure

# 3. Inspect the latest run and queued jobs if needed
fj-ex actions runs --repo {owner}/{repo} --latest
fj-ex actions runners jobs --repo {owner}/{repo} --waiting

# 4. Download logs locally (rules 5, 7-8)
fj-ex actions logs job --repo {owner}/{repo} --latest --job-index 0 > /tmp/ci-{owner}-{repo}-job-0.log

# 5. Search for errors (rules 8-9)
rg -i 'error|fail|fatal|exit code' /tmp/ci-{owner}-{repo}-job-0.log

# 6. Fix, commit, push (rule 12)
git add src/routes/search.ts
git commit -m "fix(api): handle null query parameter"
git push

# 7. Re-poll CI after fix (rule 13)
tea api --login forgejo /repos/{owner}/{repo}/commits/$(git rev-parse HEAD)/status

# 8. Merge explicitly once CI passes (rule 23)
fj pr merge 42 --method squash --delete
```
