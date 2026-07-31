## Zk (Zettelkasten CLI)

## Notebook Initialization

1. A notes repository MUST be initialized as a zk notebook before use: `zk init`.
2. The `.zk/` directory and its contents (config.toml, templates) MUST be committed to git.
3. Directory structure MUST follow the keystone standard: `inbox/`, `literature/`, `notes/`, `decisions/`, `reports/`, `presentations/`, `index/`, and `archive/`.
4. See `process.knowledge-management` for the note type taxonomy and methodology.
5. See `process.notes` and `tool.zk-notes` for hub notes, report chains, and archive workflows.
6. Automation SHOULD prefer `zk --notebook-dir <path> ...` over `cd <path> && zk ...` so notebook selection is explicit and independent of shell cwd.

## Creating Notes

7. Notes MUST be created via `zk new <group>/ --title "Title"`.
8. Groups map to directories: `inbox` (fleeting), `literature`, `notes` (permanent), `decisions`, `reports` (report), `presentations` (presentation), `index`, and `archive`.
9. In non-interactive contexts (agents, scripts), `--no-input` MUST be used to prevent `$EDITOR` from opening.
10. `--print-path` SHOULD be used when the caller needs the created file path.

```bash
# Human — interactive (opens editor)
zk new notes/ --title "ZFS pool import ordering"

# Agent — non-interactive
zk --notebook-dir ~/notes new inbox/ --title "CI failure pattern" --no-input --print-path

# With extra template variables
zk --notebook-dir ~/notes new literature/ --title "NixOS module system" --no-input \
  --extra source="NixOS Manual" --extra source_url="https://nixos.org/manual"

# Recurring report
zk --notebook-dir ~/notes new reports/ --title "Keystone fleet health $(date +%Y-%m-%d)" --no-input \
  --print-path --extra report_kind="keystone-system"

# Presentation deck
zk --notebook-dir ~/notes new presentations/ --title "Keystone architecture briefing" --no-input \
  --print-path --extra presentation_kind="architecture-briefing"
```

## Searching and Listing

11. Agents MUST use `--format json` for machine-readable output.
12. `--match` performs full-text search across note titles and bodies.

```bash
# Full-text search
zk --notebook-dir ~/notes list --format json --match "ZFS encryption"

# Filter by tag
zk --notebook-dir ~/notes list --format json --tag decision

# Filter by directory (group)
zk --notebook-dir ~/notes list inbox/ --format json

# Latest report in a chain
zk --notebook-dir ~/notes list reports/ --tag "report/keystone-system" --tag "repo/ncrmro/nixos-config" \
  --tag "source/deepwork/ks-doctor" --sort created- --limit 1 --format json

# Latest presentation deck of a given kind
zk --notebook-dir ~/notes list presentations/ --tag "presentation/architecture-briefing" \
  --tag "project/keystone" --sort created- --limit 1 --format json

# Find notes linked from a specific note
zk --notebook-dir ~/notes list --linked-by notes/202603201430.md --format json

# Find notes linking to a specific note (backlinks)
zk --notebook-dir ~/notes list --link-to notes/202603201430.md --format json

# Find related notes (shares tags or links)
zk --notebook-dir ~/notes list --related notes/202603201430.md --format json

# Find orphan notes (no incoming or outgoing links)
zk --notebook-dir ~/notes list notes/ --orphan --format json

# Recent notes
zk --notebook-dir ~/notes list --created-after "2 weeks ago" --sort created- --format json
```

## Tags

13. Tags MUST be lowercase, hyphenated slugs or approved namespaced values such as `project/keystone`.

```bash
# List all tags with counts
zk --notebook-dir ~/notes tag list

# List notes with a specific tag
zk --notebook-dir ~/notes list --tag zfs --format json
```

## LSP Integration

14. The `zk` LSP server is configured in helix via the keystone terminal module.
15. The LSP activates automatically when helix detects a `.zk/` directory in the workspace.
16. LSP provides: wikilink completion, tag completion, dead-link diagnostics, and note hover previews.
17. Agents SHOULD NOT rely on the LSP — use `zk list` and `zk tag list` for programmatic access.

## Nix-Managed Configuration

18. The `zk` binary is provided by `keystone.terminal.enable` — it is always on `PATH`.
19. The `.zk/config.toml` lives in the notes git repo, NOT in `/nix/store/`. It MAY be edited directly.
20. Template files in `.zk/templates/` MAY be customized per-repo.
21. Notes repos MUST gitignore transient zk database files such as `.zk/notebook.db` and `.zk/notebook.db-journal`.
