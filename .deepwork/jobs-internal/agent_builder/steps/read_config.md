# Read Configuration

## Objective

Parse SOUL.md and SERVICES.md to build a complete inventory of accounts, services, and CLIs that need to be set up during onboarding.

## Task

Read the agent's configuration files and produce a structured onboarding plan that covers every account and service.

### Process

1. **Read SOUL.md**
   - Extract the Accounts table (Service, Host, Username, Auth Method, Credentials)
   - Note the agent's email and identity details
   - Identify which accounts are fully configured vs. marked TBD or incomplete

2. **Read SERVICES.md**
   - Extract the services table (Service, Host, Purpose)
   - Cross-reference with SOUL.md accounts — flag any services without a corresponding account entry

3. **Identify CLI tools**
   - Check which CLIs are expected: `gh` (GitHub), `fj` (Forgejo), `rbw` (Vaultwarden)
   - For each CLI, check if it's installed: `which <tool>`
   - Note whether each CLI is authenticated: e.g., `gh auth status`, `fj auth status`

4. **Build the onboarding plan**
   - For each account/service, determine the required action:
     - **Sign in**: Account exists, needs browser login
     - **Create account**: No account exists yet, needs registration
     - **Configure CLI**: CLI needs authentication setup
     - **Skip**: Already fully configured
   - Order actions by dependency (e.g., Google sign-in before GitHub OAuth)

## Output Format

### onboarding_plan.md

```markdown
# Agent Onboarding Plan

**Agent**: [name from SOUL.md]
**Date**: [current date]

## Accounts Inventory

| Service      | Host           | Username   | Auth Method  | Status        | Action Required                      |
| ------------ | -------------- | ---------- | ------------ | ------------- | ------------------------------------ |
| Google/Gmail | google.com     | [email]    | Password     | Not signed in | Sign in via browser                  |
| GitHub       | github.com     | [username] | Google OAuth | Not signed in | Sign in via Google, configure gh CLI |
| Forgejo      | git.ncrmro.com | [username] | API token    | Not signed in | Sign in, configure fj CLI            |

## CLI Status

| Tool | Installed | Authenticated | Action Required |
| ---- | --------- | ------------- | --------------- |
| rbw  | Yes/No    | Yes/No        | [action]        |
| gh   | Yes/No    | Yes/No        | [action]        |
| fj   | Yes/No    | Yes/No        | [action]        |

## Onboarding Order

1. Unlock vault (rbw) — prerequisite for all credential access
2. Sign into Google/Gmail — prerequisite for OAuth flows
3. Sign into GitHub via Google OAuth + configure gh CLI
4. Sign into Forgejo + configure fj CLI
5. Verify all access
6. Update SOUL.md with any changes
```

## Quality Criteria

- Every account in SOUL.md is listed with its current status
- Every service in SERVICES.md is cross-referenced
- Each item has a clear, specific action (sign in, create account, configure CLI, or skip)
- CLI installation and auth status is checked with actual commands, not assumed
- Dependencies between steps are identified (e.g., Google before GitHub OAuth)

## Context

This is the first step in agent onboarding. The plan produced here drives all subsequent steps. An incomplete or inaccurate plan means services will be missed during setup.
