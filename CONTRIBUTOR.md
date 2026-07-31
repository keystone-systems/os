# Contributor guide

The goal of every keystone contribution is a clean `ks update --lock` — your
change lands in keystone `main`, the consumer flake relocks, and the full system
rebuilds and deploys with no manual intervention. Everything below serves that
goal.

## Happy path

```
1. Develop in a worktree branch or consumer flake (never dirty main)
2. Push branch → PR → agent review (at least one)
3. Squash-merge to main
4. ks update --lock   ← pulls main, relocks, builds, pushes, deploys
```

`ks update --lock` is the finish line. If it succeeds, the feature is live on
every host that runs it. If it fails, something upstream wasn't validated.

## Where to develop

| Change type | Develop in | Why |
|---|---|---|
| Keystone module/package | Worktree branch off main | Keeps main checkout clean for `ks build` |
| Per-host or per-user config | Consumer flake (`ncrmro/nixos-config`) | Not a platform change |
| Experimental / exploratory | Consumer flake with `keystone.experimental = true` | Safe to iterate without affecting other adopters |

The main keystone checkout (`~/.keystone/repos/ncrmro/keystone/`) MUST stay on
`main` with a clean working tree. `ks build` and `ks update --dev` operate on
this checkout — a dirty tree produces unpredictable builds.

### Worktree branches

Worktrees live at the global standard `~/repos/{owner}/worktrees/{repo}/{type}/{branch-tail}/`, preserving the slash from the branch name. Use Conventional Commit types (`docs`, `feat`, `fix`, `milestone`, `spec`, `spike`, `refactor`, `chore`, `test`, `ci`, `perf`, `build`); prefix the branch tail with `M{N}-` when the work is tied to a milestone.

```bash
git worktree add ~/repos/ncrmro/worktrees/keystone/feat/M1-fde-namespace -b feat/M1-fde-namespace
cd ~/repos/ncrmro/worktrees/keystone/feat/M1-fde-namespace
# develop, commit, push
git push origin feat/M1-fde-namespace
gh pr create
```

`~/repos/ncrmro/worktrees/keystone/` is the single canonical worktree root. Do not create worktrees under `~/repos/ncrmro/keystone/worktrees/`, `~/.keystone/repos/.../.claude/worktrees/`, or other dotfile roots — those locations are being phased out.

### Consumer flake changes

For changes specific to your fleet (host config, user preferences, secrets),
edit `ncrmro/nixos-config` directly. These don't need a keystone PR — just
commit and `ks update --lock`.

### Consumer flake resolution

`ks update` and `ks switch` resolve the consumer flake from a single
authoritative source: the NixOS option `keystone.systemFlake.path`, surfaced
at activation time as `/run/current-system/keystone-system-flake`.

- Default: `~/<adminUsername>/.keystone/repos/<adminUsername>/keystone-config`
- Override: `ks --flake <path> update` (explicit flag only — no CWD, env-var, or git-walk fallbacks)

When developing in a worktree, pass `--flake` explicitly:

```bash
ks --flake ~/repos/ncrmro/worktrees/keystone/<type>/<branch-tail> update --dev
```

No shell exports, no `KEYSTONE_SYSTEM_FLAKE` env var, no `NIXOS_CONFIG_DIR`.

## Review before merge

Worktree branches MUST be reviewed by at least one agent (via PR) before merging
to main. This catches regressions early, creates an audit trail, and ensures the
change validates against CI before `ks update --lock` consumes it.

## Pull request workflow

Agents shepherd PRs end-to-end per the `process.pr-shepherding` skill
(24 rules covering draft delivery, CI stabilization, Copilot iteration,
merge queue, post-merge verification). The operational loop has three
stages.

### Stage 1 — Draft

```bash
gh pr create --draft --title "type(scope): subject" --body "...Closes #N..."
gh pr checks --watch                 # watch PR-event CI to green
```

PR-event CI runs the cheap checks for fast feedback: `changes`, `eval`,
`ks`, `scripts`, `desktop`, `agents`, `nixfmt`, `shellcheck`,
`warm-cache`. The expensive `iso-build` is deferred to the merge queue
(Stage 3) and will appear `skipping` on PR-event runs — that is
expected.

Do NOT undraft while CI is failing or in progress.

### Issue and milestone linkage

Every PR MUST link to its originating issue and, when one exists for
the current work stream, be assigned to the milestone — milestones
are the unit of stakeholder-visible progress and an unassigned PR is
invisible on the project board.

