# Gather Status Data

## Objective

Read all data sources (TASKS.yaml, PROJECTS.yaml, ISSUES.yaml, PRs from GitHub/Forgejo) and compose a concise daily status digest as a plain-text email body.

## Task

Collect the agent's current operational state from local YAML files and git forges, then format it as a scannable email body ready to send to the human operator (see HUMAN.md).

### Process

1. **Read local data files**
   - Read TASKS.yaml from the repo root
   - Read PROJECTS.yaml from the repo root
   - Read ISSUES.yaml from the repo root (if it exists)

2. **Query for open PRs**
   - For each repo listed under projects in PROJECTS.yaml, determine the host:
     - GitHub repos: `gh pr list --repo {owner/repo} --author @me --state open --json number,title,url,createdAt,isDraft`
     - Forgejo repos (git.ncrmro.com): `fj pr list --repo {owner/repo} --state open`
   - If a CLI tool is not authenticated or not available, skip that source and note "Unable to query - [tool] not authenticated" in the output
   - Collect all open PRs across all project repos

3. **Compose the status digest**

   Organize the email body into these sections:

   **Priorities** - List all pending AND blocked tasks from TASKS.yaml, ordered by project priority (project order in PROJECTS.yaml). Include the task name and description. For blocked tasks, append `[BLOCKED - reason]` from ISSUES.yaml. If no pending or blocked tasks, say "No active priorities."

   **Open PRs** - List each open PR with repo, number, title, and URL. Flag any that are drafts. If no open PRs or unable to query, state why.

   **Recently Completed** - List tasks with status `completed`, limited to the most recent 5. Include name and description. If the task has an `artifact` field, include it as a link. If none, say "No recently completed tasks."

   **Blockers** - List any open issues from ISSUES.yaml with name and description. If none or ISSUES.yaml doesn't exist, say "No open blockers."

4. **Write the draft to status_draft.md**

## Output Format

### status_draft.md

Plain-text email body. No HTML, no markdown formatting - just clean text with simple section headers that reads well in any email client.

**Structure**:

```
Daily Status - [YYYY-MM-DD]

PRIORITIES
- [task-name]: [description]
- [task-name]: [description] [BLOCKED - reason]

OPEN PRS
- [owner/repo] #[number]: [title]
  [url]

RECENTLY COMPLETED
- [task-name]: [description]
  [artifact link if available]

BLOCKERS
- [issue-name]: [description]

--
{agent name} (automated daily status)  <-- read SOUL.md for agent name
```

**Concrete example**:

```
Daily Status - 2026-02-20

PRIORITIES
- fix-login-redirect: Fix the login redirect bug reported in issue #42
- daily-priorities-2026-02-19: Summarize daily priorities [BLOCKED - missing digest_notes DeepWork job]

OPEN PRS
- ncrmro/agent-space #3: Add recurring scheduled tasks
  https://github.com/ncrmro/agent-space/pull/3

RECENTLY COMPLETED
- reply-pong-to-ping-13: Reply with 'pong' to a ping email
- setup-scheduler: Create agent-scheduler timer

BLOCKERS
- missing-digest-notes-job: The digest_notes DeepWork job does not exist but is referenced by SCHEDULES.yaml

--
{agent name} (automated daily status)  <-- read SOUL.md for agent name
```

## Quality Criteria

- Pending and blocked tasks match TASKS.yaml, ordered by project priority; blocked tasks annotated with reason
- Open PRs are listed, or the draft explains why they couldn't be queried
- Open issues from ISSUES.yaml are mentioned, or the draft states there are none
- The email is concise, uses short sections, and can be scanned in under 30 seconds
- No markdown formatting - plain text only
- ASCII characters only - no em dashes, curly quotes, or other non-ASCII characters

## Context

This is step 1 of the daily status email workflow. The draft produced here is sent by the next step (send_email) to the human operator (see HUMAN.md). The email gives the human a quick morning overview of what the agent is working on, what's blocked, and what PRs need attention.
