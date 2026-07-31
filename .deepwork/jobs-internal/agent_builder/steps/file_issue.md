# File Issue

## Objective

Create the GitHub issue on ncrmro/keystone using the draft from the previous step.

## Inputs

- `issue_draft.md` from `draft_issue` — contains the title, body, labels, and assignee

## Task

### 1. Parse the draft

Read `issue_draft.md` and extract:

- Title (from the `## Metadata` section)
- Body (the `## Body` section content)
- Labels (from metadata)
- Assignee (should be `ncrmro`)

### 2. Create the issue

```bash
gh issue create \
  --repo ncrmro/keystone \
  --title "{title}" \
  --body "$(cat <<'EOF'
{body content}
EOF
)" \
  --assignee ncrmro \
  --label "{label1},{label2}"
```

If a label doesn't exist on the repo, create it first or omit it and note in the output.

### 3. Record the result

Capture the issue URL returned by `gh issue create`.

## Output Format

Write `issue_url.md`:

```markdown
# Issue Filed

- **Issue:** #{number}
- **URL:** {url}
- **Repo:** ncrmro/keystone
- **Assigned to:** ncrmro
- **Labels:** {labels applied}
- **Title:** {title}
```

## Quality Criteria

- The issue was successfully created on GitHub (URL is valid)
- The issue is assigned to ncrmro
- The output includes the issue number and URL

## Context

This is the final step. After filing, the agent should reference this issue number when discussing the problem in other contexts (e.g., task comments, status updates).
