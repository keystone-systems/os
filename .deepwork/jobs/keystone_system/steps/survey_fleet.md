# Survey Fleet

## Objective

Gather the current state of the keystone fleet: what keystone revision is locked in nixos-config, what's on keystone main, the commit changelog between them, and a preliminary health check of all reachable hosts.

## Task

Build a comprehensive snapshot of the fleet's current state to inform the update plan. This step collects data only — no changes are made.

### Process

1. **Determine the keystone revision gap**
   - Find the config repo by reading the activation-time pointer at `/run/current-system/keystone-system-flake` (written by `keystone.systemFlake`). On a non-running-NixOS host, fall back to `~/.keystone/repos/nixos-config`.
   - Read `flake.lock` to extract the currently locked keystone revision:
     ```bash
     nix eval --raw <nixos-config-path>#inputs.keystone.rev 2>/dev/null \
       || jq -r '.nodes.keystone.locked.rev' <nixos-config-path>/flake.lock
     ```
   - Get the latest commit on keystone main:
     ```bash
     git -C <keystone-path> rev-parse origin/main
     ```
   - If the revs differ, list all commits in the gap:
     ```bash
     git -C <keystone-path> log --oneline <locked-rev>..origin/main
     ```
   - If the revs match, note "keystone is up to date" and the workflow can be short-circuited

2. **Check nixos-config recent commits**
   - Review the last 20 commits on nixos-config's current branch (usually main):
     ```bash
     git -C <nixos-config-path> log --oneline -20
     ```
   - Note any uncommitted changes in nixos-config: `git -C <nixos-config-path> status`

3. **Check current host health directly**
   - **Do NOT run `ks doctor`** — that command is an AI entrypoint (`/ks.doctor` slash command) and would create a recursive loop
   - Instead, run direct shell health checks:
     ```bash
     systemctl is-system-running           # overall state: running / degraded
     systemctl --failed                    # list any failed units
     journalctl -p err --since '1 hour ago' --no-pager | tail -20
     ```
   - Note any failed units or recent errors — these are pre-existing issues, not caused by pending changes

4. **Gather fleet data via nix eval** *(required — this is the authoritative fleet registry, not `config.keystone.hosts`)*
   Use the same nix eval patterns as `ks doctor` (see AGENTS.md "Nix Eval for System Context"):
   - **Hosts table** — MUST run this first; every subsequent host probe iterates its output:
     ```bash
     nix eval -f <config-path>/hosts.nix --json
     ```
     Do NOT substitute `config.keystone.hosts` — that option attrset is typically empty; the top-level `hosts.nix` file is the source of truth consumed by the `ks` CLI.
   - **Agents** (per host):
     ```bash
     nix eval <config-path>#nixosConfigurations.<HOST>.config.keystone.os.agents \
       --json --apply 'a: builtins.mapAttrs (_: v: {
         fullName = v.fullName; host = v.host or null;
         archetype = v.archetype; desktop = v.desktop.enable;
         mail = v.mail.provision; chrome = v.chrome.enable;
       }) a'
     ```
   - **Users** (per host):
     ```bash
     nix eval <config-path>#nixosConfigurations.<HOST>.config.keystone.os.users \
       --json --apply 'u: builtins.mapAttrs (_: v: { fullName = v.fullName or ""; }) u'
     ```
   - **Enabled services** (server hosts):
     ```bash
     nix eval <config-path>#nixosConfigurations.<HOST>.config.keystone.server._enabledServices \
       --json 2>/dev/null
     ```

