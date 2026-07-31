---
slug: v2-un-experimental
trackerMilestone: 10
trackerIssue: null
flag: KEYSTONE_FLAG_MILESTONE_V2_UN_EXPERIMENTAL
dependsOnSpecs:
  - notes
  - conventions-grafana-mcp
  - projects
status: planned
---

# M10 — v2 Un-experimental

- Tracker: [ncrmro/keystone#milestone/10](https://github.com/ncrmro/keystone/milestone/10)

## Scope

Graduate experimental features to stable.

### Goals

- Stabilize notes/zk module and promote to stable surface
- Stabilize convention-based agent instructions
- Automate project hub note creation from `projects.yaml`
- Expand `projects.yaml` with richer metadata
- Walker / `pz` deeper integration with stable project config

### Candidates for graduation

- `keystone.notes` — git-backed notebook sync
- `keystone.notes.zk` — Zettelkasten initialization
- `archetypes.yaml` — agent instruction composition
- Convention regeneration pipeline

## Definition of done

Each candidate either ships as a stable module (no `keystone.experimental`
gate) or is documented as deferred to a later release. See
[`tracker.md`](tracker.md) for the live issue checklist (synced from GitHub).

## Related docs

- [`docs/experimental.md`](../../experimental.md) — current gate semantics
- [`docs/specs/`](../../specs/) — requirement specs
- [`docs/milestones/M9-v1-stabilization/`](../M9-v1-stabilization/) — what
  v1 explicitly left behind the `experimental` flag
