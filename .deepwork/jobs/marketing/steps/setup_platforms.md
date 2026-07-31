# Set Up Platform Credentials

## Objective

Sign into each platform that needs setup, create API apps/keys where applicable, and store all credentials securely per the credential storage method in common job info.

## Task

Using the discovery report from the previous step, set up credentials for each platform that was marked as needing setup. Use Chrome DevTools MCP for browser automation where sign-in or app creation is required.

### Process

For each platform needing setup (from discovery_report.md), follow the platform-specific process below. Skip platforms already set up or marked to skip.

#### X (Twitter)

1. Navigate to developer.twitter.com
2. Sign in or create a developer account
3. Create a new app/project
4. Generate API Key, API Secret, Bearer Token, Access Token, and Access Token Secret
5. Store all credentials using the item name format: `[project-name]/twitter-api`
   - Store each key as a custom field

#### LinkedIn

1. Navigate to linkedin.com/developers
2. Sign in and create a new app
3. Request necessary API products (Share on LinkedIn, Sign In with LinkedIn)
4. Generate Client ID and Client Secret
5. Store credentials using the item name format: `[project-name]/linkedin-api`

#### Instagram / Facebook (Meta)

1. Navigate to developers.facebook.com
2. Sign in and create a new app (Business type)
3. Add Instagram Graph API product
4. Generate access tokens
5. Store credentials using the item name format: `[project-name]/meta-api`

#### Bluesky

1. Navigate to bsky.app
2. Sign in or create account
3. Generate an app password (Settings > App Passwords)
4. Store credentials using the item name format: `[project-name]/bluesky`
   - Store handle and app password

### Important Guidelines

- **Never write credentials to files or terminal output** — use the credential store CLI directly
- If a platform requires email verification or 2FA, pause and ask the user to complete that step
- If a platform denies API access or requires approval, document the status and move on

## Output Format

### platform_status.md

**Save to**: `projects/[project_name]/marketing/platform_status.md`

```markdown
# Platform Setup Status: [Project Name]

## Summary

- **Platforms set up**: [count]
- **Platforms skipped**: [count]
- **Platforms pending**: [count]
- **Date**: [current date]

## X (Twitter)

- **Status**: [completed / skipped / pending approval / failed]
- **Credential Item**: [project-name]/twitter-api
- **API Access Level**: [free / basic / pro]
- **Notes**: [any issues or next steps]

## LinkedIn

- **Status**: [completed / skipped / pending approval / failed]
- **Credential Item**: [project-name]/linkedin-api
- **API Products**: [list of enabled products]
- **Notes**: [any issues or next steps]

## Instagram / Facebook

- **Status**: [completed / skipped / pending approval / failed]
- **Credential Item**: [project-name]/meta-api
- **App Type**: [business / consumer]
- **Notes**: [any issues or next steps]

## Bluesky

- **Status**: [completed / skipped / pending approval / failed]
- **Credential Item**: [project-name]/bluesky
- **Handle**: [handle without password]
- **Notes**: [any issues or next steps]
```

**Bad example — do NOT include actual secrets:**

```markdown
## X (Twitter)

- **API Key**: sk-abc123... ← NEVER DO THIS
```

## Quality Criteria

- Every supported platform has a status entry — either newly set up, already existing, or skipped with a reason
- All new credentials are confirmed stored with clear item names
- No API keys, tokens, or passwords appear in the output file
- Failed or pending setups have clear next-step instructions

## Context

This is the core setup step. Credentials stored here will be used by future marketing workflows (content posting, analytics, etc.). Clean naming conventions are critical so other agents and workflows can find these credentials later.
