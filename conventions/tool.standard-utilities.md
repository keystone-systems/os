# Convention: Standard Utilities (tool.standard-utilities)

Standards for using common Unix and development utilities (`jq`, `yq`, `rg`, `sed`, `awk`) within the keystone environment. These tools are pre-installed on all keystone hosts. For strategic guidance on using these tools for project navigation and discovery, see `process.project-navigation`.

## JSON Processing (jq)

1. `jq` MUST be used for parsing and filtering JSON output from APIs and CLI tools. See `tool.process-compose-agent` Rule 5 for its application in service orchestration.
2. Complex `jq` filters SHOULD be broken into multiple pipes for readability.
3. For scripts, use the `-r` (raw-output) flag when extracting string values to avoid unwanted quotes.
4. `jq` filters MUST handle missing keys gracefully using the `?` operator or `//` default values.

## YAML Processing (yq)

5. `yq` (mikefarah/yq) MUST be used for YAML manipulation in scripts and CI/CD pipelines.
6. When converting YAML to JSON for further processing with `jq`, use `yq -o=json eval '.'`.
7. In-place edits with `yq -i` MUST be backed up or performed within a git-tracked directory to allow for reversal.

## Searching (rg/ripgrep)

8. `rg` (ripgrep) MUST be the primary tool for searching text within files. For requirement discovery using Requirement Prefixes, see `process.project-navigation`.
9. For searching code, use the `--type` flag (e.g., `rg --type nix`) to narrow results and improve performance.
10. `rg` SHOULD be used with `--hidden` to include hidden files (e.g., `.env`, `.github/`) and `--no-ignore` if searching ignored files is necessary.
11. Large search results SHOULD be piped to `head` or `less` to avoid overwhelming the terminal or agent context.

## Text Processing (sed/awk)

12. `sed` and `awk` SHOULD only be used for simple stream edits where `jq` or `yq` are not applicable.
13. For complex text transformations, prefer specialized tools or small script fragments (Bash/Python) over intricate `sed`/`awk` one-liners.
14. `sed` commands MUST use a delimiter other than `/` if the pattern contains slashes (e.g., `sed 's|/old/path|/new/path|'`).

## Performance and Safety

15. Tools MUST NOT be used on binary files unless specifically designed for them.
16. For large-scale find-and-replace, use `git grep` or `rg` with `xargs` to ensure safety and speed. For using `git grep` in project navigation and requirement discovery, see `process.project-navigation`.
17. Avoid piping secrets or sensitive data into these utilities unless the output is immediately redirected to a secure location.

## Environment and Tool Availability

18. Projects SHOULD utilize Nix devshells (`nix develop`) to provide required tools when possible. In repositories where introducing Nix configuration is undesirable, tools MUST be provided by the pre-installed host environment or a local untracked shell. See `tool.nix-devshell` for standards on project-specific environments.
