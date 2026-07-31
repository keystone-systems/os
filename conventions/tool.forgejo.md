# Convention: Forgejo (tool.forgejo)

## Repository Access

1. Repositories MUST be cloned via SSH, not HTTPS.
2. If a repo was cloned with HTTPS, the remote MUST be updated: `git remote set-url origin git@...`.
3. Full clones MUST be used — do NOT use `--depth 1` unless explicitly requested.

## Git Workflow

4. Branches MUST use semantic prefixes: `feat/`, `fix/`, `docs/`, `refactor/`, `chore/`, `test/`.
5. Commit messages MUST use semantic style (e.g., `feat: add API route`, `fix: null check`).
6. Force-pushing to `main` MUST NOT be done without explicit approval.

## CI/Actions

7. Forgejo Actions workflows SHOULD live in `.forgejo/workflows/`.
8. Workflow files MUST be YAML and follow the Forgejo Actions syntax (GitHub Actions compatible subset).
9. Secrets MUST be configured via the Forgejo web UI, not committed to the repo.

## CLI Tools

Three CLIs are available for Forgejo interaction:

- **`fj`** (forgejo-cli) — primary CLI for scripted/non-interactive operations (issues, PRs, releases, wiki)
- **`fj-ex`** (forgejo-cli-ex) — primary CLI for Forgejo Actions operations (runs, job logs, reruns, cancellations, queued jobs, runner tokens)
- **`tea`** (Gitea tea) — used only for `tea api` raw API calls to cover entities `fj`/`fj-ex` lack (milestones, labels, webhooks, PR reviews, raw API inspection)

10. Agents MUST use `fj` as the primary CLI for issues, PRs, releases, and wiki.
11. Agents MUST use `fj-ex` as the primary CLI for Forgejo Actions workflows, including recent runs, queued jobs, job logs, reruns, cancellations, and runner token inspection.
12. Agents MUST use `tea api` for milestones, labels, webhooks, and any entity `fj` or `fj-ex` does not support.
13. Agents MUST NOT use `tea` interactive/TUI commands — only `tea api` is non-interactive and agent-safe.

### Common Flags

`fj` commands require the host flag at the top level. Repo context varies by subcommand — some accept `-r`/`--repo` (owner/repo slug), others accept `-R`/`--remote` (local git remote name). When running inside a cloned repo, `fj` auto-detects the remote, so explicit flags are often unnecessary.

```
fj -H https://git.ncrmro.com <subcommand> [args]
```

`tea api` commands require the login flag and take the endpoint directly:

```
tea api --login forgejo [method] <endpoint> [fields]
```

`tea api` supports `{owner}` and `{repo}` placeholders in endpoints that auto-resolve from `-r`.

All examples below omit the `-H` host flag for brevity. Prepend it to every `fj` command.

## Authentication

14. keystone.os provisions `fj` and `tea` authentication automatically. Agents SHOULD NOT manually configure auth under normal circumstances.
15. Verify `fj` auth: `fj whoami`.
16. Verify `tea` auth: `tea api --login forgejo /user`.
17. `fj-ex` MAY require an interactive web login for UI-backed Actions operations. When needed, authenticate with `fj-ex auth login --host <forgejo-host>`.
18. If `tea` returns "token is required": create a token via the Forgejo API using basic auth with the vault password, then update the tea login config.

## Actions (`fj-ex`)

19. Agents MUST use `fj-ex` first when they need queued jobs, recent runs, job logs, reruns, cancellations, or runner registration tokens on Forgejo.
20. Agents SHOULD preview destructive Actions operations with `--dry-run` when the subcommand supports it.
21. Agents MAY use `fj-ex actions logs job --latest --job-index <n>` to stream a single job's logs directly to stdout, but SHOULD redirect to a file before broad searching if the log is long.

```bash
# Interactive login for Actions/UI endpoints
fj-ex auth login --host forge.example.com

# Mint a NuGet API key
fj-ex token mint nuget --host forge.example.com --owner my-org

# List recent runs
fj-ex actions runs --repo owner/name --latest

# Stream one job's logs
fj-ex actions logs job --repo owner/name --latest --job-index 0

# Cancel / rerun
fj-ex actions cancel --repo owner/name --run-index 50 --dry-run
fj-ex actions rerun --repo owner/name --latest --failed-only

# Runner registration token + queued jobs
fj-ex actions runners token --repo owner/name
fj-ex actions runners jobs --repo owner/name --waiting
```

