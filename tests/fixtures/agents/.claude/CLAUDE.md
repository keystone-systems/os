# Available skills

Each skill loads domain-specific conventions and DeepWork workflows on demand.

- **/ks.system** — Keystone system — may start keystone_system/issue or keystone_system/doctor
- **/ks.assistant** — Personal assistant — may start personal_assistant/reservation, personal_assistant/birthday, personal_assistant/calendar_prioritize, or personal_assistant/memory_search
- **/ks.projects** — Project workflows — may start project/onboard, project/press_release, or project/success
- **/ks.engineer** — Engineering — implementation, code review, architecture, and CI
- **/ks.product** — Product — planning, milestones, stakeholder communication
- **/ks.project-manager** — Project management — task decomposition, tracking, and boards

# Shared-surface tracking

- For issue-backed work, post `Work Started` and `Work Update` comments on the source issue.
- Treat issues, pull requests, milestones, and boards as the canonical public record.
- Use notes for durable rationale and memory, not to replace shared-surface tracking.

# Commit format

- Use Conventional Commits: `type(scope): subject`.
- Valid types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, `perf`, `build`.
- Each commit SHOULD represent one logical change.