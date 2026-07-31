# Plan Update

## Objective

Analyze the fleet survey to classify every pending change, triage issues, and produce a concrete update plan with a verification checklist for post-deployment.

## Task

Read the fleet survey from the previous step and produce an update plan that categorizes each change and defines what needs to happen before and after `ks update --lock`.

### Process

1. **Read the fleet survey**
   - Load fleet_survey.md from the survey_fleet step
   - Understand the keystone revision gap, changelog, host reachability, and pre-existing issues

2. **Classify each commit in the gap**
   For every commit between the locked rev and keystone main, assign one of:
   - **verify-only** — The change is self-contained and already merged. After deployment, just confirm it works. Examples: new module option with default value, documentation change, convention update.
   - **ad-hoc-fix** — A small issue spotted in the changelog or pre-existing doctor findings that can be fixed quickly (< 30 min) in a keystone worktree before deploying. Examples: typo in config path, missing default value, shellcheck warning.
   - **needs-issue** — A complex problem requiring its own development cycle. Too risky or large to fix ad-hoc before deploying. Examples: service migration, breaking API change, multi-host coordination issue.

3. **Analyze module impact**
   - For each commit, determine which modules are affected (os, terminal, desktop, server)
   - Map modules to hosts that consume them:
     - `modules/os/` → all hosts
     - `modules/terminal/` → all workstations + agent hosts
     - `modules/desktop/` → workstations with desktop enabled
     - `modules/server/` → server hosts (ocean, mercury, maia)
   - Use this to determine which hosts MUST be updated and in what order

4. **Check for breaking changes and boot-critical changes**
   - Look for commits that rename options, remove defaults, change service configs
   - If found, flag them prominently and note what verification they need
   - **CRITICAL**: Check if any changes touch Secure Boot (lanzaboote), bootloader, kernel, or systemd-boot:
     - If YES: recommend `--boot` flag AND deploying to ONE local host first (laptop/workstation with physical access), rebooting to verify, THEN deploying to remote hosts
     - A past lanzaboote update broke Secure Boot on ocean and required physical BIOS intervention — remote servers must NEVER be the first host to receive bootloader changes
   - Check if any changes require a reboot (`--boot` flag for ks update) even without bootloader changes (e.g., kernel module changes)

5. **Build the verification checklist**
   For each change category, define concrete post-deployment checks:
   - New module options → verify option is available in `nix eval`
   - Service changes → verify service is running: `systemctl status <service>`
   - Agent changes → verify agent health: `agentctl <agent> status`
   - Terminal/desktop → verify in user session
   - Pre-existing doctor issues → verify they're still present or resolved

6. **Determine deployment order**
   - Current host first (fastest feedback loop)
   - Then servers (ocean, mercury, maia) — most critical
   - Then other clients (mox, ncrmro-laptop)
   - Skip unreachable hosts — note them as "deferred"

## Output Format

### update_plan.md

```markdown
# Update Plan

**Date**: [date]
**Keystone gap**: `[locked]` → `[latest]` ([N] commits)
**Pre-existing issues**: [count from doctor]

## Change Triage

### Verify Only

| #   | Commit    | Summary                         | Affected Hosts   | Post-Deploy Check     |
| --- | --------- | ------------------------------- | ---------------- | --------------------- |
| 1   | `abc1234` | feat(terminal): add shell alias | workstations     | `type ll` in terminal |
| 2   | `def5678` | docs(os): update AGENTS.md      | none (docs only) | —                     |

### Ad-Hoc Fixes (before deploy)

| #   | Issue                                | Fix                         | Estimated Effort | Commit Ref   |
| --- | ------------------------------------ | --------------------------- | ---------------- | ------------ |
| 1   | Missing default for `foo.bar` option | Add `default = true`        | 5 min            | `ghi9012`    |
| 2   | ks doctor shows stale agent timer    | Reset timer in agent config | 10 min           | pre-existing |

### Needs Issue

| #   | Problem                              | Why Not Ad-Hoc                                | Severity |
| --- | ------------------------------------ | --------------------------------------------- | -------- |
| 1   | Service X needs migration to new API | Multi-host coordination, rollback plan needed | medium   |

## Deployment Plan

### Order

1. ncrmro-workstation (current host) — `ks update --lock`
2. ocean — remote deploy via Tailscale
3. mercury — remote deploy via VPS IP
4. [deferred: mox — unreachable]

### Flags

- `--boot` required: [yes — reason | no]
- Expected build time: [estimate based on change scope]

## Post-Deployment Verification Checklist

- [ ] `ks doctor` on current host shows no new issues
- [ ] [specific check for change 1]
- [ ] [specific check for change 2]
- [ ] Remote hosts: `ssh root@ocean systemctl --failed` shows no new failures
- [ ] Agent health: `agentctl <agent> status` nominal for all local agents
- [ ] Pre-existing issues: [resolved | still present — expected]

## Risk Assessment

- **Overall risk**: [low | medium | high]
- **Rollback plan**: Previous generation available via `nixos-rebuild switch --rollback`
- **Blockers**: [none | list blockers that must be resolved before deploy]
```

## Quality Criteria

- Every commit in the keystone rev gap is classified as verify-only, ad-hoc-fix, or needs-issue — none are unaccounted for
- The plan includes a concrete checklist of things to verify after deployment, derived from the changes
- Items marked needs-issue have clear justification for why they can't be fixed ad-hoc (scope, risk, or complexity)

## Context

This step is the decision-making core of the update workflow. A good plan prevents deployment surprises by ensuring all changes are understood before `ks update --lock` runs. The triage categories directly drive the next step (execute_fixes) — ad-hoc items get fixed, needs-issue items get GitHub issues, and verify-only items go straight to the post-deploy checklist. The verification checklist becomes the acceptance criteria for the final validate step.