5. **Check host reachability**
   - From the hosts table, for each host with an `sshTarget`, check reachability. **Probe as the Keystone admin user, not as `root`** — on Keystone hosts, `root`'s SSH key is FIDO2 (ED25519-SK) and will fail when no hardware key is plugged in, giving false-negative outages. The admin user's keys are not hardware-gated and match how `ks` deploys.
   - **Resolve the admin username dynamically** (do NOT hardcode a personal username in the step output — keystone is used by many operators):
     ```bash
     ADMIN_USER="$(nix eval --raw <config-path>#nixosConfigurations.<HOST>.config.keystone.os.users \
       --apply 'u: let admins = builtins.attrNames (builtins.filterAttrs (_: v: v.admin or false) u);
                  in if admins == [] then "" else builtins.head admins' 2>/dev/null)"
     # Fallback: the current $USER on the workstation is typically the admin
     ADMIN_USER="${ADMIN_USER:-$USER}"
     ```
   - Then probe with that user:
     ```bash
     ssh -o ConnectTimeout=5 -o BatchMode=yes "$ADMIN_USER@<sshTarget>" echo ok 2>/dev/null
     ```
   - Record which hosts are reachable and which are not
   - For reachable hosts, capture their current NixOS generation:
     ```bash
     ssh "$ADMIN_USER@<sshTarget>" readlink /nix/var/nix/profiles/system
     ```
   - If a host fails with `sign_and_send_pubkey: signing failed for ED25519-SK … device not found`, the probe accidentally targeted `root` — re-run against `$ADMIN_USER@` before reporting the host offline.
   - Skip VMs and test hosts (those with `sshTarget: null` or `baremetal: false` where not cloud)

6. **Cross-reference known issues with GitHub**
   - For any failed units or health problems found in step 3, search GitHub before treating them as new:
     ```bash
     gh issue list --search "<keyword>" --repo ncrmro/keystone
     gh issue list --search "<keyword>" --repo ncrmro/nixos-config
     ```
   - Note the issue URL next to each finding in the health section — do not create duplicates

7. **Check for agenix-secrets changes**
   - If `agenix-secrets/` exists in nixos-config, check if it's clean and up to date:
     ```bash
     git -C <nixos-config-path>/agenix-secrets status --short
     git -C <nixos-config-path>/agenix-secrets log origin/main..HEAD --oneline
     ```

## Output Format

### fleet_survey.md

```markdown
# Fleet Survey

**Date**: [current date/time]
**nixos-config path**: [path]
**keystone path**: [path]

## Keystone Revision Gap

- **Locked in flake.lock**: `[commit hash]` ([date])
- **Latest on main**: `[commit hash]` ([date])
- **Commits behind**: [N]

### Changelog (oldest → newest)

| Hash      | Message                           | Modules Touched    |
| --------- | --------------------------------- | ------------------ |
| `abc1234` | feat(os): add new agent option    | modules/os/agents/ |
| `def5678` | fix(terminal): shell prompt color | modules/terminal/  |
| ...       | ...                               | ...                |

## nixos-config Status

- **Branch**: [main]
- **Clean**: [yes | no — details]
- **Recent commits**:
```

[last 10 commits one-line]

```

## Preliminary Health (Current Host)

- **Hostname**: [hostname]
- **System state**: [running | degraded | maintenance]
- **Failed units**: [list from `systemctl --failed`, or "None"]
- **Recent errors**: [summary from `journalctl -p err`, or "None"]

## Host Reachability

| Host | Role | SSH Target | Reachable | Generation | Notes |
|------|------|------------|-----------|------------|-------|
| ncrmro-workstation | client | ncrmro-workstation.mercury | yes | 142 | current host |
| ocean | server | ocean.mercury | yes | 87 | — |
| mercury | server | 216.128.136.32 | yes | 45 | VPS |
| maia | server | maia.mercury | no | — | offline |
| mox | client | mox.mercury | no | — | offline |

## Agenix Secrets

- **Status**: [clean | dirty — details]
- **Up to date**: [yes | no — commits behind]
```

## Quality Criteria

- The report shows the exact keystone commit currently locked in flake.lock and the latest commit on keystone main, with the full commit log between them
- All hosts in hosts.nix are listed with their reachability status — unreachable hosts are noted, not silently skipped
- Direct host health checks (`systemctl --failed`, `journalctl -p err`) were run on the current host and any issues are documented

## Context

This is the first step of the update workflow. The data collected here drives all subsequent decisions: the plan_update step uses the changelog to classify changes, the execute_fixes step uses pre-existing issues to prioritize work, and the run_update step uses host reachability to determine deployment targets. Accuracy here prevents surprises during deployment.
