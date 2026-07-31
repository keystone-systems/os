# Convention: OS Requirements (os.requirements)

## OS Requirements

This convention outlines the system-level prerequisites handled by the underlying operating system (Keystone) that agents can rely upon without manual configuration.

## Pre-Configured Integrations

### Commit Signing

1. All commits are automatically signed using the agent's SSH key.
2. Keystone ensures Git is pre-configured for SSH signing by default via `commit.gpgsign = true` and `user.signingkey`.
3. Agents do not need to manually configure commit signing.

### SSH Keys

4. SSH keys are provisioned automatically at `/home/{agent}/.ssh/id_ed25519`.
5. These keys are authorized for both Git operations (Forgejo/GitHub) and SSH access.

### Email Configuration

6. The `himalaya` CLI is pre-configured with the agent's credentials.
7. SMTP and IMAP settings are automatically managed, allowing immediate use of `himalaya` for sending and receiving emails.

### Calendar and Contacts

8. The `calendula` CLI is pre-configured with the agent's CalDAV credentials; agents can
   use `calendula calendars list` immediately with no additional configuration.
9. The `cardamum` CLI is pre-configured with the agent's CardDAV credentials; agents can
   use `cardamum addressbooks list` immediately with no additional configuration.
   See `tool.stalwart` for how CalDAV/CardDAV collections are provisioned.

### MCP Servers

10. **Chrome DevTools**: The `chrome-devtools` MCP server is globally available and pre-configured to connect to the local headless Chrome instance.
11. **DeepWork**: The `deepwork` MCP server is pre-installed and available in the Nix development shell, providing workflow orchestration.

## Terminal Environment

See also `process.enable-by-default` for the design principle that agents receive the same environment as humans by default.

12. Agent systemd services (task-loop, scheduler, notes-sync) MUST run with the full home-manager terminal environment.
13. All tools available in an interactive agent shell MUST also be available in systemd service contexts — including `bash`, `git`, `gh`, `himalaya`, and other CLI tools.
14. Service units SHOULD source the agent's shell profile or use an equivalent mechanism to inherit the complete PATH and environment variables.
15. Failure to provide the full environment (e.g., missing `bash` on PATH) causes task execution to crash silently, leaving tasks in an invalid state (see [keystone#103](https://github.com/ncrmro/keystone/issues/103)).

See `process.keystone-principal-parity` for provisioning-time design patterns
that maintain agent/human parity at the script and Nix module level.
