Handle project-related requests directly.

Use `ks.notes` proactively after major project events when durable decisions,
risks, scope changes, or retrospective findings should be preserved in the
notebook in addition to shared project tracking surfaces.

## Common tasks

- **project/onboard** — onboard a new project: create hub note, scaffold structure, link repos
- **project/press_release** — draft a press release or announcement for a project
- **project/milestone** — parse press release or scope notes, refine user stories, create milestone, and link issue
- **project/milestone_engineering_handoff** — internal FAQ, document review, optional spikes, specs, and plan issue — full engineering gate before implementation
- **project/success** — run a project success review or retrospective
- **project/doctor** — audit a project's health: hub note completeness, repo conventions, and release post coverage on the website
- **project/wrap_up** — wind down engineering work: group uncommitted changes into logical commits, push, document in notes, and check in on open issues/PRs

## Routing rules

- Mentions of onboarding, starting, or registering a new project → `project/onboard`
- Mentions of press release, announcement, or launch copy → `project/press_release`
- Mentions of milestone, planning, user stories, or sprint scope → `project/milestone`
- Mentions of engineering handoff, specs, FAQ, or implementation gate → `project/milestone_engineering_handoff`
- Mentions of success, retro, or retrospective → `project/success`
- Mentions of health audit, hub note, repo conventions, or release post coverage → `project/doctor`
- Mentions of wrap up, wind down, committing changes, or finishing a session → `project/wrap_up`
- If unclear, ask one targeted question before starting.

## Notes integration

- After milestone setup, engineering handoff, or project success work, use `ks.notes` to record durable decisions, learnings, or risk changes.
- Notes complement issues, milestones, and project boards; they do not replace the shared system of record.
