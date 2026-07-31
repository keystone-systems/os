# Setup Repositories

## Objective

Create any repositories that don't exist yet and ensure all agents have SSH access to all project repos.

## Task

Read the README.yaml profile and investigation_report.md to identify repos that need to be created or where agent access is missing. Ask the user for decisions about where to create new repos. Skip this step quickly if all repos exist and agents have access.

### Process

1. **Assess what needs to be done**
   - Read the investigation_report.md access matrix
   - Read the repos section of README.yaml
   - Identify repos that need to be created and repos with missing agent access

2. **Create missing repos** (if any)

   For each repo that needs to be created, ask structured questions using the AskUserQuestion tool:
   - "Where should [repo-name] be created?" — Options: Forgejo, GitHub, Other
   - "Should it be public or private?"
   - "Under which org/owner?"

   Then create using the appropriate platform CLI (see common job info for tool conventions). Example flags:
   - `tea repo create --name <name> --owner <owner> [--private]`
   - `gh repo create <owner>/<name> [--private] [--description "..."]`

3. **Fix agent access** (if any repos are inaccessible)
   - Check if the issue is SSH key configuration or missing collaborator invites
   - Document what needs to be done by a human if the agent can't fix it directly

4. **Verify access** after any changes and update the README.yaml access matrix if needed

5. **Quick exit if nothing to do** — If all repos exist and agents have access, just confirm and move on

## Output Format

### setup_confirmation.md

**Structure**:

```markdown
# Repository Setup Confirmation: [Project Name]

## Actions Taken

### Repos Created

- [repo_url] on [platform] — [public/private] — created successfully
  [or "No repos needed to be created"]

### Access Fixed

- [repo_url] — [what was done to fix access]
  [or "All repos already accessible"]

### Access Verification

| Repo  | Agent Access | Status |
| ----- | ------------ | ------ |
| [url] | all verified | ok     |

## Remaining Issues

- [Any access problems that require human intervention, or "None"]

## README.yaml Updates

- [Any updates made to the profile's repo section, or "No updates needed"]
```

## Quality Criteria

- Every repo from the profile was checked for access
- New repos were created on the platform the user chose
- Access verification was performed after any changes
- Any issues requiring human intervention are clearly documented

## Context

This is the final step in project onboarding. After this, the project should be fully set up in the agent workspace: profile exists, PROJECTS.yaml is updated, all repos are accessible, and the recommended next steps are ready to be acted on by downstream workflows.
