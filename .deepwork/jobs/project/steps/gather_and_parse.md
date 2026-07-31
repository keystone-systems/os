# Gather and Parse Input

## Objective

Collect the raw scope for a project milestone from either an existing GitHub/Forgejo issue or freehand notes provided by the user, and produce a structured document capturing the full original content with source metadata.

## Task

Determine the input source and extract the raw scope content. The agent must handle two paths:

1. **Existing issue** — Fetch the issue body from the platform and capture it verbatim
2. **Freehand notes** — Accept the user's raw notes as-is

### Process

1. **Determine the platform**
   - Parse the `project_repo` input to identify the repo slug (e.g., `owner/repo`) and platform
   - If the platform isn't explicit, ask structured questions: "Is this a GitHub or Forgejo repo?"
   - For GitHub: use `gh` CLI
   - For Forgejo: use `fj` CLI or `tea api`/`curl`

2. **Determine the input source**
   - If `issue_number` is provided (and not blank), fetch the issue from the platform
   - If `freehand_notes` is provided (and not blank), use those as the raw scope
   - If both are provided, prefer the issue and append freehand notes as supplementary context
   - If neither is provided, ask structured questions to gather the scope from the user

3. **Fetch the issue (if applicable)**
   - GitHub: `gh issue view <number> --repo <owner/repo> --json title,body,labels,milestone,assignees`
   - Forgejo: `fj issue view <number>` or equivalent API call
   - Capture the full issue title, body, existing labels, and any milestone already assigned

4. **Handle the press release issue URL (if provided)**
   - If `press_release_issue_url` is provided, fetch the press release issue body from the platform
   - Record the press release content in `raw_scope.md` under a `## Press Release` heading
   - This content will be embedded in the milestone issue body by the `setup_milestone` step

5. **Assemble the raw scope document**
   - Include all original content without editing or reformatting
   - Add metadata header with source information
   - If the content is sparse or unclear, do NOT attempt to fill gaps — capture what exists and note gaps for the next step

## Output Format

### raw_scope.md

A markdown document with metadata header and the full original content.

**Structure**:

```markdown
# Raw Scope

## Source Metadata

- **Platform**: [github | forgejo]
- **Repository**: [owner/repo]
- **Source Type**: [issue | freehand]
- **Issue Number**: [number or "N/A"]
- **Issue Title**: [title or "N/A"]
- **Existing Labels**: [comma-separated list or "none"]
- **Existing Milestone**: [milestone title or "none"]
- **Press Release Issue URL**: [URL or "N/A"]

## Original Content

[Full verbatim content from the issue body or freehand notes, preserving all formatting]

## Press Release

[Full press release content fetched from press_release_issue_url, or "None"]

## Supplementary Notes

[Any additional freehand notes provided alongside an issue, or "None"]
```

**Concrete example**:

```markdown
# Raw Scope

## Source Metadata

- **Platform**: github
- **Repository**: ncrmro/homelab
- **Source Type**: issue
- **Issue Number**: 42
- **Issue Title**: Set up monitoring stack
- **Existing Labels**: enhancement
- **Existing Milestone**: none
- **Press Release Issue URL**: https://github.com/ncrmro/homelab/issues/38

## Original Content

We need monitoring for the homelab. Should include:

- Prometheus for metrics collection
- Grafana dashboards
- Alerting to Slack when stuff breaks
- Node exporter on all machines

Nice to have:

- Log aggregation with Loki
- Uptime checks for public services

## Press Release

[Full press release text from issue #38...]

## Supplementary Notes

None
```

## Quality Criteria

- The raw scope includes the full original content without omissions or edits
- Metadata captures the source (issue number/URL, repo, platform) or notes freehand input
- If an issue was fetched, the title, labels, and milestone status are recorded
- The document preserves the original formatting of the source content
- If `press_release_issue_url` was provided, the press release content is captured under `## Press Release`

## Context

This is the entry point for the milestone workflow. The quality of downstream steps (story refinement, milestone creation) depends entirely on capturing the full scope here. Do not filter, summarize, or interpret — just capture faithfully. The refine_stories step will handle transformation.
