---
slug: v1-stabilization
trackerMilestone: 9
trackerIssue: 418
flag: KEYSTONE_FLAG_MILESTONE_V1_STABILIZATION
dependsOnSpecs:
  - keystone-os
  - nixos-installer
  - os-agents
  - terminal
  - keystone-desktop
  - projects
  - ks-cli
status: in_progress
---

# M9 — v1 Stabilization

- Tracker: [ncrmro/keystone#milestone/9](https://github.com/ncrmro/keystone/milestone/9)
- Release tracker issue: [#418](https://github.com/ncrmro/keystone/issues/418)

## Scope

Stabilize the keystone platform for v1 release.

### Goals

- Declarative project registry (`projects.yaml`) as the stable project source
- Mark unstable features as experimental (notes/zk, etc.)
- Clean module boundaries — projects decoupled from notes
- All stable features documented and tested

### Stable v1 surface

- OS modules (storage, secure boot, TPM, users, agents)
- Terminal modules (shell, editor, AI, git, projects)
- Desktop modules (Hyprland, walker, project menus)
- Server modules (services, DNS, ACME, nginx)
- Declarative project config (`projects.yaml` + JSON schema)
- `ks` CLI (build, update, switch, doctor)
- `pz` CLI (project sessions, menus, host management)

### Experimental (not part of v1 stable surface)

- Notes/zk module (`keystone.notes`)
- Convention-based agent instructions (`archetypes.yaml`)

## Definition of done

v1's bar is **system stability + reliable click-to-update**. Anything outside
that bar moves to v1.1. See [`tracker.md`](tracker.md) for the live blocker
checklist and verification matrix.

## Related docs

- [`docs/releasing.md`](../../releasing.md) — branch model, update channels, release workflow
- [`docs/experimental.md`](../../experimental.md) — `keystone.experimental` gate
- [`docs/specs/`](../../specs/) — requirement specs
