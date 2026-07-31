# Keystone releasing

Keystone distributes the way nixpkgs does: consumers track a **branch**, and
`ks update` follows that branch's head. There is no version tag to cut —
shipping a fix is just landing it on the right branch.

- `main` is the unstable integration branch. The `unstable` channel tracks it.
- `release/X.Y` branches are the stabilized release lines. The `stable` channel
  tracks the highest one.

## Branch model

- `main` is unstable and always open for ongoing development.
- `release/X.Y` is the stabilization branch for the `X.Y` release line. Fixes
  land on `main` first and are backported onto the line by pull request
  (cherry-pick), exactly like a nixpkgs `release-*` branch.
- Patch-level releases are commits *on* `release/X.Y`, not separate branches or
  tags — the line advances, consumers relock, done.

## Release cadence

1. A human creates `release/X.Y` from `main` once the line is ready to
   stabilize (`git push origin main:refs/heads/release/X.Y`, or via the GitHub
   UI). The `release/*` ruleset is PR-only after creation, so this first push
   is the one operator-owned step.
2. Stabilization fixes land on `main`, then backport to `release/X.Y` through
   pull requests with human approval.
3. Each push to `release/X.Y` runs the `Release` workflow: it builds and
   validates the tree and republishes the rolling starter ISO (see
   [Publishing model](#publishing-model)).
4. There is nothing to "tag" or "cut". A consumer on the `stable` channel picks
   up the line's new head on its next `ks update --lock`.

## Versioning

- The release line is identified by its branch name, `release/X.Y`. That branch
  head is the canonical stable state for the line.
- `main` represents the unstable state; the `unstable` channel exposes it as
  `main@<short-sha>`, and `stable` exposes the line head as
  `release/X.Y@<short-sha>`.
- Historical `v0.x` / `v1.0.0-rc.*` tags remain in the repo as inert history.
  Nothing in the update path reads them anymore.
- Package-local versions may remain package-specific, but they do not define
  the Keystone release line.

## Release notes

- The merged pull requests on a `release/X.Y` line are the change record for
  that line; GitHub's branch compare view (`main...release/X.Y`, or between two
  line heads) shows exactly what a relock will pick up.
- `CHANGELOG.md` remains available as the curated historical summary.

## Publishing model

- Consumers consume Keystone through the git repository and flake input — they
  pin `keystone.url = "github:ncrmro/keystone/release/X.Y"` (stable) or
  `.../keystone` i.e. `main` (unstable), and relocking follows the branch head.
- The **starter installer ISO** is the one build artifact published to GitHub.
  Each push to a `release/*` branch republishes a single rolling release tagged
  `latest-iso`, pointing at the newest stabilized line. This is bootstrap
  artifact hosting only — `ks update` never reads it.
- `main` pushes are validation-only; they build the ISO to keep the installer
  green but do not publish it.

## Update channels

Hosts running the Walker update menu (`ks menu update`, wired up via
`modules/desktop/home/services.nix`) track one of two branches. Selection is
declarative, through the `keystone.update.channel` option:

- `stable` (default) — the menu resolves the highest `release/<major>.<minor>`
  branch via the GitHub branches API and reads its tip commit. The `latest` row
  renders as `release/X.Y@<short-sha>`. If no `release/*` branch is published
  yet, the menu renders `Keystone OS unavailable`.
- `unstable` — the menu reads `GET /repos/OWNER/REPO/branches/main` and tracks
  the tip commit of `main`. The `latest` row renders as `main@<short-sha>`.

Both channels track a moving branch head; neither reads release tags.

To change a host's channel:

```nix
# In your consumer flake (nixos-config)
keystone.update.channel = "unstable";
```

Then run `ks update --dev` (deploy the current checkout) to pick up the
new value. The channel is embedded into the `ks-update.service` unit
environment and the shell's `home.sessionVariables` at activation time,
so interactive `ks menu update status` and background Walker dispatches
agree on which branch the host polls.

The stable channel remains the default and requires no per-host declaration.

### Fleet default and per-host overrides

Consumer flakes that use `keystone.lib.mkSystemFlake` can set the fleet-wide
channel once and override it per host:

```nix
keystone.lib.mkSystemFlake {
  defaults = {
    timeZone = "UTC";
    updateChannel = "unstable"; # fleet-wide default
  };
  hosts = {
    laptop = { kind = "laptop"; }; # inherits unstable
    server = {
      kind = "server";
      updateChannel = "stable"; # overrides the fleet default
    };
  };
}
```

Resolution order (highest precedence first):

1. `config.keystone.update.channel` set directly in a host's NixOS or
   home-manager modules.
2. The host entry's `updateChannel` attribute in `hosts`.
3. `defaults.updateChannel` in `mkSystemFlake`.
4. The option default (`"stable"`, declared in
   `modules/shared/update.nix`).

The fleet and per-host attributes apply through `lib.mkDefault`, so explicit
module-level declarations always win.

## Branch protection

Keystone uses GitHub repository rulesets for branch protection.

Configured `main` rules:

- Require pull requests before merging.
- Require the `flake-check` status check before merging.
- Block force pushes and branch deletion.

Configured `release/X.Y` rules:

- Require pull requests before merging stabilization changes.
- Require one approval before merging stabilization changes.
- Dismiss stale approvals when new commits land on the pull request.
- Require last-push approval so the actor behind the final push cannot self-approve.
- Require all review threads to be resolved before merging.
- Require the `flake-check` status check before merging, and require the branch to be up to date with the base branch before merge.
- Block force pushes.
- Block branch deletion.

Notes:

- The release rules are implemented as a wildcard GitHub ruleset targeting `refs/heads/release/*`.
- No bypass actors are configured for the `release/*` ruleset, so direct updates to existing release branches are blocked for every actor — stabilization lands by PR only.
- Creating a new `release/X.Y` branch is a human-owned operator step (the
  ruleset enforces PR-only updates *after* the branch exists, but cannot
  express "only Actions may create the branch"). Agents may propose changes to
  `release/*` through pull requests, but must not create release branches
  directly and must not merge stabilization changes without human approval.
- If Keystone starts using `hotfix/*` branches, add a matching GitHub ruleset for that namespace.

## Operating notes

- The `Release` workflow runs automatically on every push to `main` and
  `release/*`. It validates the tree and, for `release/*`, republishes the
  rolling `latest-iso` starter image. There is no manual dispatch and no
  version input.
- To open a new stable line, create `release/X.Y` from `main` (operator step),
  then land fixes via backport PRs.
- An urgent post-release fix is just another backport PR onto the existing
  `release/X.Y` line; the line head advances and consumers relock.