```bash
# Issue linkage lives in the PR body. Use a closing keyword
# (Closes / Fixes / Resolves) ONLY if this PR fully resolves the issue;
# the forge auto-closes the issue on merge. For partial work or PRs
# under a tracking issue / epic, use a plain reference instead so the
# issue stays open after merge:
gh pr edit <PR> --body "...Closes #N..."         # full resolution
gh pr edit <PR> --body "...Part of #N..."        # partial / epic

# Milestone assignment is a separate field — no closing keyword in
# the body. Set it on both the PR and its originating issue:
gh pr edit <PR> --milestone "<milestone name>"
gh issue edit <ISSUE> --milestone "<milestone name>"
```

Cross-repo references MUST use `owner/repo#N`; bare `#N` is ambiguous.
If no milestone fits, check with the product agent before creating one
— milestones are a product artifact, not an engineering convenience.
Merging a PR does not close its milestone; the forge closes a milestone
only when every contained issue is closed.

### Stage 2 — Ready for review + Copilot

```bash
gh pr ready <PR>
gh pr edit <PR> --add-reviewer copilot-pull-request-reviewer
```

After Copilot files inline comments, address each on a follow-up commit
with the conventional subject `<type>(scope): address Copilot review on
PR #<PR>` (or `address post-merge Copilot review on PR #<PR>` for issues
caught after a fast merge). Reply on the PR thread for each comment,
then push and re-watch CI to green before re-requesting review.

### Stage 3 — Merge queue

```bash
gh pr merge <PR> --auto --squash --delete-branch

gh run list --event merge_group --limit 3       # find the queue run
gh run watch <RUN_ID>                           # watch it to completion
gh run view <RUN_ID> --log-failed               # if iso-build or another
                                                # merge_group check fails
# Fix, push — the merge queue automatically re-queues.

gh pr view <PR> --json state,mergedAt           # verify merge landed
```

`iso-build` only runs under the `merge_group` event, against the final
merged tree. Required gating checks for merge: all of the PR-event
checks plus `iso-build` under merge_group.

After the PR exits the queue, verify the default-branch CI is green on
the merge commit.

## After merge: `ks update --lock`

Once your PR is squash-merged to keystone `main`:

```bash
# From the consumer flake (nixos-config)
ks update --lock
```

This runs the full cycle: pull latest inputs, relock `flake.lock` (picking up
your keystone change), build, push lock, and deploy. Even when the local system
has `keystone.development = true`, `--lock` ensures the consumer flake lock
points to the merged commit on GitHub — not the local checkout.

## Verifying changes

Before merging, validate your branch passes CI locally:

```bash
nix flake check --no-build  # Fast probe: evaluate outputs without building
nix flake check             # Full: repo-native checks and CI parity
ks build                    # Home-manager profiles when host integration matters
```

Agents MUST run `ks build` when a change affects host integration, generated
assets, or behavior that isolated flake checks cannot validate.

For agenix user-home secrets, agents MUST ensure both sides of the contract are
updated together: the encrypted secret recipients must include every host where
that Home Manager user is installed, and the corresponding `age.secrets.<name>`
declaration must exist on each of those hosts.

### Validation commands

```bash
nix flake check --no-build  # Fast local probe
nix flake check             # CI parity
ks build                    # Build home-manager profiles for current host
ks build --lock             # Full system build + lock + push (requires sudo)
ks update --dev             # Deploy home-manager profiles only
ks update                   # Full: pull, lock, build, push, deploy
ks update --lock            # Pull, lock, build, push, deploy (human-only)
ks switch                   # Fast deploy current local state
ks doctor                   # Diagnose system health
```

### E2E testing

`bin/test-e2e` runs a VM test pipeline from the keystone repo.  It
generates a consumer-flake fixture from the default template, locks it
to the current keystone checkout, and delegates to the fixture's
`test-iso`. The fixture is cached at `/tmp/keystone-e2e-fixture/` and
refreshed automatically on each run.  See
[ISO and OS virtual machine testing](docs/testing/iso-os-virtual-machine.md)
for the full reference.

There are two paths; pick the one that matches your change:

**Direct qcow2 (2-10 min)** — NixOS modules, storage, boot chain,
anything below the installer:

```bash
bin/test-e2e --direct laptop --headless   # build + boot + SSH check, clean up
bin/test-e2e --direct --headless          # same; host defaults to 'laptop'
bin/test-e2e --direct laptop              # keep SPICE window open for debugging
```

**Full ISO + installer (20-30 min)** — installer TUI, `ks install`,
post-reboot desktop validation:

```bash
bin/test-e2e                  # Full e2e (build + boot + install + validate)
bin/test-e2e --build-only     # ISO build only (CI parity)
bin/test-e2e --clean          # Regenerate fixture before running
bin/test-e2e --no-build       # Reuse existing ISO
```

