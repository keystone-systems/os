---
title: Notes
description: Shared zk note-taking system for humans, agents, and DeepWork workflows
---

# Notes

Keystone uses a shared `zk` notebook model for human notes, agent notes, and
workflow-generated reports. The same system supports quick captures, durable
knowledge notes, decision records, operational reports, and archived project
history.

For a human user, the notebook usually lives at `~/notes`. For OS agents, it
usually lives at `/home/agent-{name}/notes/`.

## Why notes matter in Keystone

Keystone uses the notes directory as shared operating context, not just a place
to store personal writing.

### Project discovery

Active hub notes in `~/notes/index/` are the source of truth for project
discovery.

That project metadata is used by Keystone Desktop and related project tooling
that needs repo URLs, summaries, and current state.

### Long-term memory for agents

Agents use their notes repo as long-term memory.

That includes:

- project hub notes,
- report chains,
- decision records,
- promoted research output, and
- other durable artifacts that should survive beyond the current task run.

### Automatic sync

Keystone automatically fetches and pushes the notes repo on a timer.

- Human users typically rely on `keystone-notes-sync` for `~/notes`
- OS agents use `agent-{name}-notes-sync` for `/home/agent-{name}/notes`

This makes the notes repo usable as shared state between the human operator,
desktop project navigation and agent workflows.

When `keystone.notes.daily.enable = true`, the same sync path also keeps
`daily.md` pointed at today's dated journal note (for example
`journal/2026-05-22.md`). The first sync after a day rollover commits and
pushes the symlink move automatically.

## What the notes system is for

Use the notes system to:

- capture fleeting thoughts quickly,
- turn research or work output into durable notes,
- keep one hub note per active initiative,
- store recurring reports such as diagnostics and reviews, and
- preserve completed work in an archive without breaking the graph.

The notes system is shared. Humans and agents should both write into the same
structure and use the same linking and tagging model.

## Executive assistant task loop

The `executive_assistant/task_loop` workflow uses zk notes as its coordination
state.

For this workflow:

- the human operator's notes repo is the canonical coordination ledger,
- active work should be represented as zk notes rather than a separate YAML task
  ledger,
- milestone, issue, pull request, assignee, and source references should live
  in frontmatter fields, and
- GitHub refs should use `gh:<owner>/<repo>#<number>` while Forgejo refs should
  use `fj:<owner>/<repo>#<number>`,
- tags should remain within the existing namespaces such as `project/<slug>`,
  `repo/<owner>/<repo>`, `status/<value>`, and `source/<value>`.

The workflow also maintains a dated executive-assistant daily note that rolls
unfinished work forward by linking existing task notes instead of copying task
bodies into a new note each day.

## Notebook layout

The current notes model uses these groups:

- `inbox/` for quick captures and raw notes
- `journal/` for dated daily notes such as `journal/2026-05-22.md`
- `literature/` for source summaries
- `notes/` for durable idea notes
- `decisions/` for explicit decisions
- `reports/` for time-stamped workflow or operational reports
- `index/` for hub notes and maps of content
- `archive/` for completed or abandoned initiative material

New or older notebooks may start with only the core `zk` groups scaffolded by
the notes module. If your notebook does not yet have `reports/` or `archive/`,
run the notes repair workflow to normalize it to the current model.

## Note types and flow

The normal flow is:

1. Capture rough input in `inbox/`.
2. Promote useful material into `literature/`, `notes/`, `decisions/`, or `reports/`.
3. Link durable notes and reports from an `index/` hub note.
4. Move concluded initiative material into `archive/`.

### Hub notes

Each active initiative should have one hub note in `index/`. The hub is the
entry point for the work. It should summarize the objective, current state,
next actions, durable notes, decisions, related repos, and recent reports.
When the initiative uses one or more repos, the hub should declare them in
frontmatter as full remote URLs.

Example:

```yaml
---
project: "keystone"
repos:
  - "git@github.com:ncrmro/keystone.git"
  - "ssh://forgejo@git.ncrmro.com:2222/drago/notes.git"
tags: [index, project/keystone, status/active]
---
```

Use the declared remote URLs as the source of truth. Humans and agents should
derive `repo/<owner>/<repo>` tags and local checkout paths from those URLs:

- keystone-managed repos: `~/.keystone/repos/{owner}/{repo}`
- non-keystone project repos: `$HOME/code/{owner}/{repo}`

### Report notes

Reports belong in `reports/`. Use them for:

- `ks.doctor` output,
- DeepWork research output,
- review writeups,
- operational checks, and
- other dated run results.

Recurring reports should link to the previous report in the same series so the
history is easy to follow.

### Archive

When an initiative is complete, paused, or abandoned, move its hub and related
initiative-specific notes into `archive/`. Keep the links and tags intact so
the historical material remains searchable.

## Tags and linking

Keystone uses a tight tag set. The most important tags are:

