# v1 release tracker

Snapshot of [ncrmro/keystone#418](https://github.com/ncrmro/keystone/issues/418).
The GitHub issue is authoritative; this copy keeps the checklist visible in the
repo without an API round-trip.

## Purpose

This issue is the human-readable tracker for v1 — Stabilization done-ness. The [v1 — Stabilization milestone](https://github.com/ncrmro/keystone/milestone/9) is the machine-readable view; this tracker exists so a single page conveys where v1 stands, what ships, what's deferred, and how completion is verified across hosts.

## Definition of done

v1's bar is **system stability + reliable click-to-update**. Anything outside that bar moves to v1.1.

v1 ships when all of the following are true:

- Walker `ks update` entry runs end-to-end reliably on every target host (#414) — this is the click-to-update flow.
- Hyprlock, theming, hibernate (laptop only), and suspend are verified on both `kind = "workstation"` and `kind = "laptop"` hosts. (Originally tracked as #412, closed 2026-04-27 not-planned: thin-client is not a distinct host kind; the underlying acceptance folds into the verification matrix below and into #344 / #359.)
- Walker surfaces are gated and the update surface uses `ks update` exclusively (#402).
- Laptop onboarding polish — first-boot stability blockers fixed (#359).
- v1.0.0 release candidate e2e tuning and validation complete (#344).
- Direct qcow2 image building for fast VM validation is available (#373).

## Blockers (child issues)

- [ ] #414 — fix(desktop): verify walker 'ks update' entry works end-to-end on v1
- [ ] #359 — docs(desktop): rc.2 laptop onboarding polish and common integrations
- [ ] #344 — test(e2e): v1.0.0 release candidate — tuning and validation

### Moved to v1.1

- #415 — feat(secrets): first-class 1Password integration (PR #427)
- #416 — docs(desktop): expose keystone docs link from walker help entry (PR #426)
- #417 — feat(desktop): walker 'add nix package' flow (PR #425)
- #441 — feat(ci): enable dependabot for nix flake inputs
- #481 — feat(desktop): make session-kill-on-hyprlock-failure explicit (follow-up to closed #421)

These are valuable but do not gate stability or the click-to-update flow.

### Closed not-planned

- #421 — fix(desktop): harden hyprlock against config-parse aborts. Premise inverted on security review: containment via lock.slice would suppress the security fail-safe (forced re-auth on lock-screen crash). Replaced by #481 which makes the existing kill-the-session behavior explicit instead of implicit via Hyprland's crash reporter.

### Completed

- [x] #402 — fix(desktop): make update surfaces use ks update only
- [x] #373 — feat(testing): direct qcow2 image building for fast VM validation without ISO
- [x] #390 — fix(desktop): gate Walker surfaces and repair setup, update, and wifi flows
- [x] #369 — fix(installer): canonical repo handoff must preserve reconciled hardware and boot-safe cryptroot fallback
- [x] #362 — fix(ks): default to ~/.keystone/repos/<owner>/keystone-config on installed systems
- [x] #361 — fix(installer): converge template installs to ~/.keystone/repos/<owner>/keystone-config
- [x] PR #305 — feat(v1): declarative project config, experimental flag, docs sync

## Verification matrix

| Host | hyprlock | theming | hibernate | suspend | walker ks-update |
|---|---|---|---|---|---|
| ncrmro workstation (`kind = "workstation"`) | ☐ | ☐ | n/a | ☐ | ☐ |
| ncrmro laptop (`kind = "laptop"`) | ☐ | ☐ | ☐ | ☐ | ☐ |

## Explicitly out of scope for v1

Agent-workflow issues are tracked on the [Post-v1 milestone](https://github.com/ncrmro/keystone/milestone/14) and intentionally excluded from v1 ship criteria. Examples: #408, #409, #410, #411, #413.

## How this issue gets closed

This tracker closes when every checkbox in the "Blockers" section is checked and the verification matrix is fully filled in on both the `kind = "workstation"` and `kind = "laptop"` hosts.

