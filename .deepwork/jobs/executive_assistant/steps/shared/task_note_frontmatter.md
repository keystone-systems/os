# Task note frontmatter

Use this shared shape for executive-assistant task notes and owner mirrors.

## Required baseline

```yaml
---
id: "202603281030"
title: "Prepare investor update"
type: permanent
created: 2026-03-28T10:30:00-05:00
author: ncrmro
tags:
  - project/catalyst
  - repo/ncrmro/catalyst
  - status/active
  - source/deepwork
---
```

## Coordination fields

Add these frontmatter fields when they are known:

```yaml
project: catalyst
owner: ncrmro
status: active
assigned_agent: drago
milestone_ref: gh:ncrmro/catalyst#12
issue_ref: gh:ncrmro/catalyst#88
pr_ref: gh:ncrmro/catalyst#91
repo_ref: gh:ncrmro/catalyst
source_ref: calendar-investor-update-2026-03-28
next_review: 2026-03-28
coordination_note: /abs/path/to/human/daily-note.md
```

## Rules

- Keep tags within approved namespaces only: `project/*`, `repo/*`,
  `status/*`, and `source/*`.
- Do not invent tag namespaces for milestone, issue, PR, or assignee identity.
- Use frontmatter for shared-surface references and owner assignment.
- Shared-surface refs MUST use normalized VCS format:
  - GitHub: `gh:<owner>/<repo>#<number>`
  - Forgejo: `fj:<owner>/<repo>#<number>`
  - Repo only: `gh:<owner>/<repo>` or `fj:<owner>/<repo>`
- Reuse the same `source_ref` for deduplication across the human note and owner
  mirrors.
