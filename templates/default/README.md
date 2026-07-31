# keystone-config

This repository was generated from the Keystone flake template:

```bash
nix flake new -t github:ncrmro/keystone keystone-config
cd keystone-config
```

Most keystone config changes happen in the `flake.nix`, read more about how
it works in [`docs/keystone/flake.md`](docs/keystone/flake.md).

## After making changes

```bash
# Update the current host
ks update

# Update other hosts
ks update HOST1,HOST2
```

## Ask an AI assistant

Any AI coding agent (Claude Code, Codex, Gemini CLI, opencode, etc.) loads
[`AGENTS.md`](AGENTS.md) automatically when you open this directory — that
file lists the rest of the docs, so your prompt can just state what you
want. For example:

> Ask me clarifying questions about my setup (the hosts I want, where my
> SSH key lives, what OS I'm driving from), then walk me through the first
> three onboarding steps, including the exact edits to `flake.nix`.

More starter prompts (learning, secrets, ops, build + install) live in
[`docs/keystone/system-agent-prompts.md`](docs/keystone/system-agent-prompts.md).

## Quick start

Open `docs/keystone/onboarding.md`.

If you'd rather see the existing `TODO:` markers up front:

```bash
grep -RIn "TODO:" flake.nix hosts/
```

## Validate OS agents

After enabling and switching an OS agent, run the notification smoke test:

```bash
os-agents-e2e
```

If no OS agents are configured, this exits successfully with a skip message.
When agents exist, it sends `[ping] <tag>` to the agent mailbox, starts the
agent's Pi runner systemd service, and expects `Re: [pong] <tag>` to appear in
your inbox. Use `os-agents-e2e drago email` to choose a specific agent.
Use `os-agents-e2e drago all` when additional checks, such as PR assignment,
are implemented.

## How this repo is organized

See [`docs/keystone/keystone-config.md`](docs/keystone/keystone-config.md)
for the mental model — scopes (fleet vs per-host, system vs user), where
to install programs, NixOS vs Home Manager, and links to upstream Nix docs.

## Included docs

- [`docs/keystone/keystone-config.md`](docs/keystone/keystone-config.md) —
  mental model for this repo: scopes, NixOS vs Home Manager, where to
  install programs, when to drop down to vanilla Nix.
- [`docs/keystone/onboarding.md`](docs/keystone/onboarding.md) — progressive
  walkthrough from `nix flake new` to a fully secured first host.
- [`docs/keystone/flake.md`](docs/keystone/flake.md) — reference for
  `keystone.lib.mkSystemFlake`: every argument it accepts and every output
  it produces.
- [`docs/keystone/os-installer.md`](docs/keystone/os-installer.md) — build
  the installer ISO and write it to USB (Linux + macOS + Windows).
- [`docs/keystone/github-token.md`](docs/keystone/github-token.md) — set up
  an agenix-encrypted GitHub PAT to avoid rate-limit 403s.
- [`docs/keystone/system-agent-prompts.md`](docs/keystone/system-agent-prompts.md)
  — copy-pasteable prompts for asking an AI coding agent to help with
  onboarding, learning, secrets, ops, and install workflows.
- [`AGENTS.md`](AGENTS.md) — short orientation for AI coding agents (Claude
  Code, Codex, Gemini CLI, etc.). Repo shape, NixOS-vs-Home-Manager pitfalls,
  agenix conventions.

## Where to investigate Keystone itself

- Unified host helper implementation: `keystone/lib/templates.nix`
- Keystone admin and user option schema: `keystone/modules/os/default.nix`
- Keystone admin/user synthesis: `keystone/modules/os/users.nix`
- Keystone NixOS modules: `keystone/modules/`
- Keystone terminal Home Manager module: `keystone/modules/terminal/default.nix`
- Keystone desktop Home Manager module: `keystone/modules/desktop/home/default.nix`