- `project/<slug>`
- `repo/<owner>/<repo>`
- `report/<kind>`
- `status/active`
- `status/archived`
- `source/human`
- `source/agent`
- `source/deepwork`
- `source/deepwork/ks-doctor`

Prefer links and frontmatter over inventing new tags. Agents should be
especially conservative about creating new tags outside the established
namespaces.

Use wikilinks for internal note references:

```markdown
See [[202603241230]] for the latest fleet health report.
```

## Human workflow

For a human operator, the normal pattern is:

```bash
# Create a durable note
zk new notes/ --title "ZFS backup failure pattern"

# Create a quick capture
zk new inbox/ --title "Follow up on launch checklist"

# Search for related notes
zk list --match "fleet health" --format json
```

When the note relates to an active initiative, add the canonical project tag
and link it from the relevant hub note. When the note materially concerns one
repo, derive the `repo/<owner>/<repo>` tag from the hub note's declared remote
URL instead of inventing a separate local-path convention.

## Editing existing notes with zk

Use `zk edit` when the note already exists and you want to reopen it in your
editor.


### Edit a report by path completion

If you know the note lives under `reports/`, the fastest workflow is often
shell completion:

```bash
zk edit reports/<TAB>
```

That lets the shell expand the report path before `zk` opens the file in your
editor.

Examples:

```bash
zk edit reports/202603241230-keystone-doctor.md
zk edit reports/<TAB>
```

Use this when:

- you already know the note family,
- the report name is recent enough to recognize, and
- you want direct file selection instead of search.

### Edit a note with the interactive picker

If you do not remember the path, use the interactive picker:

```bash
zk edit --interactive
```

Short form:

```bash
zk edit -i
```

This opens zk's fuzzy selection UI so you can search by title, path, or nearby
matches and then open the chosen note in your editor.

Use this when:

- you remember part of the note title but not the path,
- you want to scan several similar notes quickly, or
- you are not sure whether the note belongs in `reports/`, `notes/`, or `index/`.

### Recommended editing workflow

Use these defaults:

- `zk edit reports/<TAB>` when you already know you want a report note
- `zk edit -i` when you need fuzzy selection across the notebook

A practical pattern looks like this:

```bash
cd ~/notes
zk edit reports/<TAB>
```

Or:

```bash
cd ~/notes
zk edit -i
```

### Reopening report notes

When reopening a report note, usually update:

- the latest findings,
- links to related reports,
- links to the relevant project hub,
- repo tags derived from the hub note's declared remote URLs, and
- any explicit next actions or decisions that came out of the work.

If the report belongs to a recurring series, keep the series link structure
consistent so the history remains easy to follow.

## Agent and DeepWork workflow

Agents and DeepWork workflows should write durable output into the notebook
instead of leaving it only in scratch files or workflow output folders.

The new notes workflows are:

- `/notes.project` to create or refresh a hub note
- `/notes.report` to create a standardized report note
- `/notes.doctor` to repair and normalize a notebook
- `/notes.process_inbox` to review and promote fleeting notes

Typical agent behavior:

- search for an existing hub and related reports before starting work,
- write material decisions into `decisions/` or a report note,
- mirror important decisions into the related issue or pull request,
- link new reports back to the hub note.

Agents are configured to put durable workflow output into notes automatically
when that output should be kept. Common examples include:

- spike output,
- research summaries,
- status reports,
- review writeups, and
- refreshed project hubs.

That is what turns notes into long-term memory instead of just temporary task
scratch space.

### Example: human report capture

```bash
cat system_diagnostics.log | zk new reports/ \
  --interactive \
  --title "NixOS telemetry $(date +%Y-%m-%d)" \
  --extra project="unsupervised-platform" \
  --extra report_kind="nixos-telemetry" \
  --extra source_ref="system_diagnostics.log"
```

### Example: agent report flow

An agent running `ks.doctor` should create a report note in `reports/`, tag it
as `report/keystone-system`, `repo/ncrmro/nixos-config`, and
`source/deepwork/ks-doctor`, link it to the previous report in the same series,
and update a relevant system or operations hub if one exists.

## Where this is configured

- The home-manager notes module syncs the notes repo and can scaffold a zk
  notebook for human users. When `keystone.notes.daily.enable = true`, it also
  rotates `daily.md` to the current `journal/YYYY-MM-DD.md` target before the
  sync commit/push step.
- OS agents use the same notebook model in their agent-space.
- The AI command layer exposes the notes workflows across the supported coding
  agents, with tool-specific UX differences.
- Notes sync is handled by `repo-sync`, which clones if absent and then
  fetches, commits, rebases, and pushes changes automatically.

## Related docs

- [Terminal](terminal/terminal.md) for the terminal environment and AI command support
- [Agents](agents/agents.md) for human-side agent interaction
- [OS Agents](agents/os-agents.md) for agent-space provisioning and notes sync

For the authoritative policy and CLI details, see:

- `conventions/process.notes.md`
- `conventions/tool.zk-notes.md`
- `conventions/process.knowledge-management.md`
- `conventions/tool.zk.md`
