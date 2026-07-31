# Audit Branch Protection

## Objective

Deep check of branch protection rules on the default branch. Attempt to enable missing protections via API.

## Task

### Process

1. **Read platform context** from `platform_context.md`

2. **Fetch current branch protection** (same as check_branch_protection)

   **GitHub:**

   ```bash
   gh api repos/{owner}/{repo}/branches/{default_branch}/protection
   ```

   **Forgejo:**

   ```bash
   tea api --login forgejo /repos/{owner}/{repo}/branch_protections
   ```

3. **Check all expected protections**

   Same checklist as check_branch_protection:
   - Require PR reviews (min 1 approval)
   - Dismiss stale reviews
   - Require status checks (if CI configured)
   - Restrict force pushes
   - Restrict deletions

4. **Attempt to enable missing protections**

   **GitHub:**

   ```bash
   gh api repos/{owner}/{repo}/branches/{default_branch}/protection \
     --method PUT \
     --input - <<EOF
   {
     "required_pull_request_reviews": {
       "required_approving_review_count": 1,
       "dismiss_stale_reviews": true
     },
     "enforce_admins": true,
     "restrictions": null,
     "required_status_checks": null,
     "allow_force_pushes": false,
     "allow_deletions": false
   }
   EOF
   ```

   - Be careful: this replaces the entire protection config. Read existing settings first and merge.

   **Forgejo:**
   - Use the branch protection API to create or update rules
   - `tea api --login forgejo --method POST /repos/{owner}/{repo}/branch_protections`

5. **Verify changes**
   - Re-fetch protection rules to confirm the changes took effect
   - Document any API errors or permission issues

## Output Format

### branch_protection_audit.md

```markdown
# Branch Protection Audit

## Repository

- **Repo**: [owner/repo]
- **Default Branch**: [branch name]
- **Platform**: [github | forgejo]

## Findings

| Protection            | Before               | After                | Action                                             |
| --------------------- | -------------------- | -------------------- | -------------------------------------------------- |
| Require PR reviews    | [enabled \| missing] | [enabled \| missing] | [enabled via API \| already set \| failed: reason] |
| Dismiss stale reviews | ...                  | ...                  | ...                                                |
| Require status checks | ...                  | ...                  | ...                                                |
| Restrict force pushes | ...                  | ...                  | ...                                                |
| Restrict deletions    | ...                  | ...                  | ...                                                |

## Actions Taken

- [List of API calls made and their results]

## Remaining Gaps

- [Protections that could not be enabled, with reasons]
- [Or "None — all protections are in place"]
```

## Quality Criteria

- All branch protection rules have been inspected
- Missing protections were attempted to be enabled via API
- Any gaps that could not be fixed are documented with reasons
