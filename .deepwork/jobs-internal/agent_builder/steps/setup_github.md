# Set Up GitHub

## Objective

Sign into GitHub using Google OAuth, create an account if one doesn't exist, and configure the `gh` CLI for authenticated access.

## Task

Use the browser to sign into GitHub via Google, then configure the gh CLI.

### Process

1. **Check existing gh CLI auth**
   - Run `gh auth status` to see if already authenticated
   - If authenticated with the correct account, skip browser sign-in

2. **Browser sign-in via Google OAuth**
   - Navigate to `https://github.com/login`
   - Click "Continue with Google"
   - If Google account chooser appears, select the agent's Gmail account
   - If consent screen appears, click "Continue" to authorize
   - If redirected to a sign-up page (no existing GitHub account):
     - Choose a username (check SOUL.md for the expected username)
     - Complete the registration form
     - Note the new username for later SOUL.md update

3. **Configure gh CLI**
   - Run `gh auth login` using SSH protocol and device flow:
     ```
     gh auth login --hostname github.com --git-protocol ssh --web
     ```
   - This prints a one-time device code and a URL (`https://github.com/login/device`)
   - Use Chrome DevTools MCP to open the URL, enter the device code, and authorize
   - If GitHub requires sudo verification (email code), check Gmail via Chrome MCP to retrieve the code
   - After auth completes, request additional scopes for full repo management:
     ```
     gh auth refresh -h github.com -s delete_repo
     ```
     (Complete the device flow again via Chrome MCP for the scope upgrade)
   - Verify with `gh auth status`
   - **Important**: Always use SSH protocol, not HTTPS — SSH keys are already provisioned by Keystone

4. **Save credentials to rbw**
   - If a new account was created or credentials changed, save to rbw:
     ```
     rbw add --uri https://github.com github.com [username]
     ```
   - If entry already exists and needs updating: `rbw edit github.com`

5. **Add SSH public key and configure signing**
   - **Prerequisite**: Only proceed after confirming browser sign-in works (step 2 succeeded)
   - Read the agent's SSH public key: `cat ~/.ssh/id_ed25519.pub` (or `~/.ssh/id_rsa.pub`)
   - Check if the key is already added: `gh ssh-key list`
   - If the key is not already present, add it via CLI:
     - Authentication key:
       ```
       gh ssh-key add ~/.ssh/id_ed25519.pub --title "agent-$(hostname)" --type authentication
       ```
     - Signing key:
       ```
       gh ssh-key add ~/.ssh/id_ed25519.pub --title "agent-$(hostname)-signing" --type signing
       ```
   - **If CLI fails**, use Chrome DevTools MCP browser as fallback:
     - Navigate to `https://github.com/settings/ssh/new`
     - Set title to `agent-<hostname>`
     - Set key type to "Authentication Key", paste public key, submit
     - Repeat for "Signing Key" type
   - Configure git to use SSH signing:
     ```
     git config --global gpg.format ssh
     git config --global user.signingkey ~/.ssh/id_ed25519.pub
     git config --global commit.gpgsign true
     ```
   - Verify the key appears on GitHub: `gh ssh-key list`

6. **Verify access**
   - Run `gh api user` to confirm API access
   - Test SSH connectivity: `ssh -T git@github.com`
   - Note the username and account details

## Output Format

### github_status.md

```markdown
# GitHub Sign-In Status

**Status**: Success / Failed
**Username**: [GitHub username]
**Account**: New / Existing
**Auth Method**: Google OAuth
**Date**: [current date]

## Browser Sign-In

- Signed in via Google OAuth: Yes/No
- Account created: Yes/No (if new)

## CLI Configuration

- gh CLI authenticated: Yes/No
- Protocol: ssh
- Scopes: [list of scopes, should include repo, delete_repo, gist, read:org]
- gh auth status output: [summary]

## SSH Key

- Public key added: Yes/No
- Signing key added: Yes/No
- SSH test (`ssh -T git@github.com`): Success/Failed
- Git commit signing configured: Yes/No

## Credentials

- Saved to rbw: Yes/No / Already existed

## Issues

[Any issues encountered, or "None"]
```

## Quality Criteria

- Successfully signed into GitHub in the browser
- gh CLI is authenticated and can make API calls (`gh api user` succeeds)
- SSH public key is added as both authentication and signing key
- Git is configured to sign commits with the SSH key
- SSH connectivity works (`ssh -T git@github.com`)
- Username is recorded for SOUL.md update
- Credentials are saved to rbw

## Context

GitHub access is needed for code hosting, PR workflows, and collaboration. The gh CLI enables command-line operations (creating PRs, managing issues, etc.). Google OAuth is the preferred auth method to avoid managing separate passwords.