## Pull Request Workflow

22. PRs MUST be squash-merged.
23. PRs MUST have the repo owner assigned as reviewer. The reviewer is the `{owner}` from the repo slug `{owner}/{repo}`.
24. Draft PRs on Forgejo use a `WIP: ` title prefix (not a `--draft` flag).
25. PRs SHOULD reference the issue they resolve (e.g., `Closes #123`).

### Happy Path

1. **Create a branch** with a semantic prefix:

   ```bash
   git checkout -b feat/short-description
   ```

2. **Push and create the PR:**

   ```bash
   git push -u origin feat/short-description
   fj pr create "feat: short description" --head feat/short-description --base main --body "Closes #123"
   ```

3. **Request the repo owner as reviewer** (`fj` has no reviewer command; token is read from tea config since `fj auth list` only shows `user@host`):

   ```bash
   TOKEN=$(yq '.logins[] | select(.name == "forgejo") | .token' ~/.config/tea/config.yml)
   curl -s -X POST \
     -H "Authorization: token $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"reviewers":["{owner}"]}' \
     "https://git.ncrmro.com/api/v1/repos/{owner}/{repo}/pulls/{number}/requested_reviewers"
   ```

4. **Wait for approval.** Check status with:

   ```bash
   fj pr view {number}
   ```

5. **Squash merge** after approval:
   ```bash
   fj pr merge {number} --method squash --delete --title "feat: short description (#{number})"
   ```

## Issues (fj)

26. Issues SHOULD have descriptive titles and labels.

```bash
issue search [QUERY]                          # default: open
  # -l labels, -c creator, -a assignee, -s state (open|closed|all)
issue create "Title" --body "Description"
issue view <NUMBER>
issue comment <NUMBER> --body "Comment"
issue close <NUMBER>
issue edit <NUMBER> --title "New title"
```

## Releases (fj)

```bash
release create "v1.0.0" -T -b "Release notes"
  # -T: create tag, -a <FILE>: attach asset
release list
release view <NAME>
release edit <NAME>
release delete <NAME>
```

## Wiki (fj)

```bash
wiki contents
wiki view <PAGE>
wiki clone
```

## Advanced: tea api

### Milestones

```bash
tea api --login forgejo /repos/{owner}/{repo}/milestones                                    # list
tea api --login forgejo -X POST /repos/{owner}/{repo}/milestones -f title="v1.0"           # create (simple values only)
tea api --login forgejo -X PATCH /repos/{owner}/{repo}/milestones/{id} -f state="closed"   # update
tea api --login forgejo -X DELETE /repos/{owner}/{repo}/milestones/{id}                     # delete
```

**Note**: `tea api -f` breaks when values contain spaces. For milestones with spaces in title or description, use the curl fallback below.

### Labels

```bash
tea api --login forgejo /repos/{owner}/{repo}/labels                                        # list
tea api --login forgejo -X POST /repos/{owner}/{repo}/labels -f name="bug" -f color="#ee0701"
tea api --login forgejo -X DELETE /repos/{owner}/{repo}/labels/{id}
```

### PR Reviews

```bash
tea api --login forgejo /repos/{owner}/{repo}/pulls/{index}/reviews                         # list reviews
tea api --login forgejo -X POST /repos/{owner}/{repo}/pulls/{index}/reviews \
  -f body="LGTM" -f event="APPROVED"                                                       # submit review
```

### Curl Fallback

When `tea api -f` cannot handle the payload (spaces in values, JSON arrays, nested objects), use `curl` directly:

```bash
TOKEN=$(yq '.logins[] | select(.name == "forgejo") | .token' ~/.config/tea/config.yml)
curl -s -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"My Milestone","description":"Has spaces and special chars"}' \
  "https://git.ncrmro.com/api/v1/repos/{owner}/{repo}/milestones"
```

