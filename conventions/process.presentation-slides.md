<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->

# Convention: Presentation slides (process.presentation-slides)

This convention standardizes how Keystone notebooks store Slidev decks as
zk-managed Markdown documents. It makes presentation work searchable,
linkable, and reusable inside the same notebook that holds project hubs,
decision records, and supporting technical notes.

## Storage and identity

1. Slidev decks MUST be stored in `presentations/`.
2. Slidev decks MUST set `type: presentation` in YAML frontmatter.
3. Slidev decks MUST keep the notebook's timestamp-based filename and note ID
   scheme managed by `zk new`.
4. Slidev decks MUST remain single-file Markdown documents unless an embedded
   asset or theme requirement makes a companion file necessary.

## Frontmatter and tags

5. Slidev decks MUST include these frontmatter fields: `id`, `title`, `type`,
   `created`, `author`, `tags`, and `presentation_kind`.
6. Initiative-scoped decks MUST include `project: <slug>` in frontmatter.
7. Decks tied to one repo SHOULD include `repo/<owner>/<repo>` in `tags`.
8. Every deck MUST include `presentation/<kind>` and exactly one lifecycle tag:
   `status/active` or `status/archived`.
9. Decks MUST NOT introduce ad hoc tag namespaces for audience, theme, or
   delivery channel. Those details SHOULD live in the deck body or frontmatter.

## Authoring workflow

10. Humans SHOULD create decks with `zk new presentations/ --title "Title"`.
11. Agents MUST create decks non-interactively with `zk new presentations/ --no-input --print-path`.
12. New decks MUST start with valid Slidev YAML frontmatter followed by `---`
    slide separators.
13. Deck templates SHOULD include a title slide, an agenda or thesis slide, and
    a closing slide with next actions or references.
14. Speaker notes MAY include zk wikilinks such as `[[202603201430]]` or
    `[[202603201430 title-slug]]` to supporting notes, decisions, reports, and
    hubs.

## Assets and linking

15. Deck assets MUST use relative paths.
16. Existing notebook diagrams or repo-managed media SHOULD be reused instead of
    copied into parallel asset trees.
17. Initiative decks MUST link to the relevant hub note, and the hub SHOULD
    link back to the active deck.
18. If a deck supersedes an earlier deck for the same initiative or briefing,
    the new deck SHOULD link the previous deck explicitly in frontmatter or in a
    short provenance section.

## Lifecycle

19. Active decks MUST remain in `presentations/`.
20. Decks that are no longer active SHOULD move to `archive/` and replace
    `status/active` with `status/archived`.
21. Archived decks MAY retain `presentation/<kind>`, `project/<slug>`, and
    `repo/<owner>/<repo>` tags so they remain discoverable through `zk list`.

## Golden example

Canonical Slidev deck note:

```markdown
---
id: "202603241530"
title: "Keystone architecture briefing"
type: presentation
created: 2026-03-24T15:30:00-05:00
author: ncrmro
project: keystone
presentation_kind: architecture-briefing
tags:
  - presentation/architecture-briefing
  - project/keystone
  - repo/ncrmro/keystone
  - status/active
theme: default
---

# Keystone architecture briefing

## Objective

Explain how the module graph, deployment flow, and notebook conventions fit
together.

---

# Module graph

![Module overview](../assets/module-graph.svg)

<!--
Speaker notes:
- Link to the project hub: [[202603201430]]
- Link to the latest architecture decision: [[202603221015]]
-->

---

# Next actions

- Publish the updated briefing.
- Record follow-up decisions in the project hub.
```

## References

- `process.knowledge-management`
- `process.notes`
- `tool.zk`
- `tool.zk-notes`
