# Forgejo Project Board API Research

## Date: 2026-03-18

## Summary

Forgejo has **no REST API** for project boards, but the web UI uses internal HTTP
endpoints that **can be called programmatically via curl** using a session cookie.
API tokens (Basic auth, OAuth2 Bearer) do NOT work on these routes.

## Web Routes (from `routers/web/web.go`)

### Repo-Level Projects (`/{owner}/{repo}/projects/...`)

| Method | Path                                | Handler                        | Form Params                                        | Auth  |
| ------ | ----------------------------------- | ------------------------------ | -------------------------------------------------- | ----- |
| GET    | `/projects`                         | `repo.Projects`                | `sort`, `state`, `q`, `page`                       | read  |
| GET    | `/projects/{id}`                    | `repo.ViewProject`             | —                                                  | read  |
| GET    | `/projects/new`                     | `repo.RenderNewProject`        | —                                                  | write |
| POST   | `/projects/new`                     | `repo.NewProjectPost`          | `Title`, `Content`, `TemplateType`, `CardType`     | write |
| POST   | `/projects/{id}`                    | `repo.AddColumnToProjectPost`  | `Title`, `Color`                                   | write |
| POST   | `/projects/{id}/move`               | `project.MoveColumns`          | JSON body                                          | write |
| POST   | `/projects/{id}/delete`             | `repo.DeleteProject`           | —                                                  | write |
| GET    | `/projects/{id}/edit`               | `repo.RenderEditProject`       | —                                                  | write |
| POST   | `/projects/{id}/edit`               | `repo.EditProjectPost`         | `Title`, `Content`, `CardType`                     | write |
| POST   | `/projects/{id}/{open\|close}`      | `repo.ChangeProjectStatus`     | —                                                  | write |
| PUT    | `/projects/{id}/{columnID}`         | `repo.EditProjectColumn`       | `Title`, `Sorting`, `Color`                        | write |
| DELETE | `/projects/{id}/{columnID}`         | `repo.DeleteProjectColumn`     | —                                                  | write |
| POST   | `/projects/{id}/{columnID}/default` | `repo.SetDefaultProjectColumn` | —                                                  | write |
| POST   | `/projects/{id}/{columnID}/move`    | `repo.MoveIssues`              | JSON: `{"issues": [{"issueID": N, "sorting": N}]}` | write |

### Assign Issue to Project (`/{owner}/{repo}/issues/projects`)

| Method | Path               | Handler                   | Form Params                                | Auth  |
| ------ | ------------------ | ------------------------- | ------------------------------------------ | ----- |
| POST   | `/issues/projects` | `repo.UpdateIssueProject` | `issue_ids` (comma-sep), `id` (project ID) | write |

### Org-Level Projects (`/{org}/-/projects/...`)

Same structure as repo-level but under `/{org}/-/projects/`. Handlers are in `routers/web/org/`.

## Form Structures

```go
// CreateProjectForm — used for POST /projects/new and POST /projects/{id}/edit
type CreateProjectForm struct {
    Title        string  // required, max 100
    Content      string  // optional description
    TemplateType project_model.TemplateType  // template preset
    CardType     project_model.CardType      // card display type
}

// EditProjectColumnForm — used for POST /projects/{id} (add column) and PUT /projects/{id}/{columnID}
type EditProjectColumnForm struct {
    Title   string  // required, max 100
    Sorting int8    // column sort order
    Color   string  // max 7 chars (hex color)
}
```

## Authentication

### What works: Session cookie

The web auth chain is: OAuth2 → Basic → ReverseProxy → Session.

- **OAuth2**: Explicitly skips non-API paths (line 221-224 of `services/auth/oauth2.go`)
- **Basic**: Explicitly skips non-API paths (line 47 of `services/auth/basic.go`)
- **Session**: Works — checks `uid` in session store

**Only session-based auth works for project routes.**

### CSRF / Cross-Origin Protection

Forgejo uses Go 1.25's `net/http.CrossOriginProtection` (replaced older CSRF tokens).

- Checks `Sec-Fetch-Site` header (browser-only) and `Origin` vs `Host`
- **curl passes by default** — no `Sec-Fetch-Site` or `Origin` headers means the
  request is treated as same-origin or non-browser

### How to authenticate via curl

1. POST to `/user/login` with `user_name` and `password` form fields
2. Capture the `_gitea_session` (or equivalent) cookie from the response
3. Use that cookie for all subsequent requests

