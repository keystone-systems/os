# Run Update

## Objective

Guide the human through running `ks update --lock` to deploy all pending keystone changes to the fleet.

## Task

This is a **human-in-the-loop** step. The agent cannot run `ks update --lock` because it requires sudo. Present the exact command to run and capture the results.

### Process

1. **Present the exact command**
   - Read the build results from preflight_build to get the host list and confirm builds passed
   - **Always use `--lock` explicitly** — never omit it, even though it's the default

   **Determine deployment strategy based on risk:**
   - **Low risk (docs, conventions, terminal/desktop features)**: All hosts in one command:
     ```
     ks update --lock <host1>,<host2>,<host3>,<host4>
     ```
   - **Medium risk (OS module changes, service config)**: Recommend current host first, then remotes:
     ```
     # Step 1: Deploy to local host first
     ks update --lock <current-host>
     # Step 2: After verifying, deploy to remotes
     ks update --lock <remote1>,<remote2>,<remote3>
     ```
   - **High risk (bootloader, lanzaboote, Secure Boot, kernel changes)**: ONE local host with `--boot`, reboot, verify, THEN remotes:
     ```
     # Step 1: Deploy to local workstation/laptop ONLY (physical access required)
     ks update --lock --boot <local-host>
     # Step 2: REBOOT and verify Secure Boot works
     # Step 3: Only after confirming boot success, deploy to remotes
     ks update --lock --boot <remote1>,<remote2>
     ```
     **WARNING**: A past lanzaboote update broke Secure Boot on a remote server and required physical BIOS intervention. NEVER deploy bootloader changes to remote hosts first.

   **When `--boot` requires a reboot**, the current session will be lost. Before the human reboots, output clear resume instructions:

   ```
   After reboot, resume this workflow:
     claude --resume    # or: gemini
     > The ks.update workflow is at the run_update step.
     > I just rebooted after `ks update --lock --boot <host>`.
     > Boot was [successful / failed]. Next: [deploy remotes / run validate].
   ```

   Also write a `.deepwork/tmp/resume_context.md` file with:
   - Current workflow step (`run_update`)
   - Which hosts have been deployed and which remain
   - The verification checklist from the plan
   - The exact next command to run
     This file survives the reboot and gives the next session full context.

   - Include a brief summary of what's being deployed:
     - Number of keystone commits since last lock
     - Key changes (2-3 bullet points)
     - Which hosts and in what order
     - Risk level and why
   - Remind them this requires sudo

2. **Wait for results**
   - The human will run the command and report back
   - If the output is unclear, ask structured questions:
     - Did the build succeed for all hosts?
     - Were there any errors or warnings?
     - Did deployment succeed for each host?
     - Were any hosts skipped (unreachable)?

3. **Handle failures**
   - **Build failure**: Since preflight_build already validated, this is unexpected. Analyze the error:
     - If fixable ad-hoc: call `go_to_step` with `step_id: "execute_fixes"` to apply the fix and retry
     - If complex: document the error and ask the human for guidance
   - **Deploy failure** (switch-to-configuration): Document the error. This usually means a service failed to start.
     - Check `journalctl -xeu <service>` for details
     - Previous generation is available via `nixos-rebuild switch --rollback`
   - **Partial success** (some hosts deployed, others failed): Document which succeeded and which failed. The validate step will handle follow-up.

4. **Document the deployment**
   - Capture the key output from `ks update --lock`
   - Note the keystone commit that was locked
   - Record per-host deployment status

**Maximum loop iterations**: If the deploy fails twice after looping back to execute_fixes, stop and ask the human to investigate manually.

## Output Format

### update_result.md

```markdown
# Update Result

**Date**: [date/time]
**Command**: `ks update --lock <host1>,<host2>,<host3>`

## Keystone Revision

- **Previous locked**: `[old hash]`
- **Now locked**: `[new hash]`
- **Commits deployed**: [N]

## Build Results

| Host               | Build Status | Notes          |
| ------------------ | ------------ | -------------- |
| ncrmro-workstation | success      | —              |
| ocean              | success      | built remotely |
| mercury            | success      | —              |

## Deployment Results

| Host               | Deploy Status | Generation | Notes                         |
| ------------------ | ------------- | ---------- | ----------------------------- |
| ncrmro-workstation | success       | 476        | switched in-place             |
| ocean              | success       | 367        | deployed via Tailscale        |
| mercury            | failed        | 49         | connection timeout — deferred |

## Warnings

- [Notable warnings from build output, or "none"]

## Deferred Hosts

- [mox — unreachable since survey, skipped]

## Notes

- [Any relevant observations from the deploy process]
```

## Quality Criteria

- The human confirmed `ks update --lock` completed (at least partially)
- The locked keystone commit is documented
- Per-host deployment status is captured — successes and failures are both recorded
- Any warnings or issues are documented for the validate step

## Context

This is the only step requiring human intervention in the update workflow. `ks update --lock` is the full pipeline: pull repos, lock flake inputs, build all hosts, push the lock commit, and deploy sequentially. It requires sudo because NixOS system activation requires root. Since the preflight_build step already validated that all hosts build cleanly, failures here are typically service activation issues rather than build errors. After this step, the system is running the new configuration and the validate step will verify everything is nominal.
