# REQ-024: Agentic Calendar Integration

Wire CalDAV calendar events into the agent task loop so that recurring team
cadences (retrospections, status reports, reviews) are scheduled via real
calendar entries rather than static `SCHEDULES.yaml` patterns. Agents read
upcoming events from their CalDAV calendar, the scheduler creates events for
recurring workflows, and the human sees the full team operating rhythm on
their own CalDAV client without being invited to agent-only sessions.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## User Story

As a Keystone operator, I want my agent team's recurring workflows
(retrospections, status reports, strategic reviews) to appear as real
calendar events on a shared CalDAV server, so that I can see what my agents
are doing and when, without monitoring logs or checking SCHEDULES.yaml files.

As an AI agent, I want my scheduler to read CalDAV events and create tasks
from them, so that I execute work at the time the calendar says rather than
relying solely on static schedule patterns.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                     Agent Task Loop (task-loop.sh)                    │
│                                                                      │
│  Step 1: Prefetch Sources                                            │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │
│  │  email   │ │  github  │ │ forgejo  │ │ PROJECTS │ │ calendar │  │
│  │(himalaya)│ │(fetch-gh)│ │(fetch-fj)│ │ (.yaml)  │ │(calendula│  │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘  │
│       └─────────────┴────────────┴────────────┴────────────┘         │
│                              ▼                                       │
│                   SOURCES_JSON → ingest → prioritize → execute       │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│                     Scheduler (scheduler.sh)                          │
│                                                                      │
│  ┌──────────────┐          ┌──────────────────┐                      │
│  │SCHEDULES.yaml│──read──►│  Create tasks in  │                      │
│  └──────────────┘          │   TASKS.yaml      │                      │
│                            └──────────────────┘                      │
│  ┌──────────────┐          ┌──────────────────┐                      │
│  │ CalDAV events│──read──►│  Create tasks in  │  ◄── NEW (REQ-024)   │
│  │ (calendula)  │          │   TASKS.yaml      │                      │
│  └──────────────┘          └──────────────────┘                      │
│                                                                      │
│  ┌──────────────┐          ┌──────────────────┐                      │
│  │SCHEDULES.yaml│──sync──►│  Create CalDAV    │  ◄── NEW (REQ-024)   │
│  │  entries     │          │  events           │                      │
│  └──────────────┘          └──────────────────┘                      │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│                     CalDAV Server (Stalwart)                          │
│                                                                      │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐          │
│  │ human calendar │  │ agent-luce cal │  │ agent-drago cal│          │
│  │  (read/write)  │  │  (read/write)  │  │  (read/write)  │          │
│  └───────┬────────┘  └───────┬────────┘  └───────┬────────┘          │
│          │                   │                   │                    │
│          └───────── cross-calendar read ─────────┘                   │
│                  (human sees all agent calendars)                     │
└──────────────────────────────────────────────────────────────────────┘
```

## Affected Modules

- `modules/os/agents/scripts/scheduler.sh` — Add CalDAV event reading and calendar-to-task bridging
- `modules/os/agents/scripts/task-loop.sh` — Add CalDAV as a prefetch source
- `modules/os/agents/notes.nix` — Pass calendar config values to scheduler/task-loop scripts
- `modules/os/agents/types.nix` — Add `calendar.teamEvents` option for declaring team cadence events
- `modules/os/agents/home-manager.nix` — Ensure calendar + tasks modules are enabled for all agents
- `modules/terminal/calendar.nix` — No structural changes (already functional)
- `modules/server/services/mail.nix` — MAY need Stalwart ACL config for cross-calendar read access

## Requirements

### Team Calendar Enablement

**REQ-024.1** All agents with `mail.provision = true` MUST have
`keystone.terminal.calendar.enable = true` set by default. This is already
the case via `modules/os/agents/home-manager.nix:124`; this requirement
confirms the existing behavior as load-bearing.

**REQ-024.2** The agent's Calendula configuration MUST be functional
(credentials resolved, CalDAV endpoint reachable) before any calendar
integration features activate. The scheduler MUST gracefully skip calendar
operations if `calendula` is not in PATH or returns errors.

### Calendar-to-Task Bridge (Scheduler)

**REQ-024.3** The scheduler (`scheduler.sh`) MUST query the agent's CalDAV
calendar for events in the upcoming time window (default: next 24 hours)
using `calendula event list`.

**REQ-024.4** Calendar events with a recognized naming pattern MUST be
converted into tasks in `TASKS.yaml`. The naming pattern MUST use bracket
prefixes:

- `[Team] <name>` — team-wide cadence events (all agents participate)
- `[AgentName] <name>` — agent-specific events (only the named agent acts)

**REQ-024.5** Calendar-derived tasks MUST include a `source_ref` of the
form `calendar-<event-uid>-<date>` for deduplication against existing tasks,
following the same pattern as `schedule-<name>-<date>`.

**REQ-024.6** Calendar-derived tasks MUST include a `source: "calendar"`
field to distinguish them from schedule-derived and ingested tasks.

**REQ-024.7** If a calendar event includes a `workflow` field in its
description (e.g., `workflow: executive_assistant/manage_calendar`), the
created task MUST set the `workflow` field accordingly.

**REQ-024.8** Existing `SCHEDULES.yaml`-based scheduling MUST continue to
work alongside calendar-driven scheduling. The two sources MUST NOT
conflict — deduplication via `source_ref` prevents duplicates.

### Calendar Event Source in Task Loop

**REQ-024.9** The task loop prefetch step (`task-loop.sh`, Step 1) MUST
add CalDAV as a built-in source alongside email, GitHub, and Forgejo.

**REQ-024.10** The calendar prefetch MUST query upcoming events (next 24h)
and include them in `SOURCES_JSON` under `{"source": "calendar", "data": ...}`.

**REQ-024.11** The ingest step (haiku) MUST recognize calendar events and
MAY create or update tasks based on event content, attendees, and timing.

### Recurring Team Cadence Events

**REQ-024.12** The following recurring events MUST be defined as the
default team cadence, matching `process.agentic-team` convention rule 30:

| Event                                | Schedule              | Participants  | Workflow                |
| ------------------------------------ | --------------------- | ------------- | ----------------------- |
| `[Team] Weekly Retrospective`        | Friday 20:00          | All agents    | `project/status_report` |
| `[Team] Weekly Strategic Review`     | Friday 10:00          | Product agent | `project/status_report` |
| `[Team] Monthly Portfolio Review`    | 1st Monday 09:00      | Product agent | `project/status_report` |
| `[Team] Quarterly Direction Setting` | 1st Monday of Q 09:00 | Product agent | `project/status_report` |

**REQ-024.13** The Friday evening retrospective (`[Team] Weekly
Retrospective`) MUST be created as a CalDAV event that all agents are
attendees of. The human operator MUST NOT be an attendee but MUST be able
to see the event via cross-calendar read access.

**REQ-024.14** The retrospective task MUST produce a single top-level
GitHub issue documenting the retrospective output (what shipped, what's
blocked, what's next) for human review, following `process.agentic-team`
rule 15 (durable state on shared platforms).

**REQ-024.15** The product agent's weekly, monthly, and quarterly status
reports MUST be represented as CalDAV events on the product agent's
calendar, visible to all other agents and the human.

### SCHEDULES.yaml to Calendar Sync

**REQ-024.16** The scheduler SHOULD support an optional one-time migration
that reads `SCHEDULES.yaml` entries and creates corresponding CalDAV events
via `calendula event create`.

**REQ-024.17** After migration, the scheduler MUST be able to operate from
calendar events alone — `SCHEDULES.yaml` becomes OPTIONAL.

**REQ-024.18** The migration MUST be opt-in and MUST NOT modify or delete
`SCHEDULES.yaml`.

### Cross-Calendar Visibility

**REQ-024.19** Agents MUST be able to read each other's calendars via
CalDAV. Stalwart ACLs or sharing permissions MUST be configured to allow
cross-account read access between all agent accounts on the same server.

**REQ-024.20** The human operator MUST be able to read all agent calendars
from any standard CalDAV client (Apple Calendar, Thunderbird, DAVx5,
cfait, calendula).

**REQ-024.21** Agents MUST NOT modify the human operator's calendar events.
Write access MUST be limited to events with `[Team]` or `[AgentName]`
prefixes on the agent's own calendar.

### Configuration

**REQ-024.22** A new option `keystone.os.agents.<name>.calendar.teamEvents`
MAY be added to declare per-agent recurring calendar events:

```nix
keystone.os.agents.luce.calendar.teamEvents = [
  {
    name = "[Team] Weekly Retrospective";
    schedule = "weekly:friday:20:00";
    duration = "1h";
    workflow = "project/status_report";
    attendees = "all-agents"; # special value: all provisioned agents
  }
];
```

**REQ-024.23** If `calendar.teamEvents` is configured, the scheduler MUST
ensure these events exist on the agent's CalDAV calendar, creating them if
missing. This is idempotent — existing events MUST NOT be duplicated.

### Security

**REQ-024.24** Calendar event creation and modification MUST only occur
through the agent's own CalDAV credentials. Agents MUST NOT use the human
operator's credentials.

**REQ-024.25** Cross-calendar read access MUST be scoped to the
Stalwart server's internal accounts. External CalDAV endpoints MUST NOT
be queried without explicit configuration.

## Edge Cases

- **Calendula not available**: If `calendula` is not in PATH (e.g., mail
  not provisioned), all calendar operations silently skip. The scheduler
  falls back to `SCHEDULES.yaml` only.
- **CalDAV server unreachable**: Transient failures MUST NOT prevent the
  scheduler from processing `SCHEDULES.yaml`. Calendar operations SHOULD
  log a warning and continue.
- **Duplicate events**: If both `SCHEDULES.yaml` and a calendar event
  define the same recurring task, deduplication via `source_ref` prevents
  double-execution. The calendar event takes precedence if both are due.
- **Human blocks agent time**: If the human has a focus block visible on
  their calendar, agents MAY read this via cross-calendar access but MUST
  NOT modify their own scheduled work in response (future enhancement).
- **Time zones**: All CalDAV events MUST use the system's local timezone.
  `calendula` handles timezone conversion.

## Implementation Phases

### Phase 1: Calendar source in task loop + scheduler reads CalDAV

- Add `calendula event list` as a prefetch source in `task-loop.sh`
- Add CalDAV event reading to `scheduler.sh` with `source: "calendar"` tasks
- Deduplication via `calendar-<uid>-<date>` source_ref

### Phase 2: Team cadence events + retrospective

- Create the default team cadence events via calendula
- Wire Friday retrospective to produce a GitHub issue
- Wire product agent status reports to calendar events

### Phase 3: Cross-calendar visibility + SCHEDULES.yaml migration

- Configure Stalwart ACLs for cross-calendar read access
- Add optional `SCHEDULES.yaml` → CalDAV migration command
- Add `calendar.teamEvents` NixOS option

## Supersedes

This spec does not supersede any existing spec. It implements the remaining
high-priority user stories from GitHub issue #175 (Calendar Integration
milestone):

- "Agent scheduler reads calendar events"
- "Agents create calendar events for planned work"
- "Calendar-to-task bridge in the task loop"
- "Shared calendar visibility between agents and humans"

## References

- GitHub issue #175 — Calendar Integration: User Stories for Review
- GitHub issue #188 — Your Agent Team Now Shows Up on Your Calendar (press release)
- Milestone: Calendar Integration
- `modules/os/agents/scripts/scheduler.sh` — Current scheduler implementation
- `modules/os/agents/scripts/task-loop.sh` — Current task loop implementation
- `modules/terminal/calendar.nix` — Calendula CalDAV module
- `conventions/process.agentic-team.md` — Team operating cadences (rule 30)
- `docs/specs/REQ-021-cfait-tasks.md` — cfait packaging (completed)
- `docs/specs/REQ-022-cfait-tasks.md` — cfait terminal module (completed)
