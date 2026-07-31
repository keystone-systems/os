# Verify Access

## Objective

Run verification checks on all services and CLIs to produce a consolidated pass/fail report.

## Task

Systematically verify that every service and CLI configured during onboarding is working correctly.

### Process

1. **Read status files from prior steps**
   - Read `google_status.md`, `github_status.md`, and `forgejo_status.md`
   - Note any services that reported failures

2. **Run live verification checks**

   For each service, run a concrete check:

   | Service         | Check Command / Action                                  | Pass Criteria                           |
   | --------------- | ------------------------------------------------------- | --------------------------------------- |
   | Google/Gmail    | Navigate to `https://mail.google.com` and take snapshot | Inbox page loads without sign-in prompt |
   | GitHub          | `gh api user`                                           | Returns JSON with correct username      |
   | GitHub (web)    | Navigate to `https://github.com` and take snapshot      | Shows authenticated user dashboard      |
   | GitHub SSH      | `ssh -T git@github.com`                                 | Authenticated successfully              |
   | GitHub SSH keys | `gh ssh-key list`                                       | Shows auth key and signing key          |
   | Forgejo         | `fj auth status` or `fj repo list`                      | Returns valid response                  |
   | Forgejo (web)   | Navigate to `https://git.ncrmro.com` and take snapshot  | Shows authenticated dashboard           |
   | Forgejo SSH     | `ssh -T git@git.ncrmro.com`                             | Authenticated successfully              |
   | Git signing     | `git config --global commit.gpgsign`                    | Returns `true`                          |
   | rbw             | `rbw unlocked`                                          | Returns unlocked status                 |

3. **Record results**
   - For each check: record pass/fail, the command run, and any error output
   - For failures: include the error message and a suggested remediation

## Output Format

### verification_report.md

```markdown
# Onboarding Verification Report

**Date**: [current date]
**Agent**: [name from SOUL.md]
**Overall Status**: All Passed / [N] Failures

## Service Checks

### Google/Gmail

- **Status**: PASS / FAIL
- **Check**: Navigated to mail.google.com
- **Result**: [what was observed]
- **Remediation**: [if failed, what to do]

### GitHub

- **Status**: PASS / FAIL
- **Check**: `gh api user`
- **Result**: [username returned / error]
- **Remediation**: [if failed]

### GitHub (Web)

- **Status**: PASS / FAIL
- **Check**: Navigated to github.com
- **Result**: [authenticated dashboard / sign-in page]

### Forgejo

- **Status**: PASS / FAIL
- **Check**: `fj auth status`
- **Result**: [output summary]
- **Remediation**: [if failed]

### Forgejo (Web)

- **Status**: PASS / FAIL
- **Check**: Navigated to git.ncrmro.com
- **Result**: [authenticated dashboard / sign-in page]

### Vault (rbw)

- **Status**: PASS / FAIL
- **Check**: `rbw unlocked`
- **Result**: [unlocked / locked]

## Summary

| Service      | Web       | CLI       | SSH       | Signing   | Overall   |
| ------------ | --------- | --------- | --------- | --------- | --------- |
| Google/Gmail | PASS/FAIL | N/A       | N/A       | N/A       | PASS/FAIL |
| GitHub       | PASS/FAIL | PASS/FAIL | PASS/FAIL | PASS/FAIL | PASS/FAIL |
| Forgejo      | PASS/FAIL | PASS/FAIL | PASS/FAIL | PASS/FAIL | PASS/FAIL |
| Vault        | N/A       | PASS/FAIL | N/A       | N/A       | PASS/FAIL |

**[X] / [Y] services fully operational.**
```

## Quality Criteria

- Every service from the onboarding plan has a pass/fail result
- Checks use actual commands or browser navigation, not assumptions from prior steps
- Any failures include error details and suggested remediation
- Summary table gives a clear at-a-glance status

## Context

This is the validation gate before finalizing onboarding. If any services fail verification, the agent knows exactly what needs to be fixed before it can operate normally. The verification report also serves as documentation of the agent's operational readiness.
