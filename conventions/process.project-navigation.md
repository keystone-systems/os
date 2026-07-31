# Project navigation

Use `rg` (ripgrep) with `--type` filters to search code efficiently. Use `jq` or `yq` to inspect JSON and YAML files rather than reading them whole — check top-level keys first with `jq keys` or `yq keys`, then extract only what you need. Search git history with `git log -G` or `git grep` when tracing requirements or past decisions. When a project defines requirement IDs (e.g., `REQ-001`), use them as anchors in specs, tests, and code comments so related artifacts can be found with `rg "REQ-001"` — add IDs to new tests and comments when they trace back to a requirement.
