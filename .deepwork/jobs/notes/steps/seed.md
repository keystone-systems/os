# Seed Index Notes

## Objective

Create initial Maps of Content (index notes) for the notebook's primary topics.

## Task

1. Examine the repo to understand its context:
   - If PROJECTS.yaml exists, use project names as initial topics
   - If SOUL.md exists, derive topics from the agent's responsibilities
   - For a human user's repo, ask what their primary knowledge domains are
   - If no context is available, create a minimal set: one index note for "Getting Started"

2. For each topic, create an index note:

   ```bash
   zk new index/ --title "<Topic Name>" --no-input --print-path
   ```

3. Each index note should have:
   - Correct frontmatter (type: index, tags: [index])
   - A brief description of what this topic covers
   - A placeholder `## Notes` section (will be populated as permanent notes are created)

4. Do NOT create excessive index notes — start with 3-5 at most. More will emerge organically.

## Output Format

Write `seed_report.md`:

```markdown
# Seed Report

## Index Notes Created

| ID           | Title               | File                                      |
| ------------ | ------------------- | ----------------------------------------- |
| 202603201430 | NixOS Configuration | index/202603201430 nixos-configuration.md |
| 202603201431 | Infrastructure      | index/202603201431 infrastructure.md      |
```
