# Convention: GitHub (tool.github)

## Authentication

1. Account details MUST be defined in `SOUL.md`. Check `gh auth status` to verify authentication.
2. Re-authentication MUST use `gh auth login --hostname github.com --web` (device flow).
3. If the GitHub account uses Google OAuth (no standalone password), sign in via "Continue with Google" on the login page.
4. GitHub's device code form uses split inputs — each character MUST be entered individually via `press_key` (bulk `fill` does not work).

## SSH Key Management

5. The agent's ED25519 key (from ssh-agent) MUST be uploaded to GitHub as both an `authentication` key and a `signing` key.
6. RSA keys MUST NOT be used — only ED25519 keys from the ssh-agent are authorized.
7. Authentication keys MUST be listed with: `gh ssh-key list`.
8. Signing keys MUST be listed with: `gh api user/ssh_signing_keys` (requires `admin:ssh_signing_key` scope).
9. To add the key for authentication: `ssh-add -L | gh ssh-key add --title "{name}-ed25519" --type "authentication" -`.
10. To add the key for signing: `ssh-add -L | gh ssh-key add --title "{name}-signing-ed25519" --type "signing" -`.
11. The `gh` token MUST include the `admin:ssh_signing_key` and `admin:public_key` scopes. Missing scopes MUST be added with: `gh auth refresh -h github.com -s admin:ssh_signing_key`.

## Commit Signing Verification

12. The agent's commit email (from `SOUL.md`) MUST be added and verified on the GitHub account for signed commits to display as "Verified."
13. Account emails MAY be checked with: `gh api user/emails` (requires `user` scope; refresh with `gh auth refresh -h github.com -s user` if missing).
14. To add the email: `gh api user/emails -X POST -f "emails[]={email}"`.
15. GitHub sends a verification email after adding — the agent MUST complete verification before commits will show as "Verified."
16. Verification SHOULD be confirmed with: `gh api repos/{owner}/{repo}/commits/HEAD --jq '.commit.verification'` — the `reason` field MUST be `valid`.

## Usage

17. PRs SHOULD be listed with: `gh pr list --repo {owner}/{repo} --author @me --state open --json number,title,url`.
18. Pending repo invitations MAY be accepted with: `gh api /user/repository_invitations --jq '.[].id' | while read id; do gh api --method PATCH /user/repository_invitations/$id; done`.
19. GitHub repos MUST be cloned via `gh repo clone {owner}/{repo} .repos/{owner}/{repo}`.

## Project Boards

20. The `project` scope MUST be granted before using project commands: `gh auth refresh -s project`.
21. Key commands: `gh project create`, `gh project link`, `gh project item-add`, `gh project item-edit`, `gh project field-list`, `gh project item-list`, `gh project view`.
22. Built-in project workflows (Item closed → Done, PR merged → Done) handle Done transitions automatically — agents MUST NOT duplicate these.
23. See `process.project-board` for full board lifecycle and CLI reference.

## See Also

- For internal Forgejo repos (git.ncrmro.com), use `tool.forgejo` instead of this convention.
- `gh` is used only for public GitHub repos.

## Issue Comments

24. Issue comments MUST be posted with: `gh issue comment {number} --repo {owner}/{repo} --body "..."`.
25. Multi-line comment bodies MUST use a HEREDOC to preserve formatting:
    ```
    gh issue comment {number} --repo {owner}/{repo} --body "$(cat <<'EOF'
    ```

## Comment Title

Body content here.
EOF
)"
```
