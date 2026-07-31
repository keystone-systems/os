# File Issues for Gaps

## Objective

For every gap found in the hub audit and health audit, file a targeted GitHub or Forgejo
issue so it can be assigned and tracked. Update the hub note with any fields that can be
filled in automatically.

## Steps

### 1. Triage all gaps

Read `hub_report.md` and `health_report.md`. Build a gap list:

| Gap Type | Severity | Action |
|----------|----------|--------|
| Hub note missing | Critical | File issue to create hub note |
| Hub: website URL missing | High | File issue to add website URL to hub |
| Hub: no repos listed | High | Update hub note with repo_ref tags (automatic) |
| Hub: social media missing | Low | File issue (informational) |
| Blog infrastructure missing | High | File issue on website repo to scaffold blog |
| Missing release post | Medium | File one issue per release on website repo |
| Repo/doctor failures | Varies | Defer to repo/doctor's own issue filing |

Skip filing issues for gaps that `repo/doctor` already handles — those are reported but not
duplicated here.

### 2. Update the hub note automatically

For any repos that were discovered but not yet listed in the hub note, add them now:
- Add `repo/<owner>/<repo>` tags to the frontmatter `tags:` list
- This does not require an issue — just update the note directly

Only commit if frontmatter was actually changed — skip if all repos were already listed:
```bash
NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
git -C "$NOTES_DIR" diff --quiet || git -C "$NOTES_DIR" add . && git -C "$NOTES_DIR" commit -m "chore(hub): add repo refs to <project> hub note"
```

### 3. File: blog infrastructure issue (if missing)

If `blog_infrastructure: missing` for any website repo, file ONE issue on that repo:

```
Title: feat(posts): add MDX blog/posts infrastructure

Body:
## Context
The <project> website at <url> does not have a blog or posts section.
Press releases and release announcements need a published home on the website.

## Required
- A `src/content/posts/` directory (or equivalent) that accepts MDX files
- A `/posts` index page listing all posts by category
- A `/posts/[slug]` dynamic route rendering individual posts
- Posts use `export const metadata = { title, description, author, date }` frontmatter

## Standard
See `ncrmro/ks-systems-web` for the reference implementation:
- `src/content/posts/` — MDX files with dot-notation naming: `keystone.v0-8-0-os-agents.mdx`
- `src/app/posts/page.tsx` — index page grouping posts by category
- `src/app/posts/[slug]/page.tsx` — dynamic route
- `src/lib/content/posts.ts` — content loader

## Assignable to Copilot / agents
This is a well-defined implementation task suitable for automated agents.

## Releases waiting to be published
<list releases that are missing posts>
```

Label it: `feat`, `content`, `good first issue` (and `copilot` if available).

### 4. File: one issue per missing release post

For each release that has no corresponding published MDX post, file one issue on the
**website repo**:

```
Title: feat(posts): publish release post for <project> <version>

Body:
## Release
- Version: <version>
- Date: <date>
- Source: <link to release notes or GitHub release>
- Headline: <title of release>

## Task
Create `src/content/posts/<project>.v<version-dashes>-<slug>.mdx` with:

```mdx
export const metadata = {
  title: "<project> <version> — <headline>",
  description: "<one-line summary>",
  author: "NCRMRO",
  date: "<date>",
};

# <project> <version> — <headline>

<content from release notes>
```

## Source material
Release notes: <link or path>

## Assignable to Copilot / agents
```

File these issues individually — not as a bulk issue — so each can be independently assigned.

When passing the body to `gh issue create`, use a heredoc or a temp file to avoid shell
quoting issues with the embedded code block:
```bash
gh issue create --title "feat(posts): publish release post for <project> <version>" \
  --body-file /tmp/release-post-issue-<version>.md --label "feat,content"
```

### 5. Write gap_report.md

```markdown
# Gap Report: <project_name>

## Hub Note Updates (applied automatically)
- Added repo_ref tags: repo/ncrmro/keystone, ...

## Issues Filed

| Gap | Issue | URL |
|-----|-------|-----|
| Blog infrastructure missing | feat(posts): add MDX blog/posts infrastructure | https://... |
| Missing post: v0.7.0 | feat(posts): publish release post for keystone v0.7.0 | https://... |
| Missing post: v0.6.0 | feat(posts): publish release post for keystone v0.6.0 | https://... |

## Skipped Gaps

| Gap | Reason |
|-----|--------|
| Social media missing | Low priority — informational only, no issue filed |
| Repo convention gaps | Handled by repo/doctor |

## Summary
- Hub note updated: yes / no
- Issues filed: N
- No action needed: N gaps already covered
```

## Notes

- Use `gh issue create` for GitHub repos, `fj issue create` for Forgejo repos
- Do NOT file duplicate issues — before filing, check open issues for the same title with
  `gh issue list --search "feat(posts): publish release post for <project> <version>"`
- For the blog infrastructure issue, add a checklist of all missing release posts as items
  in the body so the implementer knows the full backlog
- Notify the user of all issues filed at the end with a bulleted list of URLs