### Raw API Fallback

27. For any entity not covered above, agents SHOULD use `tea api` or `curl` with the [Forgejo API docs](https://git.ncrmro.com/api/swagger).

## Known Limitations

- **`fj pr view` does not accept `-r owner/repo`** — must be run from inside the repo's git directory, or use `tea api /repos/{owner}/{repo}/pulls/{number}` instead.
- **`fj pr merge` returns 405 if the PR has not been approved** — this means approval is pending, not a bug. Wait for review.
- **Agents cannot self-approve PRs** — a PR created by an agent cannot be approved by that same agent.

## Project Boards

28. Forgejo has no project board REST API (as of 14.x). Agents MUST use the `forgejo-project` CLI (provided by keystone) for all board operations.
29. See `process.project-board` for full board lifecycle and Forgejo-specific guidance.
30. Agents MUST set `FORGEJO_HOST`, `FORGEJO_USER`, and `FORGEJO_PASSWORD_CMD` environment variables.
31. The script auto-authenticates on first use and re-authenticates on session expiry.
32. `FORGEJO_PASSWORD_CMD` MUST delegate to a credential manager (`rbw`, `pass`, etc.) — passwords MUST NOT be stored in plaintext.

```bash
# Auth — login once, session cookie cached at ~/.local/state/forgejo-project/cookies.txt
forgejo-project login --host git.example.com --user alice \
  --password-cmd "rbw get git.example.com --field password"

# Project CRUD
forgejo-project create --repo owner/repo --title "v1.0" --template basic-kanban
forgejo-project list   --repo owner/repo                 # outputs JSON
forgejo-project close  --repo owner/repo --project 5
forgejo-project open   --repo owner/repo --project 5
forgejo-project delete --repo owner/repo --project 5

# Column CRUD
forgejo-project column add     --repo owner/repo --project 5 --title "In Review" --color "#0075ca"
forgejo-project column list    --repo owner/repo --project 5  # outputs JSON
forgejo-project column edit    --repo owner/repo --project 5 --column 3 --title "Reviewing"
forgejo-project column default --repo owner/repo --project 5 --column 1
forgejo-project column delete  --repo owner/repo --project 5 --column 3

# Issue management
forgejo-project item add  --repo owner/repo --project 5 --issue 42
forgejo-project item move --repo owner/repo --project 5 --issue 42 --column 3
forgejo-project item list --repo owner/repo --project 5   # outputs JSON
```

Issue numbers are automatically resolved to internal DB IDs via the REST API
(`/api/v1/repos/{owner}/{repo}/issues/{number}`), which does accept session cookies.

## See Also

- For public GitHub repos, use `tool.github` instead of this convention.

## Admin CLI (Server-side Provisioning)

When running on the same server as Forgejo, the `forgejo admin` CLI does **not** require
API tokens. It bypasses the HTTP API entirely and talks directly to the database using
credentials from `app.ini`. Security is enforced via local file permissions — the command
must run as the Forgejo system user.

28. The admin CLI only supports: `user create`, `user list`, `user change-password`,
    `user delete`, `user generate-access-token`, `user must-change-password`, `user reset-mfa`.
29. There are **no admin CLI commands** for SSH key management, repository operations, or
    token deletion — these MUST use the HTTP API with a generated token.

```bash
# CLI operations (no token needed, must run as forgejo user):
sudo -u forgejo forgejo --work-path /var/lib/forgejo admin user list
sudo -u forgejo forgejo --work-path /var/lib/forgejo admin user create --username <name> ...
sudo -u forgejo forgejo --work-path /var/lib/forgejo admin user generate-access-token \
  --username <name> --token-name <name> --scopes "..." --raw

# API operations (require token, used for SSH keys + repos):
curl -H "Authorization: token $TOKEN" http://127.0.0.1:3000/api/v1/admin/users/<name>/keys
curl -H "Authorization: token $TOKEN" http://127.0.0.1:3000/api/v1/admin/users/<name>/repos
curl -X DELETE -H "Authorization: token $TOKEN" \
  http://127.0.0.1:3000/api/v1/users/<name>/tokens/<token-name>
```
