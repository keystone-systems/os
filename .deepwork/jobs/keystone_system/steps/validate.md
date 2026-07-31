# Validate

## Objective

Run `ks doctor` on the current host and check all affected hosts in the fleet to verify the system is nominal after deployment.

## Task

Verify that the deployed changes are working correctly across all hosts. This step can also be run standalone via the `doctor` workflow to check fleet health at any time.

### Process

1. **Check current host health directly**
   - **Do NOT run `ks doctor`** — it is an AI entrypoint (`/ks.doctor` slash command), not a shell diagnostic tool
   - Run direct health checks instead:
     ```bash
     systemctl is-system-running           # overall state
     systemctl --failed                    # list failed units
     journalctl -p err --since '1 hour ago' --no-pager | tail -30
     ```
   - For service-specific checks related to the deployed changes, run `systemctl status <service>` directly
   - Pay special attention to services related to the changes that were deployed

2. **Check the validation criteria from the plan**
   - If this step is running as part of the `develop` workflow, read the plan.md from the plan step
   - Verify each validation criterion defined in the plan is satisfied
   - Run the specific commands listed in the plan's "Validation Criteria" section

3. **Check agent health**
   - List all configured agents via nix eval (see AGENTS.md "Nix Eval for System Context"):
     ```bash
     nix eval ~/.keystone/repos/nixos-config#nixosConfigurations.<HOST>.config.keystone.os.agents \
       --json --apply 'a: builtins.mapAttrs (_: v: { fullName = v.fullName; host = v.host or null; archetype = v.archetype; desktop = v.desktop.enable; mail = v.mail.provision; chrome = v.chrome.enable; }) a'
     ```
   - For each agent on the current host, check:
     - `agentctl <agent> status` — are core services running?
     - `agentctl <agent> tasks` — are tasks processing or stuck? Note count of pending tasks.
     - `agentctl <agent> jobs` (or equivalent) — what are the 3-5 most recent jobs? Are any stuck/failed?
     - `agentctl <agent> email` — is mail flowing?
   - For agents on remote hosts, SSH in and run equivalent checks
   - **Tailscale note**: `tailscale status` shows per-agent Tailscale nodes. Agent Tailscale integration is a **TODO feature** — offline agent nodes are expected and informational only. Only flag if a _host-level_ Tailscale node goes offline.

4. **Cross-reference issues with GitHub**
   - For each issue found (failed units, stuck agents, unhealthy services), search GitHub before treating it as new:
     ```bash
     gh issue list --search "<keyword>" --repo ncrmro/keystone
     gh issue list --search "<keyword>" --repo ncrmro/nixos-config
     ```
   - If an existing issue is found: link it in the report — do not create a duplicate
   - If no existing issue: document it as a new finding requiring a new issue

5. **Determine fleet impact**
   - Read the hosts table: `ks agent` can show the fleet, or evaluate `hosts.nix` directly
   - Determine which other hosts are affected by the changes:
     - Server module changes affect the server host
     - Agent module changes affect hosts running agents
     - Terminal/desktop changes affect all workstations
     - Domain/services changes may affect all hosts
   - If no other hosts are affected, document why and skip multi-host checks

6. **Check other affected hosts**
   - For each affected remote host (probe as the Keystone admin user resolved in survey_fleet step 5 — NOT as `root`, whose key is FIDO2-gated; and NOT as a hardcoded personal username):
     - SSH in and check service status: `ssh "$ADMIN_USER@<host>" systemctl --failed`
     - Check for any deployment-related issues: `ssh "$ADMIN_USER@<host>" journalctl -p err --since '1 hour ago'`
     - If the remote host needs updating too, inform the human
   - Ask structured questions to confirm if the human wants to update remote hosts now

7. **Evaluate results**
   - If all checks pass: complete the workflow
   - If issues found on current host: document them. If they are caused by the recent changes, call `go_to_step` with `step_id: "plan"` to create a fix (this requires a new worktree since we already merged)
   - If remote hosts need attention: document what needs to happen

