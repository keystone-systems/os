# Terminal Module — Editing Guide (`modules/terminal/`)

This guide covers conventions for editing the terminal module. For the full user-facing
reference, see `docs/terminal.md`.

**Key constraint**: Terminal and desktop modules are **home-manager based**, not NixOS
system modules. Changes only require `ks build` (fast, no sudo) unless they touch
NixOS-level options.

## Shell (`shell.nix`)

Zsh + oh-my-zsh (robbyrussell), starship, zoxide, direnv+nix-direnv, zellij.

Shell aliases and zellij keybinds are defined here. When adding keybinds, check for
conflicts with Claude Code (`Ctrl+G`) and lazygit (`Ctrl+O`) — those are unbound
intentionally.

## Editor (`editor.nix`)

Helix with custom keybindings and 25+ language servers. Key bindings:

- `Return` → `:write`, `F6` → markdown preview, `F7` → toggle soft wrap

When adding a new LSP, add both the package and the language config. `harper-ls`
applies to 20+ languages for grammar/prose checking — do not add it again per-language.

## Git (`git.nix` via `terminal/default.nix`)

SSH signing is on by default (`gpg.format = "ssh"`, signing key `~/.ssh/id_ed25519`).
`push.autoSetupRemote = true` and `submodule.recurse = true` are always set.

Required options: `keystone.terminal.git.userName` and `keystone.terminal.git.userEmail`.

## AI Tools (`agents/ai.nix`)

Four tools: Claude Code (NPM), Gemini CLI, Codex, OpenCode (last three from llm-agents flake).
All available when `keystone.terminal.enable = true` — agents get the identical environment.

### llm-agents input strategy

Keystone keeps `llm-agents` at nightly-latest. Consumer flakes choose one of two patterns:

**Contributor / nightly-latest** — follow keystone's pin so relocking keystone bumps agents automatically:
```nix
llm-agents.follows = "keystone/llm-agents";
```

**Stable consumer** — declare an independent pin and override keystone's input. Bump manually with `nix flake update llm-agents`:
```nix
llm-agents = {
  url = "github:numtide/llm-agents.nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
keystone.inputs.llm-agents.follows = "llm-agents";
```

The user-facing AI surface is curated. Keystone publishes `/ks`, optional
`/ks-dev` in development mode, and `/deepwork` instead of exposing every
workflow as a top-level command. Capability-aware routing happens in
`modules/terminal/agents/extensions.nix`.

## Mail (`mail.nix`)

**CRITICAL**: The `login` field is the Stalwart **account name** (e.g., `"ncrmro"`),
NOT the email address. Using the email as login causes auth failures.

**Folder mappings** (Stalwart defaults):

| Himalaya | Stalwart      |
| -------- | ------------- |
| Sent     | Sent Items    |
| Drafts   | Drafts        |
| Trash    | Deleted Items |

See `conventions/tool.himalaya.md` for full himalaya CLI reference.

## Age-YubiKey / hwrekey (`age-yubikey.nix`)

The `hwrekey` workflow: detect YubiKey → match serial → `agenix --rekey` →
commit+push secrets submodule → update parent flake input.

Retries up to 3x with 3s backoff for pcscd contention. Requires `secretsFlakeInput`
and `configRepoPath` options to be set.

## SSH Auto-Load (`ssh-auto-load.nix`)

Systemd user service that loads SSH keys at login. **Security**: SSH private keys are
host-bound and never stored in agenix — only passphrases are managed as secrets
(`{hostname}-ssh-passphrase`). Service polls for `SSH_AUTH_SOCK` with 5s timeout.

## Sandbox (`sandbox.nix`)

Podman-based AI agent sandboxing. Sets `PODMAN_AGENT_*` env vars consumed by
`podman-agent` package. Maintains a persistent `nix-agent-store` volume so the Nix
store doesn't need to be rebuilt on each invocation.

## Conventions (`conventions.nix`)

Generates canonical `~/.keystone/AGENTS.md`, then derives
`~/.claude/CLAUDE.md`, `~/.gemini/GEMINI.md`, `~/.codex/AGENTS.md`, and
`~/.config/opencode/AGENTS.md` from the same content. The archetype is set
per-agent via `keystone.os.agents.<name>.archetype`.

**Budget warning**: emits a Nix warning if the generated file exceeds `maxGlobalBytes`
(default 16KB). If triggered, move conventions from `inlined_conventions` to
`referenced_conventions` in `archetypes.yaml`.

## Development Mode vs Locked Mode (`development` + `repos` in `terminal/default.nix`)

**Development mode** (`development = true` with repos registered): Repo-backed
shell entrypoints in the user path are linked from the checkout, and generated
agent assets are refreshed from the live checkout by `ks sync-agent-assets`
(also run during activation).

**Codex exception**: Codex 0.114.0 does not reliably discover skills when
`SKILL.md` and `agents/openai.yaml` are symlinks. Keystone therefore materializes
managed files under `~/.codex/skills/` as regular files. Use
`ks sync-agent-assets` to refresh them without a full rebuild; activation runs
the same refresh path automatically.

**Locked mode** (default): Files are immutable Nix store copies. Rebuild required.

```nix
# In nixos-config, enable development mode:
keystone.development = true;
# repos are auto-populated from flake inputs via keystone.repos
```

The `development` boolean and `repos` attrset are bridged from NixOS-level
`keystone.development` and `keystone.repos` by `users.nix`. Terminal modules
look up local checkout paths via `repos` entries by `flakeInput` name.

New file-generating modules MUST use `config.lib.file.mkOutOfStoreSymlink` when
development mode is active, falling back to Nix store `source` otherwise. New
user-facing repo `.sh` commands SHOULD use the same development-mode path
switching instead of always packaging an immutable store copy.

## Tasks / Calendar / Contacts / Timer

These modules (`tasks.nix`, `calendar.nix`, `contacts.nix`, `timer.nix`) all follow the
same credential inheritance pattern — they read from `keystone.terminal.mail` options
rather than requiring separate config. `cfait` (tasks) uses a wrapper script to resolve
the password command at launch since it only supports plaintext passwords in config.
