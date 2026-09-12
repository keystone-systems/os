---
title: System agent prompts
description: Copy-pasteable prompts for asking an AI coding agent to help with this keystone-config
---

# System agent prompts

Any AI coding agent (Claude Code, Codex, Gemini CLI, opencode, …) loads
[`AGENTS.md`](../../AGENTS.md) automatically when you open this directory.
That file lists every doc in this repo and tells the agent which one to
consult before reasoning from scratch. Your prompt only needs to state what
you want — the agent already has the context.

The prompts below are copy-pasteable starting points. Tweak the
placeholders, paste into your agent, and iterate from there.

## Onboarding

**Bootstrap my first host:**

> Ask me clarifying questions about my setup (the hosts I want, where my
> SSH key lives, what OS I'm driving from), then walk me through the first
> three onboarding steps, including the exact edits to `flake.nix`.

**Add a new host to an existing fleet:**

> I want to add a new `<kind>` host called `<name>` to my fleet. Walk me
> through the `flake.nix` entry, the `hosts/<name>/` directory shape, and
> any `keystoneServices.*.host` wiring I should update. Stop and ask before
> editing anything that affects other hosts.

## Learning

**How is the flake wired:**

> Summarize how `mkSystemFlake` turns my inventory into flake outputs, and
> call out arguments I'm not using yet that might be relevant for my fleet.

**Explain a specific module:**

> I see `keystone.nixosModules.<name>` referenced in `flake.nix`. Read the
> source in the keystone repo and explain what it does, what other modules
> it pulls in, and what I should know before enabling it.

## Secrets

**Add a sops-encrypted secret:**

> I want to add a sops-encrypted `<name>` secret consumed by the
> `<host>` host. Walk me through encrypting it with `ks secrets edit`,
> declaring `keystone.secrets.provided.<name>`, and reading it at runtime
> via its `.path` accessor without leaking through the Nix store.

**Rotate a secret near expiry:**

> The `<name>` secret is approaching expiry. Walk me through generating
> a fresh credential, re-encrypting the value in the appropriate
> `secrets/*.yaml` sops file (`ks secrets edit` / `ks secrets rekey`),
> committing, deploying, and revoking the old credential.

## Operations

**Diagnose system health and security posture:**

> Run `ks doctor` and walk me through the output. Then audit my security
> posture — LUKS unlock method (password / recovery key / TPM / hardware
> key), Secure Boot enrollment, whether `ssh-agent` has my key loaded, and
> whether fingerprint hardware is present but not enrolled. Call out which
> of those `ks doctor` doesn't currently check so I know what's a real
> gap vs. an unanswered question.

**Plan a fleet-wide upgrade:**

> I'm about to run `ks update` across `<host1>,<host2>,...`. Read the
> recent commits on `github:keystone-systems/os` since my current lock, flag
> anything risky (NixOS module renames, breaking option changes, new
> required arguments), and recommend whether to deploy all hosts at once
> or stage by kind.

## Build + install

**Adopt Keystone OS on a new machine with the public release:**

> Help me install Keystone OS on a new machine. Do not erase anything yet.
> Open `docs/keystone/os-installer.md` and use the matching release-candidate ISO and
> `ghcr.io/keystone-systems/os-installer` image; do not require Nix on my current
> computer. First ask which controller OS I use and which target host role I
> want. Tell me how to download and checksum the ISO, flash it safely, select
> the USB device in UEFI, and connect the target to a trusted wired network.
> Ask me for the IP shown on the target console. If it is absent, walk me
> through logging in as `root` with `changeme`, running `ip -br address`, and
> identifying the LAN address. Inspect my starter flake and ask only for the
> missing host role, stable disk identifiers, storage choice, and username.
> Run the controller preflight with `root`/`changeme`, show me the SSH
> fingerprint, hardware inventory, exact disks, and data-loss boundary, and
> stop for my exact interactive erase confirmation. After NixOS Anywhere
> finishes, tell me to enter `changeme` at the root-disk unlock prompt. Wait
> for the controller's revision, root-storage, and failed-unit health check.
> Clearly state that root SSH and disk encryption still use the public
> `changeme` bootstrap credential and that the host is not hardened. Do not
> claim that password removal, generation deletion, snapshots, or backups
> happened unless you verify a later generation that implements them.

**Build and verify the installer ISO:**

> Run `nix build .#iso` and confirm the result exists in `result/iso/`.
> Then walk me through writing it to a USB stick using the right `dd`
> incantation for my OS (ask if you don't know which OS I'm on).

**Walk me through a fresh install on the new host:**

> The installer USB is booted on the target. Use the container flow in
> `os-installer.md` with the temporary `root`/`changeme` SSH login and
> `changeme` LUKS password. Stop for the controller's exact erase
> confirmation, verify its post-install health report, then guide me through
> replacing the temporary credentials with per-host SSH access, durable disk
> unlock, and sops secrets.

---

Found a workflow that should live here? Add a new prompt — this doc is
owned by your repo.
