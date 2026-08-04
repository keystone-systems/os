Handle executive-assistant requests directly with the appropriate supporting references.

Use this skill for calendar management, inbox triage, event planning and
discovery, portfolio reviews, and daily task coordination.

## Supporting references

Before performing calendar, email, or contacts operations, read the relevant
convention file (co-located in this skill directory) for command syntax,
required fields, and safety rules:

- **Role behavior**: [executive-assistant.md](executive-assistant.md) -- triage urgency levels, tone, output format, and delegated-authority guardrails
- **Calendar (Calendula)**: [tool.calendula.md](tool.calendula.md) -- iCalendar editing, event creation, reminders, timezone handling
- **Email (Himalaya)**: [tool.himalaya.md](tool.himalaya.md) -- RFC 2822 message format, sending via stdin, reading with `-o json`, threading
- **Contacts (Cardamum)**: [tool.stalwart.md](tool.stalwart.md) sections 9-11 -- CardDAV addressbook operations and vCard format

## Common tasks

- **executive_assistant/manage_calendar** -- calendar triage and scheduling
- **executive_assistant/clean_inbox** -- inbox cleanup and reply drafting
- **executive_assistant/plan_event** -- end-to-end event planning
- **executive_assistant/discover_events** -- find events relevant to interests and projects
- **executive_assistant/task_loop** -- daily priority review, calendar, active work, and next actions
- **executive_assistant/portfolio_review** -- full portfolio health report across all active projects
- **executive_assistant/portfolio_review_one** -- status review for a single project

## Routing rules

- Mentions of calendar, scheduling, or appointments --> `executive_assistant/manage_calendar`
- Mentions of inbox, email cleanup, or reply drafting --> `executive_assistant/clean_inbox`
- Mentions of planning an event, venue, or logistics --> `executive_assistant/plan_event`
- Mentions of finding events, conferences, or meetups --> `executive_assistant/discover_events`
- Mentions of daily review, priorities, or task coordination --> `executive_assistant/task_loop`
- Mentions of portfolio review, project health, or status across projects --> `executive_assistant/portfolio_review`
- Mentions of reviewing a single project's status --> `executive_assistant/portfolio_review_one`
- If unclear, ask one targeted question before starting.
