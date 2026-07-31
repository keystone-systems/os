# Discover Project Context

## Objective

Read the project's PROJECTS.yaml and audit existing credentials to determine what platforms still need setup.

## Task

Gather the project context and audit existing credentials so the next step only sets up what's missing.

### Process

1. **Ask structured questions** to confirm project details:
   - Which project from PROJECTS.yaml to set up
   - Whether accounts should be business or personal for each platform
   - Any platforms to skip

2. **Read PROJECTS.yaml**
   - Find the project entry matching the user's input
   - Check if a `social_media` section already exists
   - Note any existing platform entries

3. **Audit existing credentials**
   - For each supported platform (see common job info), search the credential store for existing API keys or tokens
   - Use platform names and common aliases as search terms
   - Record which platforms already have credentials and which need setup

4. **Compile discovery report**
   - Summarize the project context
   - List platforms with existing credentials (and their credential store item names)
   - List platforms that still need setup
   - Note any special requirements from the user's answers

## Output Format

### discovery_report.md

**Save to**: `projects/[project_name]/marketing/discovery_report.md` (create directory if needed)

```markdown
# Social Media Discovery: [Project Name]

## Project Context

- **Project**: [name from PROJECTS.yaml]
- **Description**: [brief project description]
- **Account Type**: [business / personal / mixed]
- **Date**: [current date]

## Existing Credentials

| Platform   | Status              | Credential Item  | Notes       |
| ---------- | ------------------- | ---------------- | ----------- |
| [platform] | [found / not found] | [item name or —] | [any notes] |

[one row per supported platform]

## Platforms Needing Setup

- [list of platforms that need credentials created]

## Platforms to Skip

- [any platforms the user wants to skip, with reason]
```

## Quality Criteria

- All supported platforms are accounted for in the report
- Credential store was actually queried (not assumed)
- Project context matches PROJECTS.yaml
- User preferences for business vs personal are captured
- No secrets appear in the report — only item name references

## Context

This discovery step prevents duplicate work and ensures the setup step only touches platforms that actually need attention. The report feeds directly into the next step where browser automation creates accounts and API keys.
