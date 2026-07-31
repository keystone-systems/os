---
title: ks CLI reference
description: Command reference for the Keystone infrastructure CLI
---

# ks CLI reference

The `ks` command is the primary interface for building, deploying, and inspecting Keystone-managed infrastructure.

## Help

Use any of these forms to view help:

```bash
ks --help
ks -h
ks help
ks help update
ks update --help
ks update -h
```

## Global behavior

- `HOSTS` is a comma-separated list such as `workstation,ocean`.
- When `HOSTS` is omitted, `ks` resolves the current host from `hosts.nix`.
- Repo discovery reads `/run/current-system/keystone-system-flake` (written at activation time by `keystone.systemFlake`). Override with `--flake <path>`.

## Global flags

- `--flake <PATH>`: Override the consumer flake path (default: read from `/run/current-system/keystone-system-flake`).

## Commands

### `ks build`

```bash
ks build [--lock] [--user USERS] [--all-users] [HOSTS]
```

Build Keystone configurations for one or more hosts.

- `--lock`: Build full NixOS system closures instead of home-manager profiles.
- `--user USERS`: Limit home-manager builds to a comma-separated user list.
- `--all-users`: Build all home-manager users on each target host.

Examples:

```bash
ks build
ks build workstation,ocean
ks build --user alice,agent-coder workstation
ks build --lock ocean
```

### `ks update`

```bash
ks update [--debug] [--dev] [--boot] [--pull] [--lock] [--user USERS] [--all-users] [HOSTS]
```

Pull, verify, build, and deploy Keystone hosts.

Lock mode (pull latest flake inputs, build, push) is the default behavior.
Use `--dev` to deploy the current local checkout without locking.
Use `ks switch` to apply the current local state without any pull, lock, or push steps.

- `--debug`: Show warnings from `git` and `nix` commands.
- `--dev`: Build and deploy the current unlocked checkout without pull, lock, or push.
- `--boot`: Register the new generation for next boot without switching now.
- `--pull`: Pull managed repos only, then stop. Only takes effect when combined with `--dev`; without `--dev` it is ignored and the full lock-mode cycle runs.
- `--lock`: Force lock mode explicitly. This is the default; it overrides `--dev` when both are passed.
- `--user USERS`: Limit home-manager activation to a comma-separated user list.
- `--all-users`: Activate all home-manager users on each target host.

Examples:

```bash
ks update
ks update --dev workstation
ks update --boot ocean
ks update --pull --dev
```

### `ks agents`

```bash
ks agents <pause|resume|status> <agent|all> [reason]
```

Control task-loop pause state for one agent or the full agent fleet.

- `pause`: Create the pause marker so scheduled task-loop runs exit before ingest and execution.
- `resume`: Remove the pause marker and allow scheduled task-loop runs again.
- `status`: Show whether the target agent task loop is paused.

Examples:

```bash
ks agents pause drago "waiting for human review"
ks agents pause all "human focus block"
ks agents status luce
ks agents resume all
```

### `ks docs`

```bash
ks docs [topic|path]
```

Browse Keystone Markdown docs in the terminal with `glow` and `fzf`.

- With no argument, `ks docs` opens an interactive picker over Markdown files in `docs/` only.
- In the picker, type to filter, press Enter to open, and press Esc to cancel.
- Topic shortcuts: `os`, `terminal`, `desktop`, `agents`.
- Relative docs paths also work.

Examples:

```bash
ks docs
ks docs desktop
ks docs terminal/terminal.md
```

### `ks hardware-key`

```bash
ks hardware-key doctor [user|user/key] [--json]
ks hardware-key secrets [--json]
```

Inspect hardware-key wiring for the current host and current user.

- `doctor` validates registered SSH hardware keys, host root-key wiring, current-user `ageYubikey` identities, local YubiKey visibility, FIDO2 device visibility, and disk-unlock status when available.
- With no selector, `doctor` prefers the current user’s registered keys and falls back to all registered keys when no current-user keys exist.
- `secrets` is an explicit TODO stub for future agenix recipient and rekey orchestration. It currently reports the detected secrets layout and the planned implementation path.

Examples:

```bash
ks hardware-key doctor
ks hardware-key doctor ncrmro
ks hardware-key doctor ncrmro/yubi-black --json
ks hardware-key secrets --json
```

