# Update Project Tracking

## Objective

Update PROJECTS.yaml with the social media setup status and a summary of the content strategy so the project file serves as a single source of truth.

## Task

Read the platform status and content strategy outputs, then add a `social_media` section to the project's entry in PROJECTS.yaml.

### Process

1. **Read inputs**
   - Read platform_status.md for credential status per platform
   - Read content_strategy.md for the strategy summary

2. **Read current PROJECTS.yaml**
   - Find the project entry
   - Check if a `social_media` key already exists (update if so, create if not)

3. **Construct the social_media section**
   - Add platform entries with setup status and Bitwarden item references
   - Add a strategy summary (condensed from the full strategy doc)
   - Add a `last_updated` date

4. **Write the updated PROJECTS.yaml**
   - Use the Edit tool to modify the file in place
   - Preserve all existing content — only add/update the `social_media` section

5. **Document the changes**
   - Create a diff summary showing what was added/changed

## Output Format

### projects_yaml_diff.md

**Save to**: `projects/[project_name]/marketing/projects_yaml_diff.md`

````markdown
# PROJECTS.yaml Update: [Project Name]

## Changes Made

- [Added / Updated] `social_media` section under project `[name]`
- [count] platform entries added
- Strategy summary added

## Social Media Section Added

```yaml
social_media:
  last_updated: "YYYY-MM-DD"
  platforms:
    twitter:
      status: [active / pending / skipped]
      credentials: "[bitwarden-item-name]"
    linkedin:
      status: [active / pending / skipped]
      credentials: "[bitwarden-item-name]"
    instagram:
      status: [active / pending / skipped]
      credentials: "[bitwarden-item-name]"
    bluesky:
      status: [active / pending / skipped]
      credentials: "[bitwarden-item-name]"
  strategy:
    pillars: ["pillar1", "pillar2", "pillar3"]
    posting_cadence: "[brief summary]"
    brand_voice: "[1-2 word tone descriptor]"
    full_strategy_doc: "projects/[project_name]/marketing/content_strategy.md"
```

## Verification

- [ ] PROJECTS.yaml parses as valid YAML
- [ ] Existing project data preserved
- [ ] No credentials appear in YAML — only Bitwarden item references
````

**Bad example — do NOT include secrets in YAML:**

```yaml
twitter:
  api_key: "sk-abc123" # NEVER store credentials in PROJECTS.yaml
```

## Quality Criteria

- PROJECTS.yaml contains a `social_media` section for the target project with platform entries and strategy summary
- The YAML content matches the platform_status.md and content_strategy.md deliverables
- Existing PROJECTS.yaml content is preserved (no data lost)
- PROJECTS.yaml remains valid, parseable YAML
- No credentials or secrets in the YAML — only Bitwarden item name references

## Context

This is the final step that ties everything together. PROJECTS.yaml is the canonical project registry, and having social media status there means any agent or workflow can quickly check what platforms are set up and where to find credentials. The `full_strategy_doc` path lets anyone find the detailed strategy when needed.
