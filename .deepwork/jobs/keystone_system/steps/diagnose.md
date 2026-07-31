# Diagnose

## Objective

Check all hosts in the fleet are nominal. Run diagnostic commands directly — do NOT call `ks doctor` (CLI) or `/ks.doctor` (slash command), as those are launchers that start a new Claude session. This step contains the actual diagnostic work.

## Task

Verify the deployed system is healthy across all hosts. This step is the inner implementation of the doctor workflow.

### Process

1. **Gather system state on the current host**
   - Check NixOS generation: `nixos-version`
   - Check failed systemd units: `systemctl --failed --no-legend`
   - Check disk usage: `df -h`
   - Check flake.lock age: `git -C ~/nixos-config log -1 --format="%ar" -- flake.lock`
   - Check ZFS pools: `zpool status -x`
   - Look for any errors, warnings, or failed services

2. **Check the validation criteria from the plan** (if running as part of develop workflow)
   - If there is a plan.md from a prior plan step, read it
   - Verify each validation criterion defined in the plan is satisfied
   - Run the specific commands listed in the plan's "Validation Criteria" section

3. **Check agent health**
   - List all configured agents via nix eval (see AGENTS.md "Nix Eval for System Context"):
     ```bash
     nix eval ~/nixos-config#nixosConfigurations.<HOST>.config.keystone.os.agents \
       --json --apply 'a: builtins.mapAttrs (_: v: { fullName = v.fullName; host = v.host or null; archetype = v.archetype; desktop = v.desktop.enable; mail = v.mail.provision; chrome = v.chrome.enable; }) a'
     ```
   - For each agent on the current host, check:
     - `agentctl <agent> status` — are core services running? (task-loop.timer, notes-sync.timer)
     - `agentctl <agent> tasks` — are tasks processing or stuck?
     - `agentctl <agent> email` — is mail flowing?
   - **SSH signing and git commit signing**: For each agent with a git identity:
     ```bash
     agentctl <agent> exec ssh-add -l                           # verify SSH key is loaded
     agentctl <agent> exec git config --global commit.gpgsign  # should be "true"
     agentctl <agent> exec git config --global gpg.format      # should be "ssh"
     agentctl <agent> exec git config --global user.signingkey # should point to ~/.ssh/id_ed25519
     ```
   - **Tool health** — verify each terminal tool is functional:
     ```bash
     agentctl <agent> exec himalaya account list       # mail client configured + reachable
     agentctl <agent> exec bash -c 'cd /tmp && calendula calendars list'  # calendar client configured + reachable (no "account" subcommand)
     agentctl <agent> exec bash -c 'cd /tmp && cfait --version'           # task manager available
     ```
     Flag any tool that errors or returns no accounts — it indicates missing config or unreachable server.
   - For agents on remote hosts, SSH in and run equivalent checks
   - Note: `tailscale status` shows per-agent Tailscale nodes — offline agents should be flagged

4. **Determine fleet impact and check remote hosts**
   - Enumerate all hosts from `hosts.nix`
   - For each remote host with an `sshTarget`:
     - Test reachability: `ssh -o ConnectTimeout=5 -o BatchMode=yes root@<sshTarget> nixos-version`
     - Check failed units: `ssh root@<sshTarget> systemctl --failed --no-legend`
     - Check ZFS: `ssh root@<sshTarget> zpool status -x`
     - Compare NixOS generation to current host — flag drift
   - Document which hosts were unreachable vs. which were skipped (no sshTarget)

5. **Check ZFS replication** (syncoid)
   - On each host: `systemctl is-active syncoid*.service syncoid*.timer 2>/dev/null`
   - If syncoid units exist and are failed, check recent logs for root cause
   - Common issues: SSH key permissions, ZFS delegation missing on source datasets

6. **Evaluate results**
   - If all checks pass: complete the workflow
   - If issues found on current host caused by recent changes: document them. If from the develop workflow, call `go_to_step` with `step_id: "plan"` to create a fix.
   - If remote hosts need attention: document what needs to happen

**Maximum loop iterations**: If this is the 2nd validation failure, stop looping and present all findings to the human for manual resolution.

## Output Format

### validation_report.md

```markdown
# Validation Report

## Current Host

- **Hostname**: [hostname]
- **NixOS generation**: [version]
- **Status**: [PASS | WARNINGS | FAIL]
- **Failed units**: [none | list]
- **ZFS**: [all pools healthy | issues]
- **flake.lock age**: [X hours/days ago]

## Plan Validation Criteria (if applicable)

| Criterion             | Status    | Evidence                        |
| --------------------- | --------- | ------------------------------- |
| [criterion from plan] | PASS/FAIL | [command output or observation] |

## Agent Health

| Agent        | Host   | Services         | Tasks       | Mail      | Tailscale        |
| ------------ | ------ | ---------------- | ----------- | --------- | ---------------- |
| [agent-name] | [host] | [running/failed] | [X pending] | [ok/down] | [online/offline] |

### Agent Tool Health

| Agent        | SSH Key Loaded | Commit Signing | himalaya     | calendula    | cfait        |
| ------------ | -------------- | -------------- | ------------ | ------------ | ------------ |
| [agent-name] | [ok / no keys] | [true/false]   | [ok / error] | [ok / error] | [ok / error] |

## Fleet Status

| Host   | Reachable | NixOS Generation | Status      |
| ------ | --------- | ---------------- | ----------- |
| [host] | local     | [version]        | ← current   |
| [host] | yes       | [version]        | ok / drift  |
| [host] | no        | —                | unreachable |

## Remote Host Issues (if any)

### [hostname]

- **Failed units**: [list]
- **ZFS replication**: [ok | failed — details]
- **Details**: [findings]

## Overall Status

- **System nominal**: [yes | no — details]
- **All validation criteria met**: [yes | no — which failed]
- **Action needed**: [none | prioritized list of follow-up actions]
```

## Quality Criteria

- The current host shows no failed systemd units, healthy ZFS pools, and reasonable disk usage
- All hosts in the fleet have been checked or documented as unreachable/not applicable
- Each agent's SSH key is loaded and commit signing is configured (`commit.gpgsign = true`, `gpg.format = ssh`)
- Each agent's mail (himalaya), calendar (calendula), and task (cfait) tools are reachable and configured

## Context

This step is invoked by the doctor workflow and also referenced by the validate step in the develop workflow. The multi-host check is critical because keystone manages a fleet of interconnected hosts. ZFS replication and agent tool health are key signals of overall system health.
