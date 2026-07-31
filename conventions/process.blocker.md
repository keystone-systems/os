<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->

# Convention: Blocker Escalation (process.blocker)

This convention defines how agents identify, report, and recover from platform and infrastructure blockers that prevent task completion.

## Identifying Blockers

1. A blocker MUST be declared when an agent cannot proceed due to a platform, infrastructure, or ops issue outside the task's feature scope.
2. Blocker categories include:
   - **Infrastructure/OS**: missing package, config change, service misconfiguration, environment issue.
   - **Project ops**: broken CI pipeline, dependency conflict, build tooling failure, database migration issue.
   - **External dependency**: upstream bug or incompatibility in a public repo that affects a project.
3. Blockers MUST NOT be declared for feature-scope issues — implementation failures are task failures (max 3 attempts per `process.feature-delivery`), not blockers.

## Filing Blocker Issues

4. Agents MUST only file issues in internal repos owned by the organization — agents MUST NOT create issues on external or public open-source repos.
5. If a blocker originates from an external/public project, the agent MUST file an internal issue documenting the problem and assign it to the human operator (see `TEAM.md`), who decides whether to file upstream.
6. Target repo for the internal issue MUST be selected as follows:
   - Infrastructure/OS issues → the infrastructure repo (e.g., `{org}/{infra-repo}`).
   - Project-specific ops issues → the project's own repo.
   - External dependency issues → the internal repo that depends on it, with a reference to the upstream repo.
7. The issue title MUST follow conventional format: `fix(scope): description of blocker`.
8. The issue body MUST include:
   - **What is blocked**: link to the task, PR, or issue that cannot proceed.
   - **Root cause**: the platform or infra problem preventing progress.
   - **Error evidence**: error messages, log excerpts, or reproduction steps.
   - **External reference** (if applicable): link to the public repo, upstream issue, or relevant documentation.
   - **Suggested fix** (if known): what change would unblock the agent.

## Labeling and Board Management

9. The blocker issue MUST be labeled `blocked`.
10. The original task's issue (if it has one) MUST also be labeled `blocked`.
11. The original task's project board item MUST be moved to "Backlog" per `process.project-board`.
12. TASKS.yaml MUST be updated: set the blocked task's status to `blocked` with a `blocker_ref` noting the blocker issue URL.

## Handoff and Notification

13. The blocker issue MUST be assigned to the appropriate person — infrastructure issues to the human operator (see `TEAM.md`), project ops issues to the repo owner.
14. A comment MUST be posted on the blocked task's issue (if it has one) linking to the blocker issue and explaining the dependency. See `process.vcs-context-continuity` for standards on documenting environmental difficulties.
15. The agent SHOULD send a brief email notification to the assignee via himalaya per `tool.himalaya`.

## Resuming After Unblock

16. When a blocker issue is closed, the agent MUST verify the fix is available in the environment before resuming.
17. After verification, the agent MUST:

- Update the task's status from `blocked` to `pending` in TASKS.yaml.
- Remove the `blocked` label from the original task's issue.
- Move the task's project board item to "To Do" per `process.project-board`.

18. The task SHOULD be picked up in the next task loop iteration.
19. Agents SHOULD monitor blocker issues for resolution by checking issue status during task loop runs.

## Golden Example

Agent cannot access the platform CLI token from its environment, blocking issue creation for task #42 on `{org}/{project}`:

```bash
# 1. Agent hits blocker: CLI fails due to missing auth
#    Error: "authentication required"

# 2. File blocker issue on the infrastructure repo (rule 6)
gh issue create --repo {org}/{infra-repo} \
  --title "fix(agent-env): mount CLI auth token into agent environment" \
  --label "blocked" \
  --assignee {operator} \
  --body "$(cat <<'EOF'
## What is blocked

[Issue #42]({org}/{project}/issues/42) — agent cannot
create issues or PRs due to missing CLI credentials.

## Root cause

The agent environment does not have access to the CLI auth token.

## Error evidence

```

$ gh issue create --repo {org}/{project} --title "test"
error: authentication required

```

## Suggested fix

Mount the CLI config into the agent environment read-only.
EOF
)"

# 3. Label the original task issue as blocked (rule 10)
gh issue edit 42 --repo {org}/{project} --add-label "blocked"

# 4. Comment on the original task issue (rule 14)
gh issue comment 42 --repo {org}/{project} \
  --body "Blocked by {org}/{infra-repo}#NEW — CLI auth not available in agent environment."

# 5. Move task board item to Backlog (rule 11)
# gh project item-edit ...

# 6. Update TASKS.yaml (rule 12)
# status: blocked, blocker_ref: {org}/{infra-repo}/issues/NEW

# --- After the fix is merged and deployed ---

# 7. Verify fix (rule 16)
gh auth status  # confirms CLI is now authenticated

# 8. Resume (rule 17)
gh issue edit 42 --repo {org}/{project} --remove-label "blocked"
# Update TASKS.yaml status: pending
# Move board item to "To Do"
# Task picked up in next task loop run
```