### `ks photos`

```bash
ks photos search [options]
ks photos people [options]
ks photos download <asset-id> [options]
ks photos preview <asset-id>
```

Search and preview the remote Immich-backed photo library.

- `Keystone Photos` is the canonical name for this feature.
- The public CLI entrypoint is `ks photos`.
- `immich-search` is legacy spec wording and should not be used for new docs.

Examples:

```bash
ks photos search --text "acme"
ks photos search --album "Screenshots - alice" --tag "receipt" --city "Austin"
ks photos search --text "nick romero" --kind business-card
ks photos search --person "Nick Romero" --type photo
ks photos search --filename "IMG_" --camera-make "Apple" --camera-model "iPhone 15 Pro"
ks photos people --json
ks photos search --text "ks build" --type screenshot --from 2026-01-01 --to 2026-03-31
```

### `ks screenshots`

```bash
ks screenshots sync [options]
```

Sync local PNG screenshots into the configured Immich server.

- `ks screenshots` manages the local screenshot pipeline.
- `ks photos` remains the remote search and preview surface.

Examples:

```bash
ks screenshots sync
ks screenshots sync --directory ~/Pictures --album-name "Screenshots - alice"
ks screenshots sync --url https://photos.example.com --api-key-file /run/agenix/alice-immich-api-key
```

### `ks switch`

```bash
ks switch [--boot] [HOSTS]
```

Build and deploy the current local state without pull, lock, or push steps.

- `--boot`: Register the new generation for next boot without switching now.

Examples:

```bash
ks switch
ks switch workstation,ocean
ks switch --boot ocean
```

### `ks sync-agent-assets`

```bash
ks sync-agent-assets
```

Refresh generated Keystone agent assets for the current user from the current
profile manifest.

- Rewrites generated instruction files, curated command files, and managed
  Codex skills from the live keystone checkout in development mode.
- This is the supported no-sudo refresh path for development-mode agent assets.

Example:

```bash
ks sync-agent-assets
```

### `ks sync-host-keys`

```bash
ks sync-host-keys
```

Fetch SSH host public keys from live hosts and write them into `hosts.nix`.

- Hosts without `sshTarget` are skipped.
- If `sshTarget` is unreachable and `fallbackIP` exists, `ks` retries over `fallbackIP`.

Example:

```bash
ks sync-host-keys
```

### `ks grafana dashboards`

```bash
ks grafana dashboards <apply|export> [uid]
```

Manage checked-in Keystone Grafana dashboards through the Grafana API.

- `apply`: Push every checked-in dashboard JSON file to Grafana, and delete stale keystone-managed dashboards that are no longer in the repo.
- `export <uid>`: Pull one dashboard by UID into its checked-in JSON file.
- `GRAFANA_URL`: Override the Grafana base URL.
- `GRAFANA_API_KEY`: Override the Grafana API key.
- In development mode, `ks update --dev`, `ks update`, and `ks switch` automatically sync keystone dashboards after deployment.

Examples:

```bash
ks grafana dashboards apply
ks grafana dashboards export keystone-host-overview
```

### `ks agent`

```bash
ks agent [--local [MODEL]] [args...]
```

Launch an AI coding agent with Keystone conventions and host context.

`ks agent` launches `claude` by default. Its static base prompt comes from the
generated `~/.keystone/AGENTS.md`, then `ks` appends live host and fleet context.
The generated command surface inside the session is curated to `/ks`, optional
`/ks-dev` in development mode, and `/deepwork`.

- `--local [MODEL]`: Use the local Ollama-backed model, or the configured default model.
- Remaining args are passed through to the underlying `claude` invocation.

Examples:

```bash
ks agent
ks agent --local
ks agent --local qwen2.5-coder:14b --continue
```

### `ks doctor`

```bash
ks doctor [--local [MODEL]] [args...]
```

Print the scripted fleet doctor report, then optionally launch the default agent.

- `--local [MODEL]`: If you choose to launch the agent, use the local Ollama-backed model, or the configured default model.
- Remaining args are passed through to the agent if you choose to launch it.

Examples:

```bash
ks doctor
ks doctor --local
ks doctor --local mistral --continue
```
