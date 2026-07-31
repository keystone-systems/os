# Set Up Forgejo

## Objective

Sign into Forgejo on `git.ncrmro.com` and configure the `fj` CLI for authenticated access using the API token from rbw.

## Task

Authenticate with the self-hosted Forgejo instance using credentials from rbw and set up the fj CLI.

### Process

1. **Check existing fj CLI auth**
   - Run `fj auth status` or equivalent to see if already authenticated
   - If authenticated with the correct account, skip to verification

2. **Retrieve credentials**
   - Read SOUL.md for the Forgejo username and credential reference
   - Get the API token or password from rbw using the reference in SOUL.md's Credentials column
   - The credential entry name may be a keyfile reference — check `rbw search forgejo` or `rbw search git.ncrmro.com`

3. **Browser sign-in (if needed)**
   - Navigate to `https://git.ncrmro.com/user/login`
   - Enter username and password
   - Complete sign-in

4. **Configure fj CLI**
   - Authenticate fj with the Forgejo instance:
     ```
     fj auth login --host git.ncrmro.com --token <api-token>
     ```
   - If fj uses a different auth flow, follow its conventions (see `.agents/conventions/tool.forgejo.md` if available)
   - Verify with `fj auth status` or `fj repo list`

5. **Add SSH public key and configure signing (via Chrome MCP browser)**
   - **Prerequisite**: Only proceed after confirming browser sign-in works (step 3 succeeded)
   - Read the agent's SSH public key: `cat ~/.ssh/id_ed25519.pub` (or `~/.ssh/id_rsa.pub`)
   - Use Chrome DevTools MCP to add both keys via the Forgejo web UI:
     - Navigate to `https://git.ncrmro.com/user/settings/keys`
     - **Authentication key**: Click "Add Key" under "Manage SSH Keys", paste the public key, set title to `agent-<hostname>`, submit
     - **Signing key**: In the same page, find "Manage Signing Keys" or equivalent section, click "Add Key", paste the same public key, set title to `agent-<hostname>-signing`, submit
   - If the API is preferred as fallback:
     - Auth key: `curl -X POST https://git.ncrmro.com/api/v1/user/keys -H "Authorization: token <token>" -H "Content-Type: application/json" -d '{"title":"agent-<hostname>","key":"<pubkey>"}'`
   - Verify the keys appear in settings: navigate to `https://git.ncrmro.com/user/settings/keys` and take a snapshot
   - Test SSH connectivity: `ssh -T git@git.ncrmro.com`

6. **Verify access**
   - List repositories or user info to confirm access
   - Run a simple API call to confirm the token works
   - Confirm SSH clone works

## Output Format

### forgejo_status.md

```markdown
# Forgejo Sign-In Status

**Status**: Success / Failed
**Host**: git.ncrmro.com
**Username**: [Forgejo username]
**Auth Method**: API token
**Date**: [current date]

## Browser Sign-In

- Signed into Forgejo web UI: Yes/No

## CLI Configuration

- fj CLI authenticated: Yes/No
- Host configured: git.ncrmro.com
- fj auth status output: [summary]

## SSH Key

- Public key added: Yes/No
- Signing key added: Yes/No
- SSH test (`ssh -T git@git.ncrmro.com`): Success/Failed

## Issues

[Any issues encountered, or "None"]
```

## Quality Criteria

- Successfully signed into Forgejo web UI
- fj CLI is authenticated and can list repos or user info
- API token is working and stored appropriately
- SSH public key is added as both authentication and signing key
- SSH connectivity works (`ssh -T git@git.ncrmro.com`)

## Context

Forgejo is the primary Git hosting platform on the intranet. The fj CLI enables creating repos, issues, PRs, and managing milestones from the command line. All agent code changes flow through Forgejo PRs.
