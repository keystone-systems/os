# Update SOUL.md

## Objective

Update SOUL.md to reflect the actual state of all accounts after onboarding. Save any new or changed credentials to rbw.

## Task

Compare the current SOUL.md accounts table against what was actually configured during onboarding, and reconcile any differences.

### Process

1. **Read the verification report**
   - Review `verification_report.md` for the final state of each service
   - Note any new accounts created, usernames assigned, or auth methods changed

2. **Read current SOUL.md**
   - Parse the existing Accounts table
   - Identify entries that need updating (TBD usernames, changed auth methods, new services)

3. **Determine changes needed**
   - Compare each account's expected state (from verification) with SOUL.md
   - Build a list of changes:
     - New accounts to add (rows)
     - Existing entries to update (username, auth method, credentials reference)
     - Entries to mark as failed/incomplete if verification failed

4. **Update SOUL.md**
   - Edit the Accounts table to reflect the verified state
   - Ensure every entry has:
     - Correct username (not TBD)
     - Accurate auth method
     - Valid rbw credential reference
   - Do NOT change non-account sections of SOUL.md

5. **Save credentials to rbw**
   - For any new credentials not yet in rbw, add them:
     ```
     rbw add --uri <url> <entry-name> <username>
     ```
   - For changed credentials, update them:
     ```
     rbw edit <entry-name>
     ```
   - Verify saved credentials with `rbw get --full <entry-name>`

6. **Document changes**
   - Record every change made to SOUL.md and rbw in the changelog

## Output Format

### changelog.md

```markdown
# Onboarding Changelog

**Date**: [current date]
**Agent**: [name]

## SOUL.md Changes

| Field              | Before                 | After             | Reason                            |
| ------------------ | ---------------------- | ----------------- | --------------------------------- |
| GitHub username    | TBD                    | [actual-username] | Account created during onboarding |
| GitHub auth method | OAuth device flow      | Google OAuth      | Signed in via Google              |
| GitHub credentials | ~/.config/gh/hosts.yml | rbw `github.com`  | Stored in vault                   |

## rbw Changes

| Entry      | Action | Username   | URI                |
| ---------- | ------ | ---------- | ------------------ |
| github.com | Added  | [username] | https://github.com |

## No Changes Needed

- [List any accounts that were already correct]

## Failed / Incomplete

- [List any accounts that could not be set up, with reason]
```

## Quality Criteria

- The accounts table in SOUL.md matches the actual verified state of all services
- All new or updated credentials have been saved to rbw
- No TBD entries remain for services that were successfully configured
- Changelog accurately records every change made
- No credentials or secrets appear in the changelog — only entry names and usernames

## Context

This is the final step in onboarding. SOUL.md is the agent's source of truth for its own identity and accounts. If it falls out of sync with reality, future sessions will use stale or incorrect information. Keeping rbw in sync ensures credentials are available for subsequent operations.