```bash
# Step 1: Login and capture session cookie
curl -c cookies.txt -X POST 'https://git.ncrmro.com/user/login' \
  -d 'user_name=drago&password=PASSWORD_HERE'

# Step 2: Create a project
curl -b cookies.txt -X POST 'https://git.ncrmro.com/{owner}/{repo}/projects/new' \
  -d 'Title=My+Board&Content=Description&TemplateType=1&CardType=0'

# Step 3: Add a column
curl -b cookies.txt -X POST 'https://git.ncrmro.com/{owner}/{repo}/projects/{id}' \
  -d 'Title=In+Progress&Color=%230075ca'

# Step 4: Assign issue to project
curl -b cookies.txt -X POST 'https://git.ncrmro.com/{owner}/{repo}/issues/projects' \
  -d 'issue_ids=1,2,3&id=PROJECT_ID'

# Step 5: Move issue to column
curl -b cookies.txt -X POST 'https://git.ncrmro.com/{owner}/{repo}/projects/{id}/{columnID}/move' \
  -H 'Content-Type: application/json' \
  -d '{"issues": [{"issueID": 42, "sorting": 0}]}'
```

## Data Model (`models/project/`)

### Project (`project.go`)

- `ID`, `Title`, `Description`, `CreatorID`, `RepoID`
- `TemplateType` — preset column layout
- `CardType` — how cards display
- `Type` — `TypeRepository` (2) or `TypeOrganization` (3)
- `IsClosed`

### Column (`column.go`)

- `ID`, `Title`, `Color`, `ProjectID`, `CreatorID`, `Sorting`
- Default column marked via `Default` bool

### Issue-Project Link (`issue.go`)

- `ProjectIssue` table: `IssueID`, `ProjectID`, `ProjectColumnID`, `Sorting`
- Issues are assigned to both a project and a specific column within it

## Template Types

From `template.go`:

- `TemplateTypeNone` (0) — no preset columns
- `TemplateTypeBasicKanban` (1) — creates: Uncategorized, To Do, In Progress, Done
- `TemplateTypeBugTriage` (2) — creates: Needs Triage, High Priority, Low Priority, Closed

## Key Findings

1. **Programmatic access IS possible** via session cookie + curl
2. **No API token auth** — tokens are explicitly rejected on web routes
3. **No CSRF barrier** — Go's CrossOriginProtection passes non-browser requests
4. **Many handlers return JSON** — `AddColumnToProjectPost`, `EditProjectColumn`,
   `DeleteProjectColumn`, `SetDefaultProjectColumn`, `MoveIssues`, and `UpdateIssueProject`
   all return `ctx.JSONOK()` or JSON responses, making them curl-friendly
5. **`NewProjectPost` returns a redirect** (302), not JSON — need to follow or ignore
6. **The `issue_ids` param for UpdateIssueProject uses internal DB issue IDs, not issue numbers** —
   need to resolve issue number → issue ID first (available via the Forgejo API: `GET /api/v1/repos/{owner}/{repo}/issues/{number}`)

## Feasibility Assessment

**Feasible with caveats:**

- Need to maintain a session cookie (login once, reuse)
- Session may expire — need to handle re-login
- `NewProjectPost` redirects instead of returning JSON — parse the redirect URL to get the project ID
- Issue assignment uses internal IDs — need an API call to resolve issue numbers first
- A helper script wrapping these curl calls would make this practical for the `repo` job

## Proof of Concept Results (2026-03-18)

All operations tested successfully against `git.ncrmro.com/ncrmro/agents`:

| Operation               | Endpoint                                          | HTTP Status | Response                |
| ----------------------- | ------------------------------------------------- | ----------- | ----------------------- |
| Login                   | `POST /user/login`                                | 303         | Session cookie set      |
| List projects           | `GET /{owner}/{repo}/projects`                    | 200         | HTML page               |
| Create project          | `POST /{owner}/{repo}/projects/new`               | 303         | Redirect to `/projects` |
| Add column              | `POST /{owner}/{repo}/projects/{id}`              | 200         | `{"ok":true}`           |
| Assign issue to project | `POST /{owner}/{repo}/issues/projects`            | 200         | `{"ok":true}`           |
| Move issue to column    | `POST /{owner}/{repo}/projects/{id}/{colID}/move` | 200         | `{"ok":true}`           |
| Delete project          | `POST /{owner}/{repo}/projects/{id}/delete`       | 200         | `{"redirect":"..."}`    |

**All operations work with session cookie auth + no special headers.**

## Recommended Next Steps

1. Create a `scripts/forgejo-project.sh` helper in the `repo` job that wraps login + CRUD
2. Update the board step instructions to use the script instead of "manual web UI instructions"
3. Handle session expiry with automatic re-login
