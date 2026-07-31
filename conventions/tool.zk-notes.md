# Convention: zk note workflows (tool.zk-notes)

This convention documents the canonical `zk` workflows for hub notes, report
capture, presentation deck capture, note repair, and archive handling in
Keystone notebooks.

## Hub note creation

1. Initiative hubs MUST be created as `index` notes.
2. Humans SHOULD create a hub with:

```bash
zk new index/ --title "Project: Keystone" --extra project="keystone"
```

3. Agents MUST create hubs non-interactively:

```bash
zk --notebook-dir ~/notes new index/ --title "Project: Keystone" --no-input --print-path \
  --extra project="keystone"
```

4. After creation, the note MUST be updated to include `project/keystone` and
   `status/active`, plus links to decisions, reports, presentations, repos, and
   next actions.
5. Agents MUST NOT update an existing hub note unless the user explicitly asks
   for that hub mutation or the active workflow's contract explicitly includes
   hub maintenance.

## Report capture

6. Reports MUST be created in `reports/`.
7. Interactive capture MAY stream command output into `zk new`, for example:

```bash
cat system_diagnostics.log | zk new reports/ \
  --interactive \
  --title "NixOS telemetry $(date +%Y-%m-%d)" \
  --extra project="unsupervised-platform" \
  --extra report_kind="nixos-telemetry" \
  --extra source_ref="system_diagnostics.log"
```

8. Agents SHOULD use non-interactive creation and then write the summarized
   report content into the created file:

```bash
zk --notebook-dir ~/notes new reports/ --title "Keystone fleet health $(date +%Y-%m-%d)" \
  --no-input --print-path \
  --extra report_kind="keystone-system" \
  --extra source_ref="ks.doctor"
```

9. Before writing a recurring report, agents SHOULD search for the latest prior
   report of the same kind:

```bash
zk --notebook-dir ~/notes list reports/ \
  --tag "report/keystone-system" \
  --tag "repo/ncrmro/nixos-config" \
  --tag "source/deepwork/ks-doctor" \
  --sort created- --limit 1 --format json
```

10. If a prior report exists, the new note MUST record it in `previous_report`.
11. Operational reports MAY omit the `project` field when they are better
    identified by `report/<kind>`, `repo/<owner>/<repo>`, and source tags.
12. When a report or durable note is based on a repo tracker artifact, agents
    SHOULD record the shared-surface refs in frontmatter during initial capture,
    for example:

```yaml
repo_ref: gh:ncrmro/keystone
milestone_ref: gh:ncrmro/keystone#12
issue_ref: gh:ncrmro/keystone#88
pr_ref: gh:ncrmro/keystone#91
```

## DeepWork workflow note creation

13. DeepWork workflows MUST use `zk new` to create output notes. When
    `ZK_NOTEBOOK_DIR` is set, agents MUST NOT pass `--notebook-dir`.

14. Workflows MUST create the final report as a report note:

```bash
REPORT_PATH=$(zk new reports/ \
  --title "Competitive content analysis: Plant Caravan 2026-04-01" \
  --no-input --print-path)
```

15. Workflows MUST create supporting research as literature notes:

```bash
LIT_PATH=$(zk new literature/ \
  --title "AeroGarden content strategy analysis" \
  --no-input --print-path)
```

16. After `zk new` creates the file, the agent MUST update the frontmatter to
    fill in `report_kind`, `source_ref`, and `tags` (the template leaves these
    empty), then append content below the template sections.

17. The final report MUST include a "Supporting research" section with
    wikilinks to all supporting literature notes:

```markdown
## Supporting research

- [[literature/<id> aerogarden-content-strategy-analysis]]
- [[literature/<id> gardyn-content-strategy-analysis]]
```

18. For periodic workflows, agents MUST search for the latest prior report and
    record it in `previous_report` frontmatter (per report chaining rules above).

## Presentation deck capture

19. Slidev decks MUST be created in `presentations/`.
20. Humans SHOULD create a deck with:

```bash
zk new presentations/ --title "Keystone architecture briefing"
```

21. Agents MUST create decks non-interactively and then apply the canonical
    Slidev deck template:

```bash
zk --notebook-dir ~/notes new presentations/ --title "Keystone architecture briefing" \
  --no-input --print-path \
  --extra project="keystone" \
  --extra presentation_kind="architecture-briefing"
```

22. New decks SHOULD be initialized with Slidev YAML frontmatter, `---` slide
    separators, and a speaker-notes block that can contain zk wikilinks.
23. Before writing a replacement or recurring deck, agents SHOULD search for
    the latest related deck first:

```bash
zk --notebook-dir ~/notes list presentations/ \
  --tag "presentation/architecture-briefing" \
  --tag "project/keystone" \
  --sort created- --limit 1 --format json
```

## Repair and cleanup

24. Notebook cleanup SHOULD start with a search-driven audit rather than manual
    browsing of the entire notebook.
25. Agents SHOULD use these queries during cleanup:

```bash
zk --notebook-dir ~/notes list reports/ --format json
zk --notebook-dir ~/notes list presentations/ --format json
zk --notebook-dir ~/notes list index/ --tag "status/active" --format json
zk --notebook-dir ~/notes list notes/ --orphan --format json
zk --notebook-dir ~/notes tag list
```

26. Cleanup workflows SHOULD normalize:
    - missing required frontmatter,
    - report chains,
    - presentation deck metadata,
    - missing hub links,
    - stale status tags, and
    - notes that should move to `archive/`.
27. Cleanup workflows SHOULD prefer frontmatter updates and directory moves over
    destructive rewriting of note bodies.

## Archive handling

28. Archived project material MUST be moved into `archive/`.
29. Archival workflows SHOULD verify that the hub note and latest report are
    still discoverable via `zk --notebook-dir <notes_path> list --tag "project/<slug>" --format json`.
30. Archived notes MAY retain project and repo tags. They MUST replace
    `status/active` with `status/archived`.

## Slash command mapping

31. `/notes.project` SHOULD create or refresh a hub note.
32. `/notes.report` SHOULD create a report note, apply the canonical tags, and
    chain it to the latest prior report.
33. Deck-focused workflows SHOULD create or refresh a presentation note in
    `presentations/` rather than storing the deck in ad hoc folders.
34. `/notes.process_inbox` SHOULD continue to promote inbox notes and SHOULD link
    promoted project notes back to the relevant project hub.
35. `/notes.doctor` SHOULD repair and normalize an existing notebook, especially
    `~/notes`, rather than acting only as a one-time migration command.
36. `/notes.doctor` SHOULD ensure the root `.gitignore` ignores transient zk database
    files and local junk while keeping tracked YAML state files versioned.

## References

- `process.knowledge-management`
- `process.notes`
- `tool.zk`
