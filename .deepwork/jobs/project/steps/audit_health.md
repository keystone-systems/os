# Audit Repo and Release Health

## Objective

For each repo in the project, run `repo/doctor` via a parallel sub-agent to audit
conventions. For each source repo, enumerate releases and check whether each release
has a corresponding published MDX post on the project's website.

## Steps

### 1. Run repo/doctor for each repo (parallel sub-agents)

For each repo listed in `hub_report.md`, launch a sub-agent (Task tool) running the
`repo/doctor` workflow. These run in parallel — one sub-agent per repo.

Each sub-agent should be invoked via the Task tool with a prompt like:
```
Start the repo/doctor workflow for <owner>/<repo>.
job_name: "repo", workflow_name: "doctor", goal: "audit repo health for <owner>/<repo>", session_id: <session_id>
Follow the steps and return a summary of: labels present/missing, branch protection status, open milestones, and boards.
```

Collect results. If a repo is inaccessible (no SSH/API access), record that as a skip
with reason.

### 2. Enumerate releases in source repos

For each **source repo** (non-website repos), find all releases/tags:

```bash
# GitHub
gh release list --repo <owner>/<repo> --limit 50

# Forgejo
fj release list --repo <owner>/<repo>

# Fallback: git tags
git -C <local-path> tag --sort=-version:refname | head -20
```

Also check for a `releases/` directory in the repo root — Keystone-style projects store
release notes at `releases/<version>/release_notes.md`. If found, use those as the
canonical release list.

For each release, record:
- Version (e.g. `v0.8.0`)
- Date
- Title / headline (first line of release notes)
- Source: GitHub release, git tag, or `releases/` directory

### 3. Check website for published posts

For each **website repo**, check whether blog/posts MDX infrastructure exists:

```bash
# Clone locally if not already present, then check
ls <website-repo>/src/content/posts/ 2>/dev/null || \
ls <website-repo>/content/posts/ 2>/dev/null || \
ls <website-repo>/posts/ 2>/dev/null
```

Common paths to check (in order):
1. `src/content/posts/`
2. `content/posts/`
3. `src/pages/blog/`
4. `pages/blog/`
5. `src/app/posts/` (Next.js App Router)

If no posts directory found: record `blog_infrastructure: missing`.

If found: list all `.mdx` and `.md` files. For each release found in step 2, check whether
a post exists that references the version (filename contains the version string, or file
content mentions the version in the title/metadata).

### 4. Write health_report.md

```markdown
# Health Report: <project_name>

## Repo Doctor Results

### <owner>/<repo>
- Labels: ✅ standard set present / ❌ missing: bug, enhancement, ...
- Branch protection: ✅ / ❌ main not protected
- Milestones: ✅ current milestone open / ❌ no open milestones
- Boards: ✅ / ❌

(repeat per repo)

## Release Coverage

### Source Repo: <owner>/<repo>
Releases found: N

| Version | Date | Title | Published Post | Post Path |
|---------|------|-------|----------------|-----------|
| v0.8.0 | 2026-03-17 | OS Agents | ✅ | src/content/posts/keystone.v0-8-0-os-agents.mdx |
| v0.7.0 | 2026-03-16 | Keys | ❌ missing | — |

### Website Repo: <owner>/<repo>
- Blog infrastructure: ✅ found at src/content/posts/ | ❌ missing
- Posts directory: src/content/posts/
- Total posts: N

## Summary

- Repos checked: N
- Releases found: N
- Posts published: N / N
- Missing posts: N
- Blog infrastructure missing: yes | no
```

## Notes

- **Scope**: This step checks whether posts exist — it does NOT create MDX files. If posts
  are missing, record them as gaps; `file_gaps` will file issues for an agent to create them.
- Run repo/doctor sub-agents in parallel — do not wait for each to finish before starting
  the next
- If the website repo is not cloned locally, clone it to `~/.keystone/repos/<owner>/<repo>/`
  using `gh repo clone <owner>/<repo> ~/.keystone/repos/<owner>/<repo>` (GitHub) or
  `git clone ssh://forgejo@git.ncrmro.com:2222/<owner>/<repo>.git ~/.keystone/repos/<owner>/<repo>` (Forgejo)
- Version matching is fuzzy: `v0-8-0`, `v0.8.0`, and `0.8.0` should all match release `v0.8.0`
