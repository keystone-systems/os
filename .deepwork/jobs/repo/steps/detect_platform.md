# Detect Platform

## Objective

Identify the platform, verify CLI authentication, determine the default branch, and inventory existing labels, milestones, and boards.

## Task

### Process

1. **Determine the platform**
   - Parse the `project_repo` input to identify the repo slug and platform
   - If not explicit, check the repo's remote URL or ask the user
   - Platforms: `github` or `forgejo`

2. **Verify CLI authentication**

   **GitHub:**
   - Run `gh auth status` to check current scopes
   - If the `project` scope is missing, run `gh auth refresh -s project`
   - Confirm the authenticated user matches the agent's GitHub username from TEAM.md

   **Forgejo:**
   - Run `fj auth status` or equivalent to verify token
   - Confirm connectivity to `git.ncrmro.com`

3. **Get default branch**
   - GitHub: `gh repo view {owner}/{repo} --json defaultBranchRef --jq '.defaultBranchRef.name'`
   - Forgejo: `tea repo info --login forgejo {owner}/{repo}` or API call

4. **Inventory existing labels**
   - GitHub: `gh label list --repo {owner}/{repo} --json name,color,description`
   - Forgejo: `tea label list --login forgejo --repo {owner}/{repo}`

5. **Inventory milestones**
   - GitHub: `gh api repos/{owner}/{repo}/milestones --jq '.[] | {title, number, state, open_issues, closed_issues}'`
   - Forgejo: `tea milestone list --login forgejo --repo {owner}/{repo}`

6. **Inventory boards** (GitHub only)
   - `gh project list --owner {owner} --format json`
   - If Forgejo, note that board API is unavailable and record `boards_api: false`

## Output Format

### platform_context.md

```markdown
# Platform Context

## Platform

- **Platform**: [github | forgejo]
- **Repository**: [owner/repo]
- **Default Branch**: [main | master | etc.]
- **Auth Status**: [authenticated | needs refresh]
- **Boards API**: [true | false]

## Existing Labels

| Name | Color | Description |
| ---- | ----- | ----------- |
| ...  | ...   | ...         |

## Milestones

| Title | Number | State | Open | Closed |
| ----- | ------ | ----- | ---- | ------ |
| ...   | ...    | ...   | ...  | ...    |

## Boards (GitHub only)

| Title | Number | URL |
| ----- | ------ | --- |
| ...   | ...    | ... |

[Or "N/A — Forgejo does not support project boards via API"]
```

## Quality Criteria

- Platform is correctly identified
- CLI authentication is verified and scopes are sufficient
- Default branch name is recorded
- Existing labels, milestones, and boards are inventoried
