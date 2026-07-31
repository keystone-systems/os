# Convention: Calendula calendar management (tool.calendula)

Standards for creating, updating, and inspecting calendar events with the
`calendula` CLI in Keystone environments.

## Command model

1. Agents MUST treat Calendula event editing as raw iCalendar (`.ics`) editing via the user's `$EDITOR`.
2. Agents MUST use `calendula calendars list` to discover available calendar IDs before creating or updating events.
3. Agents MUST use `calendula items create <calendar-id>` to create a new event.
4. Agents MUST use `calendula items list <calendar-id>` to discover event IDs for later updates.
5. Agents MUST use `calendula items update <calendar-id> <item-id>` to modify an existing event.

## Required event fields

1. Events MUST set `SUMMARY` to the user-facing event title.
2. Events MUST set `DTSTART` to the intended start date and time.
3. Events SHOULD set `DTEND`; when the user gives no end time, agents SHOULD choose the smallest reasonable duration, state the assumption, and proceed.
4. Events SHOULD set an explicit timezone with `TZID` when local time interpretation could be ambiguous.
5. Events SHOULD preserve a stable `UID` when updating an existing event instead of replacing it with a new logical event.

## Location and details

1. When the user provides a venue, address, or meeting place, agents SHOULD map the primary venue string into the `LOCATION` field.
2. Supplemental details such as phone numbers, contact names, room notes, gate codes, or agenda text SHOULD go in `DESCRIPTION`.
3. Street addresses in `LOCATION` MUST escape literal commas as required by iCalendar.
4. Multi-line descriptions MUST use escaped newline sequences (`\\n`) in the stored iCalendar text.

## Reminders

1. When the user asks for reminders, agents SHOULD add `VALARM` blocks with explicit trigger offsets.
2. `ACTION:DISPLAY` SHOULD be the default reminder type unless the target calendar backend is known to support a different alarm type end-to-end.
3. Reminder requests such as "1 day before" or "2 hours before" SHOULD be encoded with negative duration triggers such as `TRIGGER:-P1D` and `TRIGGER:-PT2H`.
4. Multiple requested reminders MAY be represented by multiple `VALARM` blocks on the same event.

## Assumptions and safety

1. If the user omits duration, timezone, or reminder details, agents SHOULD make the narrowest reasonable assumption and report it clearly after the change.
2. Agents MUST NOT silently change unrelated event fields while editing an existing event.
3. Agents SHOULD verify the target calendar account before making changes when multiple accounts are configured.

## Examples

```bash
# List calendars
calendula calendars list

# Create a new item in the default calendar
calendula items create default

# List items to find an event ID
calendula items list default

# Update an existing event
calendula items update default <item-id>
```

```ics
BEGIN:VEVENT
UID:intuitive-machines-presentation@example.com
DTSTAMP:20260331T120000Z
DTSTART;TZID=America/Chicago:20260417T090000
DTEND;TZID=America/Chicago:20260417T100000
SUMMARY:Intuitive Machines Company Presentation
LOCATION:13467 Columbia Shuttle Street\, Houston\, TX 77059
DESCRIPTION:Contact\nIntuitive Machines\n13467 Columbia Shuttle Street\, Houston\, TX 77059\n281.520.3703
BEGIN:VALARM
ACTION:DISPLAY
DESCRIPTION:Intuitive Machines Company Presentation
TRIGGER:-P1D
END:VALARM
BEGIN:VALARM
ACTION:DISPLAY
DESCRIPTION:Intuitive Machines Company Presentation
TRIGGER:-PT2H
END:VALARM
END:VEVENT
```
