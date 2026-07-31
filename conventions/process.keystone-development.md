# Convention: Keystone Development Workflow (process.keystone-development)

Standards for efficiently developing and deploying changes across the keystone
platform repos: `ncrmro/keystone`, `ncrmro/ks-config`, and
`Unsupervisedcom/deepwork`. All repos live under `~/repos/{owner}/{repo}/`.

For the technical rules governing how `keystone.development = true` resolves paths
at the Nix module level, see `process.keystone-development-mode`.

## Repo roles

1. **`ncrmro/keystone`** is the upstream platform — reusable NixOS modules any user
   can adopt. Changes here affect all adopters. Put things here when they are
   broadly useful and not specific to ncrmro's setup.
2. **`ncrmro/ks-config`** is the consumer flake — per-host and per-user config
   that imports keystone modules. Put things here when they are specific to this
   fleet (host names, secrets, user preferences).
3. **`Unsupervisedcom/deepwork`** is the DeepWork framework and shared job library.
   Edit `library/jobs/` here for shared library jobs. Keystone-native jobs split
   across two directories: `ncrmro/keystone/.deepwork/jobs/` for workflows
   published to adopters via `pkgs.keystone.keystone-deepwork-jobs`, and
   `ncrmro/keystone/.deepwork/jobs-internal/` for keystone-development-only
   plumbing that is intentionally excluded from the published package.

## `ks` commands

4. `ks build` MUST be used to verify changes compile before deploying. It builds
   the full system for the current host using local keystone checkouts in dev mode.
5. `ks update --dev` deploys the current local unlocked keystone checkout via
   `ks switch`. When the system closure is unchanged it short-circuits to a
   home-manager-only activation. Use after editing terminal config, conventions,
   deepwork jobs, or any keystone module. Approval-gated per
   `process.privileged-approval`.
6. `ks update` runs the full update cycle: pull, lock, build, push, deploy. It MUST
   be treated as an approval-gated operation per `process.privileged-approval`.
7. `ks doctor` MUST be run when diagnosing fleet health or after a failed deploy.
8. `ks switch` (alias for the NixOS rebuild path) applies immediately and MUST be
   treated as an approval-gated operation per `process.privileged-approval`.

## Keystone dev workflow (in-repo iteration)

9. To test keystone module changes without committing to GitHub, use `keystone-dev`:
   ```bash
   keystone-dev --build   # verify changes compile (no deploy)
   keystone-dev           # nixos-rebuild switch with local keystone (deploys immediately)
   keystone-dev --boot    # nixos-rebuild boot (safe for dbus/init changes)
   ```
10. When `keystone.development = true`, `ks build` and `ks update --dev` automatically
    use the live `ncrmro/keystone` checkout — no `keystone-dev` wrapper needed.
    Approval policy still applies to `ks update --dev`.
11. When managing the local service stack (database, backend, frontend) during development, agents MUST follow `tool.process-compose-agent` for reliable orchestration.

## Change flow: keystone → ks-config

12. When a change ships to the `ncrmro/keystone` GitHub repo, ks-config must
    update its flake lock to pick it up:
    ```bash
    nix flake update keystone   # update keystone input only — NEVER bare nix flake update
    git add flake.lock && git commit -m "feat: update keystone (<description>)"
    ```
13. Always target a specific input — bare `nix flake update` MUST NOT be used. See
    `tool.nix` rule 4 for the authoritative prohibition and rationale.

## Conventions and AI instruction files

14. Convention files (`conventions/*.md`) and `archetypes.yaml` in `ncrmro/keystone`
    are the source of truth for agent instructions. Edit them here; the Nix build
    regenerates all downstream instruction files (`~/.claude/CLAUDE.md`, etc.).
    See `process.keystone-development-mode` rule 11 for the module-level specification.
15. After editing a convention or archetype, run `ks update --dev` to regenerate
    instruction files. In development mode, regenerated files appear as git diffs
    in the live repo checkout — commit them to persist the change. Because this is
    a deploy path, request approval before running it.

## Notes metadata

16. When keystone workflows create or update zk notes that reference a GitHub or
    Forgejo shared surface, those refs MUST use normalized frontmatter fields:
    `repo_ref`, `milestone_ref`, `issue_ref`, and `pr_ref`.
17. GitHub refs MUST use `gh:<owner>/<repo>#<number>`. Forgejo refs MUST use
    `fj:<owner>/<repo>#<number>`. Repo-only refs MUST use
    `gh:<owner>/<repo>` or `fj:<owner>/<repo>`.
18. Bare issue numbers, local path aliases, and custom tracker prefixes MUST NOT
    be used in note frontmatter when a shared-surface ref exists.

## DeepWork jobs

19. `DEEPWORK_ADDITIONAL_JOBS_FOLDERS` (set by keystone in dev mode — see
    `process.keystone-development-mode` rule 10) points at the live job roots:
    - `~/repos/Unsupervisedcom/deepwork/library/jobs/` — shared library jobs
    - `~/repos/ncrmro/keystone/.deepwork/jobs/` — published keystone-native jobs
    - `~/repos/ncrmro/keystone/.deepwork/jobs-internal/` — keystone-development-only jobs (appended in dev mode only; absent on adopter hosts)
20. Edits to job files in these directories take effect immediately without rebuild.
21. When fixing or extending a shared library job, edit it in
    `Unsupervisedcom/deepwork/library/jobs/`. For keystone-specific jobs, edit
    them in `ncrmro/keystone/.deepwork/jobs/` if any adopter-installed code
    (user workflows, OS-agent runtime, systemd services) invokes them, or in
    `ncrmro/keystone/.deepwork/jobs-internal/` if they are only reachable from
    a keystone contributor's local checkout.
22. A keystone-native job MUST live in `.deepwork/jobs/` if any adopter-installed
    code references it — including runtime-infrastructure jobs the OS agent
    invokes (e.g. `task_loop` is called from `modules/os/agents/scripts/task-loop.sh`).
    Jobs MUST live in `.deepwork/jobs-internal/` only when no adopter-installed
    code references them: contributor authoring tools (e.g. `agent_builder`) and
    in-progress stubs without a working `job.yml`.
