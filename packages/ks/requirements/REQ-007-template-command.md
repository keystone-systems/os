# REQ-007: Template Command

This document defines requirements for the `template` subcommand that
scaffolds a new Keystone configuration from minimal user input.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Requirements

### Core Behavior

**REQ-007.1** The binary MUST support a `template` subcommand that
generates a complete mkSystemFlake configuration directory.

**REQ-007.2** The `template` subcommand MUST accept `--github-username`
to fetch the user's display name and SSH public keys from the GitHub
API.

**REQ-007.3** When `--github-username` is provided, the command MUST
populate `owner.name` from the GitHub profile and include fetched SSH
keys in the generated config.

**REQ-007.4** The `template` subcommand MUST accept `--output` to specify
the target directory. If omitted, it SHOULD default to the current
directory or a named subdirectory based on hostname.

### Interactive CLI Mode

**REQ-007.5** When run without `--json`, the `template` subcommand MUST
present a quick interactive line-based form (not full-screen TUI)
prompting for: hostname, machine kind, username, password, and
optionally disk device and timezone.

**REQ-007.6** Fields with defaults (timezone = UTC, kind = server) MUST
show the default in the prompt and accept Enter to use it.

**REQ-007.7** When `--github-username` is provided, the interactive form
MUST skip prompting for owner name and SSH keys since those are fetched
from GitHub.

### JSON Mode

**REQ-007.8** When `--json` is passed, the `template` subcommand MUST
read a JSON object from stdin with fields matching the template
parameters and MUST write a JSON result object to stdout.

**REQ-007.9** The JSON output MUST include the generated file paths and
the config version (`1.0.0`).

### Git Integration

**REQ-007.10** After generating files, the `template` subcommand SHOULD
offer to initialize a git repository and create an initial commit.

**REQ-007.11** After git init, the `template` subcommand SHOULD offer to
create a private GitHub repository via `gh repo create` if `gh` is
available and authenticated.
