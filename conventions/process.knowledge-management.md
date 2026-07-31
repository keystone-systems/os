## Knowledge Management

## Purpose

This convention defines a Zettelkasten-based knowledge management system for keystone notes repositories. It applies to both human users and OS agents. The system uses the `zk` CLI (see `tool.zk`) to manage a flat, densely-linked graph of atomic notes.

## Note Types

1. Every markdown note MUST belong to exactly one type, stored in its corresponding directory.

| Type         | Directory             | Purpose                                                                    |
| ------------ | --------------------- | -------------------------------------------------------------------------- |
| fleeting     | `inbox/`              | Raw captures, quick thoughts, unprocessed session output                   |
| literature   | `literature/`         | Summaries of external sources written in your own words                    |
| permanent    | `notes/`              | Distilled, atomic ideas — one idea per note                                |
| decision     | `decisions/`          | Architectural Decision Records (ADRs) with context, decision, consequences |
| report       | `reports/`       | Time-stamped operational, research, or workflow reports                    |
| presentation | `presentations/` | Slidev decks and other Markdown-native presentation artifacts              |
| index        | `index/`              | Maps of Content — curated entry points linking to related permanent notes  |
| archive      | `archive/`            | Archived project notes retained in the zk graph                            |

2. Fleeting notes are ephemeral — they MUST be processed (promoted or discarded) within a few days.
3. Literature notes MUST be written in your own words to verify understanding — do not copy-paste.
4. Permanent notes MUST contain exactly one atomic idea. If a note needs a second heading, it SHOULD be split.
5. Decision notes MUST document context, the decision itself, and its consequences.
6. Report notes MUST summarize the run, research, or workflow outcome and SHOULD link to follow-up decisions or issues.
7. Index notes MUST NOT contain original ideas — they are curated link collections only.
8. Archive notes MUST preserve their original note purpose and SHOULD include archive metadata when moved.

## ID Schema

7. Every note MUST have a unique ID in `YYYYMMDDHHmm` format (12-digit timestamp, minute precision).
8. The filename MUST follow the pattern `{id} {title-slug}.md` (e.g., `202603201430 zfs-encryption-key-loading-order.md`).
9. IDs are permanent — they MUST NOT change even if the title or content changes.
10. For migrated notes, the ID SHOULD be backdated from git history or file modification time.

## Frontmatter Schema

11. Every note MUST include YAML frontmatter with the following required fields:

```yaml
---
id: "202603201430"
title: "ZFS credstore must unlock before pool import"
type: permanent
created: 2026-03-20T14:30:00-05:00
author: ncrmro
tags: [zfs, storage]
---
```

| Field     | Required | Description                                                                                        |
| --------- | -------- | -------------------------------------------------------------------------------------------------- |
| `id`      | Yes      | 12-digit timestamp ID                                                                              |
| `title`   | Yes      | Human-readable title                                                                               |
| `type`    | Yes      | `fleeting`, `literature`, `permanent`, `decision`, `report`, `presentation`, `index`, or `archive` |
| `created` | Yes      | ISO 8601 creation timestamp                                                                        |
| `author`  | Yes      | Unix username of creator (e.g., `ncrmro`, `agent-drago`)                                           |
| `tags`    | Yes      | List of lowercase hyphenated tags                                                                  |

13. Type-specific optional fields:

| Field               | Types        | Description                                                  |
| ------------------- | ------------ | ------------------------------------------------------------ |
| `source`            | literature   | Title/author of external source                              |
| `source_url`        | literature   | URL of external source                                       |
| `status`            | decision     | `proposed`, `accepted`, `deprecated`, `superseded`           |
| `supersedes`        | decision     | ID of the decision this one replaces                         |
| `project`           | any          | Project name for cross-reference                             |
| `report_kind`       | report       | Canonical report kind, e.g. `fleet-health`                   |
| `previous_report`   | report       | Prior report note ID in the same chain                       |
| `source_ref`        | report       | Workflow, command, file, or source that generated the report |
| `presentation_kind` | presentation | Canonical deck kind, e.g. `architecture-briefing`            |
| `archived_at`       | archive      | ISO 8601 timestamp when the note was archived                |
| `archived_reason`   | archive      | Why the note moved out of the active workspace               |
| `archived_from`     | archive      | Original group before archival                               |

## Linking

14. Internal links MUST use wikilink syntax: `[[202603201430]]` or `[[202603201430 title-slug]]`.
15. External URLs MUST use standard markdown links: `[text](url)`.
16. Every permanent note MUST link to at least one other note — no orphans in `notes/`.
17. Fleeting notes MAY be orphans (they are unprocessed by definition).
18. Decision notes MUST link to the permanent notes that informed the decision.
19. Report notes SHOULD link to the relevant project hub and MUST link to the prior report when they continue an existing series.
20. Presentation notes SHOULD link to the relevant project hub and supporting notes used in speaker notes or references.
21. When a note is superseded, the old note MUST link forward to the replacement via the `supersedes` field.

## Information Pipeline

22. New ideas MUST be captured immediately as fleeting notes in `inbox/`.
23. Fleeting notes MUST be reviewed periodically: promoted to permanent or literature, or discarded.
24. When promoting a fleeting note, the new permanent/literature note SHOULD incorporate and expand on the fleeting content, then the fleeting note SHOULD be deleted.
25. Literature notes MAY be promoted to permanent notes when a distinct atomic insight emerges.

## Agent Integration

26. After completing a task, agents SHOULD create a fleeting note capturing what was learned.
27. Before starting a task, agents SHOULD search for relevant context: `zk list --match "<task description>" --format json`.
28. Inbox processing SHOULD be scheduled as a recurring task in `SCHEDULES.yaml`.
29. Agents MUST use `--no-input` and `--print-path` when creating notes programmatically (see `tool.zk`).
30. Hub notes, report chains, presentation deck storage, and archival policy are defined by `process.notes`.

## Coexistence with Operational Files

31. YAML operational files (`TASKS.yaml`, `PROJECTS.yaml`, `SCHEDULES.yaml`) remain at the repo root and are NOT notes.
32. The `zk` indexer ignores non-markdown files — no special exclusion rules are needed.
33. Identity files (`SOUL.md`, `AGENTS.md`) at the repo root are NOT notes and SHOULD NOT have zk frontmatter.
