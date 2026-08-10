---
title: ks CLI reference
description: Command reference for the Keystone infrastructure CLI
---

# ks CLI reference

`ks` builds and deploys Keystone hosts, enrolls hardware keys, opens secrets,
and escalates single Kubernetes commands. It is a shell script
(`packages/ks/ks.sh`) that front-ends the tools which do the real work:
`nixos-rebuild` for this host, `ks-fleet` for every other host,
`keystone-approve-exec` for privileged execution, and `ykman`/`ssh-keygen`
for tokens.

A subcommand belongs in `ks` only when a Keystone module, or the documented
contributor workflow, invokes it. Anything else belongs in its own script
under `bin/`.

## Global behavior

- `HOSTS` is a comma-separated list such as `workstation,ocean`. When omitted,
  `ks` uses the current host.
- A host that is not the current host is deployed by `ks-fleet deploy`. There
  is one deploy path, not two.
- Flake discovery reads `/run/current-system/keystone-system-flake` (written
  at activation time by `keystone.systemFlake`). Override with `--flake
  <path>` or `$KS_FLAKE`.

## Global flags

- `--flake <PATH>`: consumer flake path.
- `-h`, `--help`, `help`: show usage.

## Commands

### `ks build`

```bash
ks build [HOSTS]
```

Build the system closure for each host and print the store paths.

### `ks switch`

```bash
ks switch [--boot] [HOSTS]
```

Build and activate the current local state. No pull, no relock, no push.

- `--boot`: register the generation for next boot instead of switching now.

### `ks update`

```bash
ks update [--dev] [--lock] [--boot] [HOSTS]
```

Pull, relock, build, deploy, and push. Lock mode is the default.

- `--dev`: skip the pull, relock, and push steps; deploy the local checkout.
- `--lock`: force lock mode. This is the default.
- `--boot`: register the generation for next boot instead of switching now.

### `ks activate`

```bash
ks activate <STORE_PATH>
```

Activate a pre-built system closure. Refuses any path outside `/nix/store`.
This is the verb the privileged-approval allowlist grants — see
`keystone.security.privilegedApproval`.

### `ks approve`

```bash
ks approve --reason REASON -- COMMAND [ARG ...]
```

Run an allowlisted privileged command. `keystone-approve-exec` owns the
allowlist and is asked to validate the request first, so a rejected request
never raises an authentication prompt. Execution goes through `pkexec` in a
graphical session and `sudo` otherwise.

Requires `keystone.security.privilegedApproval.enable`.

### `ks kube`

```bash
ks kube sudo [--user NAME] [--cluster NAME] -- <kubectl args...>
```

Per-command Kubernetes privilege escalation via RBAC impersonation. Re-runs
one command as `kubectl --as=<user> --as-group=keystone:sudoers`, then exits
with kubectl's status.

- The impersonated user defaults to `$USER`; override with `--user`.
- Elevated rights come from the `keystone:sudoers` impersonation group. Its
  RBAC bindings live in ks.systems/services `access/sudo.yaml`. Impersonating
  a `system:*` identity is refused.
- `--cluster` is accepted but reserved: kubectl resolves the cluster from the
  kubeconfig context.
- Enforcement is server-side RBAC, so no root or `ks approve` gate applies.

Examples:

```bash
ks kube sudo -- delete pod stuck-pod -n prod
ks kube sudo --user alice -- get secrets -A
```

### `ks secrets`

```bash
ks secrets edit FILE
```

Open a sops-encrypted file. Recipients come from the hardware-key registry —
see `keystone.keys` and `hardwareKeyRegistrations.<name>.ageRecipients`.

### `ks hardware-key`

```bash
ks hardware-key doctor [--host HOST] [--strict] [--json]
ks hardware-key register NAME [--serial SERIAL] [--owner USER] [--repo DIR]
```

`doctor` delegates to `bin/ks-hardware-key-audit`: it compares committed
hardware-key state with a live host and is read-only.

`register` enrolls a physically connected token. It reads the serial with
`ykman`, creates a resident `ed25519-sk` credential (two touches: one for the
credential, one for the PAM/U2F registration), reads the age recipient from
`age-plugin-yubikey`, and prints the three blocks a consumer flake needs:

```nix
keystone.hardwareKeys.<name> = "<serial>";
keystone.hardwareKeyRegistrations.<name> = {
  owner = "...";
  sshPublicKeys = [ ... ];
  pamU2f = [ ... ];
  ageRecipients = [ ... ];
};
# In modules/keys.nix:
keystone.keys.<owner>.hardwareKeys.<name> = {
  publicKey = "...";
  handleSource = ../hardware-keys/<name>;
};
```

The key handle is written to `<repo>/hardware-keys/<name>{,.pub}`. `register`
uses `../hardware-keys/<name>` when the repository has `modules/keys.nix`. It
uses `./hardware-keys/<name>` for a root-level Nix file. `register` never edits
the flake. A human reviews the blocks and commits them.

## Removed commands

`ks` was a Rust CLI until 2026-08-02. These subcommands went with it and were
not ported: `agent`, `agent-loop`, `agents`, `docs`, `doctor`, `grafana`,
`install`, `menu`, `notification`, `notify`, `photos`, `print`, `project`,
`screenshots`, `sync-agent-assets`, `sync-host-keys`, `task`, `template`.

Their replacements, where one exists:

| Removed | Use instead |
| --- | --- |
| `ks install` | `ks-fleet install` (nixos-anywhere against the ISO's sshd) |
| `ks agent-loop` | the agent task-loop shell script (always used now) |
| `ks menu update` | nothing — the Walker update menu is gated off |
