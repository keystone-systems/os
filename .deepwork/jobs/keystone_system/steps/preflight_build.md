# Preflight Build

## Objective

Run `ks build` for all target hosts to catch Nix evaluation errors before the human runs `ks update --lock`. This is a non-sudo, agent-driven step that validates the build will succeed.

## Task

Build all target hosts from the deployment plan to verify Nix evaluation and build pass. This catches errors early — before the human invests time in the full deploy.

### Process

1. **Determine target hosts**
   - Read the deployment plan from update_plan.md
   - Extract the ordered list of reachable hosts
   - These are the hosts that will be built

2. **Update flake lock to latest keystone**
   - In nixos-config, update the keystone flake input to pick up any fixes from execute_fixes:
     ```bash
     nix flake update keystone --flake <nixos-config-path>
     ```
   - This does NOT require sudo — it just updates flake.lock

3. **Build all target hosts**
   - Run `ks build` with the target hosts:
     ```bash
     ks build <host1>,<host2>,<host3>
     ```
   - This builds home-manager profiles for all specified hosts (no sudo needed)
   - Capture the full output

4. **Handle failures**
   - If a build fails with a Nix evaluation error:
     - Analyze the error (missing option, type mismatch, import failure)
     - Determine if the fix is in keystone or nixos-config
     - If fixable: call `go_to_step` with `step_id: "execute_fixes"` to apply the fix
     - If complex: document the error for the human
   - If all builds succeed: proceed to run_update

5. **Document results**
   - Record per-host build status
   - Note any warnings (Nix deprecation warnings are expected and can be ignored)

**Maximum loop iterations**: If builds fail twice after looping back to execute_fixes, stop and present the errors to the human.

## Output Format

### build_result.md

```markdown
# Preflight Build Result

**Date**: [date]
**nixos-config path**: [path]
**Keystone rev in flake.lock**: `[hash]`

## Build Command
```

ks build <host1>,<host2>,<host3>

```

## Per-Host Results

| Host | Build Status | Notes |
|------|-------------|-------|
| ncrmro-workstation | success | — |
| ocean | success | — |
| mercury | success | — |
| maia | success | — |

## Warnings

- [Notable warnings, or "none beyond standard Nix deprecation warnings"]

## Errors

- [Error details if any host failed, or "none"]

## Ready for Deploy

- **All hosts build clean**: [yes | no]
- **Recommended command**: `ks update --lock <host1>,<host2>,<host3>`
```

## Quality Criteria

- Every reachable host from the deployment plan was built — none were silently skipped
- All hosts build successfully, or failures are documented with error details

## Context

This step exists to catch build failures before the human invests time in the full `ks update --lock` pipeline. `ks build` runs without sudo and evaluates the Nix configuration for each host. If it passes here, `ks update --lock` is very likely to succeed (the main remaining risk is service activation, not the build itself). The build result also provides the exact `ks update --lock` command with host list for the human to copy-paste.
