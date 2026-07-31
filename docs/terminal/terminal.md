---
title: Terminal Module
description: Comprehensive command-line development environment via Home Manager
---

# Terminal Module

The Keystone Terminal module (`keystone.terminal`) provides a comprehensive, opinionated command-line development environment. It is designed to work consistently across NixOS, macOS, and other Linux distributions via Home Manager.

## Enable the Module

To enable the terminal environment in your Home Manager configuration:

```nix
keystone.terminal.enable = true;
```

This installs and configures:

- **[Helix](https://helix-editor.com/)**: Modal text editor (default)
- **[Zsh](https://www.zsh.org/)**: Interactive shell with Starship prompt
- **[Zellij](https://zellij.dev/documentation/)**: Terminal multiplexer
- **[Lazygit](https://github.com/jesseduffield/lazygit)**: Git TUI
- **Git**: Configured with LFS and sensible defaults
- **Utilities**: `eza`, `ripgrep`, `htop`, `zoxide`, `direnv`, `yazi`

## Helix Editor

Keystone configures [Helix](https://helix-editor.com/) as the default editor (`EDITOR` and `VISUAL` environment variables are set to `hx`). New to Helix? Start with the [Basics guide](https://helix-editor.vercel.app/start-here/basics/) — it uses a modal editing model similar to Vim.

### Key Features

- **Language Support**: Pre-configured LSPs for Bash, Markdown, Nix, TypeScript, Docker, YAML, JSON, and more.
- **Theme**: Uses `kinda_nvim` theme by default.
- **Soft Wrap**: Enabled by default with a text width of 120 columns.

### Keybindings (Normal Mode)

| Key           | Action           | Description                                                                                                                            |
| :------------ | :--------------- | :------------------------------------------------------------------------------------------------------------------------------------- |
| `Ret` (Enter) | `:write`         | Save the current buffer.                                                                                                               |
| `F6`          | Markdown Preview | Selects all text, renders Markdown to HTML using Pandoc, opens it in the default browser, and copies the preview URL to the clipboard. |
| `F7`          | Toggle Soft Wrap | Toggles soft wrapping of text.                                                                                                         |

### Markdown Preview

The Markdown preview feature (`F6`) uses a robust helper script (`helix-preview-markdown`) that:

1. Pipes the full content of the current file (even if unsaved) to Pandoc.
2. Renders it to `/tmp/helix-preview.html`.
3. Opens the HTML file in your system's default browser (via `xdg-open`).
4. Copies the URL (`file:///tmp/helix-preview.html`) to your clipboard (using `wl-copy` on Linux or `pbcopy` on macOS) so you can paste it into a different browser if preferred.

### Language Servers

The module installs and configures the following language servers automatically:

- **Markdown**: `marksman`, `harper-ls` (grammar checking)
- **Nix**: `nixfmt`
- **Bash**: `bash-language-server`
- **TypeScript**: `typescript-language-server`, `prettier`
- **Docker**: `docker-langserver`, `docker-compose-langserver`
- **YAML**: `yaml-language-server`
- **Ruby**: `ruby-lsp`, `solargraph`

## Shell Environment

### Zsh

- **Prompt**: [Starship](https://starship.rs/) prompt is configured for a minimal, informative interface.
- **Navigation**: [Zoxide](https://github.com/ajeetdsouza/zoxide) is enabled for fast directory jumping (`z <dir>`).
- **Aliases**:
  - `ls`, `l` -> `eza -1l` (modern ls replacement)
  - `grep` -> `rg` (ripgrep)
  - `g` -> `git`
  - `lg` -> `lazygit`
  - `zs` -> `zesh connect` (session manager)

### Zellij

[Zellij](https://zellij.dev/) is configured with sensible keybindings and acts as the default terminal multiplexer.

For the combined desktop and terminal movement reference, see [Navigation](../navigation.md).

Common Keystone zellij keybindings:

- `Ctrl+PageUp` / `Ctrl+PageDown`: Previous and next tab
- `Ctrl+,` / `Ctrl+.`: Previous and next tab
- `Ctrl+<` / `Ctrl+>`: Move the current tab left or right
- `Ctrl+T`: Create a new tab and name it immediately
- `Ctrl+W`: Close the current tab

## hwrekey — Secrets Rekeying

The `hwrekey` command automates re-encrypting agenix secrets with your YubiKey and (optionally) handling the full submodule commit/push/flake-update workflow.

### Enable

`hwrekey` is available when `keystone.terminal.ageYubikey.enable = true`.

```nix
keystone.terminal.ageYubikey = {
  enable = true;
  identities = [ "AGE-PLUGIN-YUBIKEY-..." ];
  # Optional: enable submodule workflow
  secretsFlakeInput = "agenix-secrets";
};
```

### Usage

```bash
cd agenix-secrets
hwrekey
```

### What It Does

1. Runs `agenix --rekey` using the YubiKey identity file (touch prompt per secret, no SSH password)
2. If `secretsFlakeInput` is set:
   - Commits and pushes the rekeyed secrets in the current (submodule) repo
   - Runs `nix flake update <secretsFlakeInput>` in the parent repo
   - Commits the submodule pointer + `flake.lock` together in the parent repo
3. If `secretsFlakeInput` is null, only runs the rekey — you commit manually

### Options

| Option              | Type        | Default                       | Description                                         |
| ------------------- | ----------- | ----------------------------- | --------------------------------------------------- |
| `enable`            | bool        | `false`                       | Enable age-plugin-yubikey identity management       |
| `identities`        | list of str | `[]`                          | YubiKey identity strings (`AGE-PLUGIN-YUBIKEY-...`) |
| `identityPath`      | str         | `~/.age/yubikey-identity.txt` | Path to the combined identity file                  |
| `secretsFlakeInput` | null or str | `null`                        | Flake input name for the secrets submodule          |

### When to Use

Run `hwrekey` after any change to `secrets.nix` that adds or removes key recipients (e.g., enrolling a new YubiKey, adding a new host key, removing a decommissioned machine). See [Hardware Keys](hardware-keys.md) for the full YubiKey enrollment workflow.

## Conventions

The conventions module writes keystone conventions to each CLI coding tool's native instruction file path at build time:

- `~/.claude/CLAUDE.md` (Claude Code)
- `~/.gemini/GEMINI.md` (Gemini CLI)
- `~/.codex/AGENTS.md` (Codex)
- OpenCode reads `~/.claude/CLAUDE.md` via legacy compatibility

```nix
keystone.terminal.conventions = {
  enable = true;                       # Default: true
  archetype = "keystone-system-host";  # Default: keystone-system-host
  maxGlobalBytes = 16000;              # Default: 16000 bytes (~4000 tokens)
};
```

The `archetype` option controls which convention set is inlined vs referenced. The default is `"keystone-system-host"`. Per-agent overrides are set via `keystone.os.agents.<name>.archetype`. See `conventions/tool.cli-coding-agents.md` for details on each tool's file discovery.

`maxGlobalBytes` sets the budget for the generated file. A build warning is emitted when the content exceeds this limit.

## DeepWork

The DeepWork module integrates workflow-driven development with quality gates into the terminal environment.

```nix
keystone.terminal.deepwork = {
  enable = true;            # Default: true
};
```

When enabled, the `DEEPWORK_ADDITIONAL_JOBS_FOLDERS` environment variable is set and injected into the generated DeepWork MCP server configs, allowing spawned MCP sessions to discover shared project job definitions alongside the built-in ones.

## Notes

Keystone supports a shared `zk` notebook model for both human note-taking and
agent-generated notes and reports. The user-facing guide is [Notes](../notes.md).

For terminal users, the most relevant parts are:

- `zk` for manual note creation and search, and
- `/ks-notes` to route notes workflows (hub notes, report capture, inbox review, notebook repair).

Use the notes guide for the workflow and the conventions for the authoritative
schema and policy details.

## Projects and sessions

Keystone project sessions are note-backed. Active project hub notes in
`~/notes/index/` define the valid project set, related repos, and context for
manual Zellij sessions and agent workflows.

## Personal Information Management

Keystone integrates the [Pimalaya](https://pimalaya.org/) CLI suite for email, calendars, contacts, and timers:

| Tool      | Enable                                     | Purpose            |
| --------- | ------------------------------------------ | ------------------ |
| himalaya  | `keystone.terminal.mail.enable = true`     | Email (IMAP/SMTP)  |
| calendula | `keystone.terminal.calendar.enable = true` | Calendars (CalDAV) |
| cardamum  | `keystone.terminal.contacts.enable = true` | Contacts (CardDAV) |
| comodoro  | `keystone.terminal.timer.enable = true`    | Pomodoro timers    |

Calendar and contacts auto-default credentials from the mail config. See [Personal Information Management](personal-info-management.md) for full usage documentation and [Agents](agents.md) for `agent-mail` usage (structured email templates for OS agents).
