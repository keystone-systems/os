# Investigate Repos and Websites

## Objective

Independently investigate all git repositories and public websites mentioned in the intake notes, verifying agent access and gathering technical context.

## Task

Read the intake_notes.md from the gather_basics step, then systematically investigate every repo and domain listed. The goal is to understand what already exists and confirm agent access to the infrastructure.

### Process

#### Phase 1: Repository Investigation

For each git repo mentioned in intake_notes.md:

1. **Check agent access** using the appropriate CLI tools per platform (see common job info for tool conventions)
   - Record access status for each agent

2. **Inspect repo structure** (if accessible)
   - Clone to a temporary location or use the platform API
   - Check for: README, license, CI/CD config, language/framework
   - Note recent commit activity (last commit date, active contributors)
   - Look for existing documentation, tests, deployment configs
   - Note the primary language and any frameworks detected

3. **Check for existing project artifacts**
   - Look for requirements docs, user stories, roadmaps
   - Note any existing issue trackers
   - Check for PRs, branches, release tags

#### Phase 2: Website Investigation

For each public domain mentioned in intake_notes.md:

1. **Quick CLI check first** — `curl -sI <url>` to check status, redirects, server info

2. **Chrome MCP for any live site** — If the site is up (HTTP 200), always open it in Chrome MCP to capture the current state. This is critical context for the project profile.
   - Take a screenshot of the homepage
   - Take a snapshot (a11y tree) to capture all text content, navigation, CTAs
   - Note: key messaging, product positioning, pricing, target audience signals
   - Check for key pages (pricing, docs, dashboard, blog, team)
   - Browse 1-2 additional routes if they exist (e.g., /dashboard, /docs, /pricing) and note their state (live, demo, placeholder)
   - Summarize the current website state in 5-10 lines

3. **Skip Chrome MCP only if** the domain doesn't resolve, returns 4xx/5xx errors, or is a purely internal/API domain with no UI

#### Phase 3: Access Summary

Compile a clear access matrix showing which agents can reach which repos.

## Output Format

### investigation_report.md

**Structure**:

```markdown
# Investigation Report: [Project Name]

## Repository Investigation

### [Repo Name] — [repo_url]

- **Platform**: GitHub / Forgejo / other
- **Agent Access**: drago: [yes/no/untested] | luce: [yes/no/untested]
- **Primary Language**: [language]
- **Framework**: [framework or "none detected"]
- **Last Activity**: [date of last commit]
- **Structure Notes**: [key observations about repo structure]
- **Existing Docs**: [any requirements, roadmaps, or specs found]
- **Issues/PRs**: [count of open issues and PRs]

[Repeat for each repo]

## Website Investigation

### [domain.com]

- **Status**: [up / down / redirect / not registered]
- **Hosting**: [detected hosting/CDN/framework]
- **Screenshot**: [taken / not applicable]

#### Current Website State

[5-10 line summary of what the site communicates: headline, positioning, product/pricing,
key pages and their state (live vs demo vs placeholder), navigation structure, blog activity,
any calls to action. This summary feeds directly into the project profile.]

[Repeat for each domain]

## Access Matrix

| Resource | drago | luce | Notes                |
| -------- | ----- | ---- | -------------------- |
| [repo1]  | yes   | yes  |                      |
| [repo2]  | no    | no   | Need to add SSH keys |

## Issues Found

- [Any access problems, broken links, missing repos, etc.]

## Additional Context Discovered

- [Anything learned from repo/website investigation that enriches the project profile]
```

## Quality Criteria

- Every repo listed in intake_notes.md was investigated
- Access status is documented for each agent per repo — no "untested" entries without explanation
- Report clearly distinguishes between "no access" and "not tested"
- Every live website (HTTP 200) was opened in Chrome MCP with a snapshot and screenshot taken
- Website state summary captures headline, positioning, key pages, and page states (live/demo/placeholder)

## TODO

- When git LFS is set up, commit screenshots to `projects/{slug}/screenshots/` for version-controlled visual history of the project's web presence over time.

## Context

This step bridges the user conversation (gather_basics) and the structured profile (build_profile). The investigation surfaces ground truth about what infrastructure exists, what agents can access, and what the project looks like from the outside. The access matrix is critical for the setup_repos step, which will fix any access gaps.
