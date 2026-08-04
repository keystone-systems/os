Use `ks.notes` as the durable-memory entrypoint for Keystone notes work.

Handle note-related requests directly. Use this skill proactively when work
produces durable context that should not live only in scratch files or chat.

## Canonical note conventions

- Use `ks.notes` when the task is primarily about durable note capture, note cleanup, inbox promotion, notebook repair, or notebook setup.
- Use `ks.notes` proactively after meaningful findings, design choices, operational learnings, or reusable research conclusions.
- Record repo-level or initiative-level decisions that materially affect implementation, operations, or prioritization.
- Create or update a decision note, report note, or hub-linked note after work that produced meaningful findings.
- Treat the notebook as durable memory, not as the public system of record for issue, PR, or milestone status.
- When a task is tied to a shared-surface artifact, record normalized refs during capture whenever known:
  - `repo_ref`
  - `milestone_ref`
  - `issue_ref`
  - `pr_ref`
- When a suitable hub exists, link new decisions, reports, and presentations from that hub before considering the note complete.
- When note structure, tags, frontmatter, shared-surface refs, or zk workflow details matter, read:
  - `~/.config/keystone/conventions/process.notes.md`
  - `~/.config/keystone/conventions/tool.zk-notes.md`
- If the user wants a fast durable brain dump before deeper organization, capture the note first, then continue with the appropriate notes workflow.

## Shared-surface split

- Issues, pull requests, milestones, and project boards are the shared system of record.
- Use notes to preserve durable context, richer rationale, and linkable memory that complements those shared surfaces.
- If a decision or blocker belongs on an issue or PR, record it there too; do not leave it only in the notebook.

## Common tasks

- **notes/process_inbox** — review and promote fleeting notes from inbox/ to permanent notes
- **notes/doctor** — audit, repair, and normalize a zk notebook
- **notes/init** — bootstrap a new zk notes repo from scratch
- **notes/setup** — configure an existing zk notebook

## Routing rules

- Mentions of processing, reviewing, or promoting inbox notes → `notes/process_inbox`
- Mentions of repair, health check, audit, or normalize → `notes/doctor`
- Mentions of new notebook, bootstrap, or initializing → `notes/init`
- Mentions of setup or configure → `notes/setup`
- If the user wants a quick durable capture before more work, capture first and organize second.
- If unclear, ask one targeted question before starting.