8. **Archive report to zk notes** (see `tool.zk-notes` and `process.notes`)
   - Fleet health reports contain personal deployment data — archive to the configured notes dir (`$NOTES_DIR`, `~/notes` for Keystone human users), NOT leave them in the open-source repo
   - **Find prior report** (required — used for `previous_report` chain):
     ```bash
     NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
     zk --notebook-dir "$NOTES_DIR" list reports/ \
       --tag "report/keystone-system" \
       --tag "repo/ncrmro/nixos-config" \
       --tag "source/deepwork/ks-doctor" \
       --sort created- --limit 1 --format json
     ```
   - **Create the report note**:
     ```bash
     NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
     zk --notebook-dir "$NOTES_DIR" new reports/ --title "keystone fleet health $(date +%Y-%m-%d)" \
       --no-input --print-path \
       --extra report_kind="keystone-system" \
       --extra source_ref="ks.doctor" \
       --extra type="report" \
       --extra author="ks.doctor"
     ```
   - **Write note content** — required frontmatter (`type: report`, `tags: [report/keystone-system, repo/ncrmro/nixos-config, source/deepwork/ks-doctor]`, `previous_report: <prior note id or omit if none>`) followed by a concise summary:
     - Keystone revision gap (commits behind, impactful changes)
     - Host reachability table
     - Failed units per host with GitHub issue links
     - Action items
   - **Link from a relevant hub if one exists**:
     ```bash
     NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
     zk --notebook-dir "$NOTES_DIR" list index/ --tag "status/active" --format json
     ```
     If there is a system or operations hub for this notebook, append a link to the new report in its report ledger section. Do not require a `project/keystone` hub.

**Maximum loop iterations**: If this is the 2nd validation failure, stop looping and present all findings to the human for manual resolution.

## Output Format

### validation_report.md

```markdown
# Validation Report

## Current Host

- **Hostname**: [hostname]
- **System state**: [running | degraded | maintenance]
- **Failed units**: [from `systemctl --failed`, or "None"]
- **Recent errors**: [from `journalctl -p err`, or "None"]

## Plan Validation Criteria

| Criterion             | Status    | Evidence                        |
| --------------------- | --------- | ------------------------------- |
| [criterion from plan] | PASS/FAIL | [command output or observation] |
| [criterion from plan] | PASS/FAIL | [command output or observation] |

## Agent Health

### [agent-name] (host: [host])

- **Services**: [running | failed — details]
- **Tasks**: [N pending | idle | stuck since HH:MM]
- **Recent jobs**: [last 3-5 job names or "none in last 24h"]
- **Blocking issues**: [description or "none"]
- **Mail**: [ok | down]
- **Tailscale**: [online | offline] _(offline is expected — agent Tailscale integration is a TODO)_

## Fleet Impact Assessment

- **Changes affect**: [list of affected hosts, or "current host only"]
- **Hosts checked**: [list]
- **Hosts needing update**: [list, or "none"]

## Remote Host Status

### [hostname] (if applicable)

- **Status**: [nominal | issues found | needs update]
- **Details**: [findings]

## Issues Found

| Issue                                         | Existing tracker item   | Status       |
| --------------------------------------------- | ----------------------- | ------------ |
| [e.g., syncoid-rpool-to-ocean.service failed] | [#42 — link]            | pre-existing |
| [e.g., unknown service crash]                 | none — new issue needed | new          |

## Overall Status

- **System nominal**: [yes | no — details]
- **All validation criteria met**: [yes | no — which failed]
- **Action needed**: [none | list of follow-up actions]
```

## Quality Criteria

- Direct health checks on the current host (`systemctl --failed`, `journalctl -p err`) show no critical issues
- All hosts affected by the changes have been checked or confirmed not impacted
- The specific validation criteria from the plan are confirmed working on the live system
- Each agent's task queue, recent jobs, and any blocking issues are reported
- Every issue found is cross-referenced against the issue tracker — existing issues are linked, genuinely new issues are flagged for creation
- A dated fleet health note has been written to the configured notes dir via `zk` — the report must not remain only in the keystone repo's `.deepwork/` folder

## Context

This is the final quality gate in the develop workflow. It ensures that changes don't just build — they actually work on a live system. The multi-host check is critical because keystone manages a fleet of interconnected hosts, and a change that works on the workstation might break a server service or agent provisioning. This step can also be invoked standalone via the `doctor` workflow for routine fleet health checks.
