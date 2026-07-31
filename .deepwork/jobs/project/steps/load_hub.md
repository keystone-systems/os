# Load Project Hub

## Objective

Find the project's index hub note in the notes repo via the zk tag system, then extract all
structured data needed for the health audit: repos, website URL, social media, and hub
field completeness.

## Steps

### 1. Find the hub note

Use `zk` to locate the hub note by its `index` type and project name tag:

```bash
NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
zk --notebook-dir "$NOTES_DIR" list index/ --tag "index" --tag "<project_name>" --format "{{absPath}}"
```

If no result, try variations in this order:
1. Search by `project:` frontmatter: `rg "^project: <project_name>" "${NOTES_DIR:-$HOME/notes}/index/" -l`
2. Search by `type: index` in frontmatter: `rg "type: index" "${NOTES_DIR:-$HOME/notes}/index/" -l` then check each for a matching title or name
3. Try alternate tag spellings (e.g. `ks-systems` vs `ks.systems`)

Note: Hub notes may be findable via `project:` frontmatter even when the project tag is missing from `tags:`. This is a common gap that `file_gaps` will correct by adding the tag.

If still not found, report it as a critical gap (hub note missing entirely) and proceed
with whatever repos can be inferred from the project name.

### 2. Parse the hub note

Read the full note frontmatter and body. Extract:

| Field | Source |
|-------|--------|
| Website URL | Body links, `website_url:` frontmatter, or `domains:` field |
| Social media | Body links to X/Twitter, LinkedIn, Bluesky, Mastodon, GitHub profile |
| Repos | `tags` containing `repo/<owner>/<repo>`, `repo_ref:` frontmatter, body links to GitHub/Forgejo repos |
| Project name | `name:` frontmatter |
| Status | `status/active`, `status/paused`, etc. tags |

For repos: check both the frontmatter and the body — hub notes often have repos as wikilinks
or markdown links. Parse both `repo/ncrmro/keystone` style tags and `https://github.com/...`
style links.

### 3. Identify the website repo

Among the extracted repos, identify which (if any) is the project's website:
- Name contains `web`, `site`, `www`, or `frontend`
- Description mentions "website", "landing page", or "marketing"
- Has a known web framework (Next.js, Astro, etc.) — check with `git ls-remote` or a quick
  `gh repo view` / `fj repo view`

### 4. Write the hub_report.md

Create `hub_report.md` with this structure:

```markdown
# Hub Report: <project_name>

## Hub Note
- Path: <notes-dir>/index/<id> <slug>.md
- Status: found | missing

## Fields

| Field | Status | Value |
|-------|--------|-------|
| Website URL | ✅ present / ❌ missing | https://... |
| Social: X/Twitter | ✅ / ❌ | ... |
| Social: LinkedIn | ✅ / ❌ | ... |
| Social: Bluesky | ✅ / ❌ | ... |
| Repos | ✅ N repos / ❌ none listed | ... |

## Repos

| Repo | Platform | URL | Role |
|------|----------|-----|------|
| ncrmro/keystone | github | https://github.com/ncrmro/keystone | source |
| ncrmro/ks-systems-web | github | https://github.com/ncrmro/ks-systems-web | website |

## Website Repo
- Identified: <repo> | None identified
```

## Notes

- Do NOT update the hub note yet — that happens in `file_gaps`
- If the hub note is missing entirely, still produce hub_report.md with the missing status
  so downstream steps know to file a hub creation issue
- Social media gaps are informational (lower priority issues) — repos and website are critical
