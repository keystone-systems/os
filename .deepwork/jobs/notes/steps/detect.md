# Detect Source Format

## Objective

Quickly identify the source note-taking system and whether this is a keystone-managed repo. This informs all downstream steps with format-specific handling.

## Task

Run the following checks in order (fast filesystem checks, no content reading):

### 1. Keystone Detection (silent)

Check for keystone markers — if found, keystone conventions apply automatically:

```bash
# Any of these present = keystone repo
ls -1 TASKS.yaml AGENTS.md SOUL.md SCHEDULES.yaml PROJECTS.yaml 2>/dev/null
```

Do NOT announce keystone detection to the user. Just record it in the report and let downstream steps handle it.

### 2. Source Format Detection

Check for app-specific artifacts:

**Obsidian vault:**

```bash
[ -d .obsidian ] && echo "OBSIDIAN"
ls .obsidian/plugins/ 2>/dev/null  # List installed plugins
ls .obsidian/workspace.json 2>/dev/null
```

Obsidian-specific syntax to watch for (sample 5 files):

- Callouts: `> [!note]`, `> [!warning]`, `> [!tip]`
- Dataview queries: ` ```dataview `
- Embedded files: `![[filename]]`
- Block references: `^block-id`, `[[note#^block-id]]`
- Aliases in frontmatter: `aliases: [...]`
- Tags as `#tag` inline (not just frontmatter)

**Apple Notes export:**

```bash
# Apple Notes exports typically have HTML fragments, no frontmatter, and attachment dirs
# Check for HTML tags in markdown files
head -20 *.md 2>/dev/null | grep -l '<div>\|<br>\|<span>' | head -3
# Check for "Attachments" or "Media" directories
ls -d Attachments Media 2>/dev/null
```

**Plain markdown:** No app-specific markers found.

### 3. Structure Summary

Quick directory stats (no content reading):

```bash
# Top-level dirs
ls -d */ 2>/dev/null
# Total markdown count
find . -name "*.md" -not -path "./.git/*" -not -path "./.zk/*" -not -path "./.obsidian/*" -not -path "./.deepwork/*" -not -path "./.claude/*" | wc -l
# Existing zk setup?
[ -d .zk ] && echo "ZK_ALREADY_INIT"
```

## Output Format

Write `detection_report.md`:

```markdown
# Detection Report

## Source Format

- **Detected**: Obsidian | Apple Notes | Plain Markdown
- **Confidence**: High | Medium (explain why)

## Keystone Repo

- **Is keystone**: yes | no
- **Markers found**: (list files found)

## Format-Specific Artifacts

- (list what was found: plugins, callouts, dataview, HTML fragments, etc.)

## Structure

- **Top-level directories**: (list)
- **Total markdown files**: N
- **Existing zk setup**: yes | no

## Recommendations

- (brief notes for downstream steps, e.g., "Obsidian callouts should be preserved as-is" or "Apple Notes HTML needs stripping")
```

## Important Notes

- This step is READ-ONLY — do not modify any files
- Do NOT read note content beyond sampling a few files for syntax detection
- Keystone detection is silent — do not prompt the user about it
- Speed matters — this should complete in seconds, not minutes
