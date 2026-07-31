# Milestones

Product deliverables for Keystone. Each milestone is a directory under this
folder that mirrors a GitHub Milestone on
[ncrmro/keystone](https://github.com/ncrmro/keystone/milestones).

A milestone is a product surface: press release, internal FAQ, designs, and
the GitHub tracker checklist. Specs (engineering requirements) live next door
at [`docs/specs/`](../specs/) and are linked into a milestone by adding their
slug to the `dependsOnSpecs:` field of `README.md`'s YAML frontmatter. Specs
never reference milestones back — the reverse-lookup is computed by scanning
each milestone's frontmatter.

## Active

| Local | Tracker | Title | Status |
|---|---|---|---|
| [M9 — v1 Stabilization](M9-v1-stabilization/) | [milestone/9](https://github.com/ncrmro/keystone/milestone/9) | v1 — Stabilization | in_progress |
| [M10 — v2 Un-experimental](M10-v2-un-experimental/) | [milestone/10](https://github.com/ncrmro/keystone/milestone/10) | v2 — Un-experimental | planned |

## Per-milestone layout

```
docs/milestones/M<N>-<slug>/
├── README.md          YAML frontmatter + scope/goals; the milestone's home page
├── press-release.md   working-backwards announcement
├── internal-faq.md    leadership / investor FAQ
├── designs.md         mockups or design pointers (stub OK)
└── tracker.md         snapshot of the GitHub release tracker issue
```

### README.md frontmatter

The machine-readable header lives in `README.md` itself, as YAML frontmatter:

```yaml
---
slug: v1-stabilization                       # kebab-case; matches dir suffix
trackerMilestone: 9                          # GitHub milestone number; matches M<N>
trackerIssue: 418                            # the "release tracker" issue, or null
flag: KEYSTONE_FLAG_MILESTONE_V1_STABILIZATION
dependsOnSpecs: []                           # list of spec slugs in docs/specs/
status: in_progress                          # planned | in_progress | shipped | cancelled
---
```

Each `dependsOnSpecs:` entry is the slug portion of a `docs/specs/REQ-NNN-<slug>.md`
file (the `<slug>` portion, not the full filename).
