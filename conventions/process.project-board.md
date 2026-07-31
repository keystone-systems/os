<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->

# Convention: Project Board (process.project-board)

This convention defines how project boards (Kanban boards) are created, populated, and maintained to track milestone progress.

## Board Lifecycle

1. One project board MUST exist per milestone.
2. The board MUST be created when the milestone is set up.
3. The board MUST be closed or archived when the milestone is closed.

## Standard Columns

4. Every board MUST use these five columns:

| Column      | Meaning                             |
| ----------- | ----------------------------------- |
| Backlog     | Issue exists, not yet prioritized   |
| To Do       | Prioritized and ready to pick up    |
| In Progress | Branch created, active work         |
| In Review   | Non-draft PR open, review requested |
| Done        | Issue closed / PR merged            |

## Transition Rules

5. Issues MUST progress through columns as work advances. The mechanism depends on the platform:

| Event                       | From → To               | GitHub                                    | Forgejo                            |
| --------------------------- | ----------------------- | ----------------------------------------- | ---------------------------------- |
| Issue added to milestone    | → Backlog               | Agent: `gh project item-add` + set status | Agent: `forgejo-project item add`  |
| Issue prioritized for work  | Backlog → To Do         | Agent: `gh project item-edit`             | Agent: `forgejo-project item move` |
| Branch created, work starts | To Do → In Progress     | Agent: `gh project item-edit`             | Agent: `forgejo-project item move` |
| PR marked ready for review  | In Progress → In Review | Agent: `gh project item-edit`             | Agent: `forgejo-project item move` |
| PR merged / issue closed    | → Done                  | **Automatic** (built-in workflow)         | Agent: `forgejo-project item move` |

6. Agents MUST NOT duplicate automatic transitions — if the platform handles a transition, the agent MUST NOT also fire it.

## GitHub Built-in Automations

7. GitHub Projects V2 includes three default workflows that MAY be enabled:
   - **Item closed** → status set to Done (enabled by default)
   - **PR merged** → status set to Done (enabled by default)
   - **Auto-add** → items from linked repos auto-added (configurable)

8. Agents SHOULD enable the "Item closed" and "PR merged" workflows when creating a new board.
9. Agents SHOULD enable the "Auto-add" workflow and configure it for the milestone's repository.

## GitHub CLI Reference

10. The `project` scope MUST be granted before using project commands: `gh auth refresh -s project`.

11. Board creation and management commands:

```bash
# Create board
gh project create --owner {owner} --title "{Milestone}" --format json

# Link to repo
gh project link {number} --owner {owner} --repo {owner}/{repo}

# Get field/option IDs (needed for status changes)
gh project field-list {number} --owner {owner} --format json

# Add item
gh project item-add {number} --owner {owner} --url {issue_url} --format json

# Change status (requires project-id, field-id, option-id)
gh project item-edit --id {item-id} --project-id {project-id} \
  --field-id {status-field-id} --single-select-option-id {option-id}

# List items
gh project item-list {number} --owner {owner} --format json

# View project
gh project view {number} --owner {owner} --format json
```

12. The status field ID and option IDs MUST be looked up via `gh project field-list` before setting statuses. These IDs are project-specific and MUST NOT be hardcoded.

## Forgejo Automation

13. Forgejo has **no project board REST API**, but all board operations are automatable via the `forgejo-project` CLI which calls the web UI's internal HTTP routes with session cookie auth.
14. Agents MUST use `forgejo-project` for all board operations on Forgejo repos — see `tool.forgejo` for full CLI reference.
15. Agents MUST set `FORGEJO_HOST`, `FORGEJO_USER`, and `FORGEJO_PASSWORD_CMD` environment variables. The script auto-authenticates on first use.
16. Unlike GitHub, Forgejo has **no built-in board automations** — agents MUST handle all transitions (including issue close → Done) explicitly.

## Doctor Checklist

17. Every milestone issue MUST have a corresponding board item.
18. Closed issues MUST be in the Done column.
19. Issues with open draft PRs SHOULD be in In Progress.
20. Issues with non-draft PRs and requested reviewers SHOULD be in In Review.
21. Issues with no associated PR SHOULD be in Backlog or To Do.
