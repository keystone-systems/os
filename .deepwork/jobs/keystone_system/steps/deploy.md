# Deploy

## Objective

Guide the human through running `ks update --lock` in nixos-config to deploy the merged keystone changes to the system.

## Task

This is a **human-in-the-loop** step. The agent cannot run `ks update --lock` because it requires sudo. Guide the human through the deployment and capture the results.

### Process

1. **Prompt the human**
   - Tell the user to run `ks update --lock` in their nixos-config directory
   - Remind them this will: pull latest keystone, lock flake.lock, build the full system, and deploy
   - Ask them to share the output when it completes

2. **Wait for results**
   - The human will run the command and report back
   - Ask structured questions if the output is unclear:
     - Did the build succeed?
     - Were there any errors or warnings?
     - Did the deployment (switch-to-configuration) succeed?

3. **Evaluate the deployment**
   - If `ks update --lock` succeeded: proceed to validate
   - If it failed with a build error: this is likely a Nix evaluation issue that wasn't caught in the build step. The agent should analyze the error and determine if it can be fixed. If so, call `go_to_step` with `step_id: "implement"` (this will require creating a new worktree since the previous one was cleaned up in merge)
   - If it failed with a deployment error (switch-to-configuration): document the error and ask the human for guidance

4. **Document the deployment**
   - Capture the key output from `ks update --lock`
   - Note the keystone commit that was locked

**Maximum loop iterations**: If the deploy fails twice, stop and ask the human to investigate manually rather than looping.

## Output Format

### deploy_result.md

```markdown
# Deploy Result

## Command

`ks update --lock` in nixos-config

## Keystone Revision

- **Locked commit**: `<hash from flake.lock>`
- **Previous commit**: `<previous hash>`

## Build Output

- **Status**: [success | failed]
- **Warnings**: [notable warnings, or "none beyond upstream deprecations"]

## Deploy Output

- **Status**: [success | failed]
- **NixOS generation**: [generation number if available]

## Notes

- [Any relevant observations from the deploy output]
```

## Quality Criteria

- The human confirmed `ks update --lock` completed successfully
- The locked keystone commit matches the merge result from the previous step
- Any warnings or issues are documented

## Context

This is the only step that requires human intervention. `ks update --lock` is the full pipeline: pull repos, lock flake inputs, build the complete NixOS system, push the lock commit, and switch to the new configuration. It requires sudo because NixOS system activation requires root. After this step, the system is running the new configuration and the validate step will verify everything is nominal.
