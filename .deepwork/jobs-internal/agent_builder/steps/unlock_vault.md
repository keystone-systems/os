# Unlock Vault

## Objective

Ensure the Vaultwarden credential vault is unlocked via `rbw` and verify that all credentials needed for onboarding are accessible.

## Task

Unlock the vault and check that each credential referenced in the onboarding plan is present and retrievable.

### Process

1. **Check rbw status**
   - Run `rbw unlocked` to check if the vault is already unlocked
   - If locked, run `rbw unlock` to unlock it

2. **Verify required credentials**
   - Read the onboarding plan from the previous step
   - For each account that references rbw credentials (from SOUL.md's Credentials column), attempt to retrieve it:
     - `rbw get <entry-name>` to verify the credential exists
     - Do NOT log the actual password — just confirm it was found
   - Record which credentials were found and which are missing

3. **Handle missing credentials**
   - If a credential is missing, note it in the output
   - Missing credentials may need to be created during later steps (e.g., when creating a new account)

## Output Format

### vault_status.md

```markdown
# Vault Status

**Unlocked**: Yes
**Date**: [current date]

## Credential Check

| Entry              | Found  | Notes                |
| ------------------ | ------ | -------------------- |
| www.google.com     | Yes    | Username: [username] |
| github.com         | Yes    | Username: [username] |
| [fj keyfile entry] | Yes/No | [notes]              |

## Missing Credentials

- [List any credentials that could not be found, with notes on how they'll be resolved in later steps]

## Summary

[X] of [Y] required credentials found. [Notes on any issues.]
```

## Quality Criteria

- Vault is confirmed unlocked
- Every credential referenced in the onboarding plan has been checked
- Missing credentials are clearly documented with resolution plan
- No actual passwords or secrets appear in the output

## Context

This step gates all subsequent service logins. If the vault cannot be unlocked or critical credentials are missing, later steps will fail. Identifying missing credentials early allows the workflow to plan for account creation or manual credential entry.