`bin/test-e2e` forwards user-supplied flags to `test-iso`, so anything
in `test-iso --help` (e.g. `--luks-passphrase`, `--port`, `--memory`)
generally works with `bin/test-e2e` too. It may also add wrapper
defaults such as `--dev` and a default mode (`--e2e --headless`) when
no mode flag is provided.

## AI instruction regeneration

AI instruction files (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`) are automatically
regenerated from `archetypes.yaml` and the `conventions/` directory during
`ks build`, `ks switch`, and `ks update --dev`. In development mode
(`keystone.development = true`), these files are symlinked from the repository,
and `ks switch` regenerates them as committable git diffs.

## Consumer-flake docs sync

User-facing docs that ship into every scaffolded `keystone-config` repo
(onboarding walkthrough, `mkSystemFlake` reference, ISO build + USB write,
agenix PAT setup, agent prompt library) are **canonically located** in
`templates/default/docs/keystone/`. The keystone repo's own
`docs/keystone/` directory is a flat set of in-repo symlinks pointing back
into that template path.

Why the symlink direction is template → root and not root → template:
`nix flake new -t github:ncrmro/keystone` copies the template's contents
verbatim into the user's destination. A symlink in the template like
`../../docs/foo.md` would, after scaffolding, resolve relative to the
*user's* tree — where root `docs/` doesn't exist. Putting the canonical
files in the template guarantees the scaffolded user repo gets real files,
and the keystone repo's `docs/keystone/*` view stays in sync via the
filesystem at zero cost.

To add a new shared doc:

1. Create the canonical file at
   `templates/default/docs/keystone/<name>.md`.
2. Add a matching symlink in the same commit:
   `ln -s ../../templates/default/docs/keystone/<name>.md docs/keystone/<name>.md`.
3. `git add` both. Git tracks symlinks natively (mode 120000) on every
   platform we ship to. GitHub follows the symlink when rendering the file
   in its web UI, so the root path displays the same markdown as the
   template path.

This sync is *not* regenerated by `ks build` / `ks switch` (the AI
instruction flow above is separate). The docs are hand-authored content,
not derived from `archetypes.yaml`.

## DeepWork job sync

Shared DeepWork jobs are discovered through `DEEPWORK_ADDITIONAL_JOBS_FOLDERS`.
In development mode, Keystone sets that env var to the live job roots:

- `~/.keystone/repos/Unsupervisedcom/deepwork/library/jobs` — shared library
- `~/.keystone/repos/ncrmro/keystone/.deepwork/jobs` — keystone-native, published
  to adopters via `pkgs.keystone.keystone-deepwork-jobs`
- `~/.keystone/repos/ncrmro/keystone/.deepwork/jobs-internal` — keystone-native,
  development-only (contributor authoring tools, in-progress stubs); appended
  in dev mode only and intentionally excluded from the published package, so
  it never reaches adopter hosts

Outside development mode, the first two roots resolve to packaged derivations
and the internal root is absent. Edits to job files in development mode take
effect immediately without rebuild.

When adding a new keystone-native job, decide its directory by whether any
adopter-installed code references it: workflows users invoke and runtime jobs
the OS agent calls (e.g. `task_loop`) live in `.deepwork/jobs/`;
contributor-only authoring tools and in-progress stubs live in
`.deepwork/jobs-internal/`.

DeepWork `keystone_system/issue` draft bodies are temporary artifacts — write
them under `.deepwork/tmp/`, not `.deepwork/jobs/`.

## llm-agents input strategy

AI agent packages (`claude-code`, `gemini-cli`, `codex`, `opencode`) come from
the `llm-agents` flake input pinned at nightly-latest. Consumer flakes choose:

- **Nightly-latest**: `llm-agents.follows = "keystone/llm-agents"` — relocking
  keystone bumps agent versions automatically.
- **Stable**: declare independent `llm-agents` input and override with
  `keystone.inputs.llm-agents.follows = "llm-agents"`.

See `modules/terminal/AGENTS.md` § "llm-agents input strategy" for examples.

## VM testing

For the full automated ISO and desktop testing workflow, see
[ISO and OS virtual machine testing](docs/testing/iso-os-virtual-machine.md).

`bin/virtual-machine` is the canonical VM tool (Q35 + EDK2 SecureBoot + TPM + QXL).
The template e2e test (`./bin/test-iso --dev --headless --e2e`) validates the full
new-user journey. Changes to NixOS modules do NOT require an ISO rebuild — only
`ks` binary or installer module changes do.

`--post-install-reboot` creates a `post-install` qcow2 snapshot; restore with
`--restore <vm> post-install` to skip reinstallation when debugging. Consolidation
tracked in #339.
