# REQ-004: User Input

This document defines requirements for the CLI and TUI interactive
interfaces. The binary serves as both a full-screen TUI and a
scriptable CLI with structured JSON I/O for integration with desktop
menu systems (Walker, Elephant) and automation.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Requirements

### Platform Support

**REQ-004.1** The binary MUST run on Linux and macOS. Windows support MAY
be added as a stretch goal.

### Interactive Input

**REQ-004.2** The TUI MUST collect all REQUIRED inputs from REQ-002 via
interactive prompts with sensible defaults.

**REQ-004.3** The TUI SHOULD auto-detect SSH public keys from
`~/.ssh/*.pub` and offer them for selection.

**REQ-004.4** The TUI SHOULD detect connected hardware security keys
(YubiKey, SoloKey) and offer to configure `keystone.os.hardwareKey`.

**REQ-004.5** The TUI MUST validate inputs before generating config (e.g.,
hostId is 8 hex chars, at least one device, at least one user).

### CLI Subcommands

**REQ-004.6** The binary MUST support subcommands (e.g., `template`,
`build`, `update`, `switch`, `doctor`) in addition to the default
full-screen TUI mode. Running without a subcommand launches the TUI.

**REQ-004.7** CLI subcommands that collect user input MUST support a quick
interactive mode using line-based prompts (stdin/stdout) without
launching the full-screen TUI.

### JSON Input/Output

**REQ-004.8** Most user-facing CLI subcommands SHOULD support a `--json`
flag that switches the command to structured JSON I/O mode. Commands
intended for desktop menu adapters, automation, or machine-readable
integration MUST provide this mode. In JSON mode, input is read from
stdin as a JSON object and output is written to stdout as a JSON object.

**REQ-004.9** The JSON output envelope MUST include at minimum a `status`
field (`"ok"` or `"error"`) and a `data` field containing the
command-specific result payload.

**REQ-004.10** The JSON I/O mode MUST be usable by desktop menu adapters
(Walker, Elephant) that pipe JSON through the CLI to build interactive
menu hierarchies. Commands SHOULD return structured data suitable for
rendering as menu entries.

**REQ-004.11** JSON command contracts MUST live on the subcommand surface
(`ks <subcommand> --json`) rather than on a new global flag.
A historical top-level `--json` alias MAY be retained temporarily as a
compatibility shim for `template --json`, but it MUST NOT be the primary
documented interface.
