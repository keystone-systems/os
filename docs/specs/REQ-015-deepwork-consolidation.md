# REQ-015: Shared DeepWork Convention and Job Consolidation

Consolidate DeepWork jobs from multiple repos into keystone as the single
source of truth. Establish a shared `.deepwork/jobs/` convention that makes
jobs available to all agents and users via home-manager.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Affected Modules

- `flake.nix` — new `keystone-deepwork-jobs` derivation
- `modules/terminal/deepwork.nix` — extend `DEEPWORK_ADDITIONAL_JOBS_FOLDERS`
- `.deepwork/jobs/` — new directory for consolidated jobs

## Requirements

### Shared DeepWork Folder Convention

**REQ-015.1** Keystone MUST have a `.deepwork/jobs/` directory at the
repository root for shared, keystone-native DeepWork job definitions.

**REQ-015.2** A `keystone-deepwork-jobs` Nix derivation MUST copy the
contents of `.deepwork/jobs/` into the Nix store, making them available
as a store path for home-manager integration.

**REQ-015.3** `modules/terminal/deepwork.nix` MUST append the
`keystone-deepwork-jobs` store path to `DEEPWORK_ADDITIONAL_JOBS_FOLDERS`
alongside the existing `deepwork-library-jobs` path. The env var is
colon-delimited.

**REQ-015.4** When keystone is consumed as a submodule (e.g.,
`nixos-config/.submodules/keystone`), the consumer repo's own `.deepwork/`
directory MUST extend (not replace) keystone's shared jobs. This works
automatically: project-level `--path .` discovers local jobs, keystone's
are via the env var.

### Job Consolidation

**REQ-015.5** DeepWork jobs from `ncrmro/agents` (Forgejo) MUST be
migrated into `keystone/.deepwork/jobs/` as the initial set (11 jobs).

**REQ-015.6** Jobs from other repos (obsidian vault, luce/drago) SHOULD
be migrated in a separate future PR for review.

**REQ-015.7** Migrated jobs MUST be validated against the authoritative
`job.schema.json` before merge.

**REQ-015.8** After successful migration, the source repos SHOULD have
their deepwork jobs removed to eliminate duplication.

**REQ-015.9** Migrated jobs MUST follow the existing naming convention:
`lowercase_snake_case` directory names starting with a letter.

### Availability

**REQ-015.10** Consolidated jobs MUST be available to all OS agents and
human users with `keystone.terminal.enable = true` — no per-agent
opt-in required.

**REQ-015.11** Collaborators on the keystone repo MUST be able to develop
and push new DeepWork jobs by adding them to `.deepwork/jobs/` and
submitting a PR. Changes propagate to all agents on the next
`ks update --lock`.

## Edge Cases

- If `.deepwork/jobs/` is empty, the derivation MUST produce an empty
  store path without error.
- If a job name conflicts between `deepwork-library-jobs` and
  `keystone-deepwork-jobs`, the deepwork server's discovery order
  determines precedence (first match wins).
