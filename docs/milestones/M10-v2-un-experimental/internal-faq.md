# Internal FAQ — v2 Un-experimental

> Contributor questions about graduating experimental features to stable.

## Which features graduate in v2?

Currently candidates (subject to per-feature review):

- `keystone.notes` and `keystone.notes.zk`
- `archetypes.yaml` (convention-based agent instructions)
- Convention regeneration pipeline

## What's the bar for "graduated"?

- Module is reachable without `keystone.experimental = true;`
- Documented in `docs/` (a top-level page, not just a research note)
- Has an end-to-end test covered by `nix flake check` or the host VM harness
- No `# TODO:` blockers in the module surface area

## What happens to `keystone.experimental`?

It stays as the gate for whatever the *next* set of in-flight features is.
v2 graduations remove the gate from the named modules; the flag itself remains
declared in `modules/shared/experimental.nix`.

## Are there breaking changes for v1 operators?

Operators who had `keystone.experimental = true;` get the v2 surface
unconditionally. Operators who had it `false` will see the graduated modules
become available — they remain opt-in via their own `keystone.*` toggles
(e.g. `keystone.notes.enable = true;`).

## How are the candidates tracked?

See [`tracker.md`](tracker.md) (a snapshot of the v2 milestone issues from
GitHub). When a v2 release tracker issue is opened, link it back into
the frontmatter `trackerIssue:` field in `README.md`.
