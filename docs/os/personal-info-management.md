---
title: Personal Information Management
description: CLI tools for managing email, calendars, contacts, and timers via Pimalaya
---

# Personal Information Management

Keystone provides a suite of CLI tools from the [Pimalaya](https://pimalaya.org/) project for managing email, calendars, contacts, and timers. All tools share the same credential pattern — when mail is configured, calendar and contacts auto-default from it. No extra secrets needed.

## Tools Overview

| Tool                                               | Purpose   | Backend              | Module                       |
| -------------------------------------------------- | --------- | -------------------- | ---------------------------- |
| [Himalaya](https://github.com/pimalaya/himalaya)   | Email     | IMAP/SMTP (Stalwart) | `keystone.terminal.mail`     |
| [Calendula](https://github.com/pimalaya/calendula) | Calendars | CalDAV (Stalwart)    | `keystone.terminal.calendar` |
| [Cardamum](https://github.com/pimalaya/cardamum)   | Contacts  | CardDAV (Stalwart)   | `keystone.terminal.contacts` |
| [Comodoro](https://github.com/pimalaya/comodoro)   | Timers    | Local (Unix socket)  | `keystone.terminal.timer`    |

## Configuration

### Enable Everything

If mail is already configured, enabling the other tools requires one line each:

```nix
keystone.terminal.mail = {
  enable = true;
  accountName = "personal";
  email = "me@example.com";
  displayName = "My Name";
  login = "me";
  host = "mail.example.com";
  passwordCommand = "cat /run/agenix/mail-password";
};

keystone.terminal.calendar.enable = true;
keystone.terminal.contacts.enable = true;
keystone.terminal.timer.enable = true;
```

Calendar and contacts inherit `accountName`, `host`, `login`, and `passwordCommand` from the mail module. Override any option explicitly if needed.

### Generated Config Files

Each tool gets a TOML config in `~/.config/`:

| Tool      | Config Path                       |
| --------- | --------------------------------- |
| Himalaya  | `~/.config/himalaya/config.toml`  |
| Calendula | `~/.config/calendula/config.toml` |
| Cardamum  | `~/.config/cardamum/config.toml`  |
| Comodoro  | `~/.config/comodoro/config.toml`  |

These are managed by Home Manager — don't edit them manually.

## Email (Himalaya)

### List Inbox

```bash
himalaya envelope list
himalaya envelope list -f "Sent Items"
```

### Read a Message

```bash
himalaya message read <id>
```

### Send an Email

Always include a `Date:` header. Without it, emails show as 1970-01-01.

```bash
echo "From: me@example.com
To: recipient@example.com
Subject: Hello
Date: $(date -R)
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Message body here" | himalaya message send
```

### Folder Names

Stalwart uses different folder names than Himalaya defaults. The module auto-maps them:

| Himalaya Default | Stalwart Name |
| ---------------- | ------------- |
| Sent             | Sent Items    |
| Drafts           | Drafts        |
| Trash            | Deleted Items |

## Calendars (Calendula)

Calendula connects to Stalwart's CalDAV endpoint at `/dav/cal`.

### List Calendars

```bash
calendula calendars list
```

### List Events

```bash
calendula items list <calendar-id>
```

### Create or edit an event

Calendula `v0.1.0` edits raw iCalendar data through your `$EDITOR`. In practice,
that means event creation and updates are done by writing a `VEVENT` with the
fields you want to set.

Minimum useful fields:

- `SUMMARY` for the event title
- `DTSTART` for the start date and time
- `DTEND` for the end date and time, or a reasonable assumed duration
- `LOCATION` for the venue or address
- `DESCRIPTION` for contact details, notes, room info, or agenda

Common examples:

```ics
BEGIN:VEVENT
UID:intuitive-machines-presentation@example.com
DTSTAMP:20260331T120000Z
DTSTART;TZID=America/Chicago:20260417T090000
DTEND;TZID=America/Chicago:20260417T100000
SUMMARY:Intuitive Machines Company Presentation
LOCATION:13467 Columbia Shuttle Street\, Houston\, TX 77059
DESCRIPTION:Contact\nIntuitive Machines\n13467 Columbia Shuttle Street\, Houston\, TX 77059\n281.520.3703
END:VEVENT
```

Add alerts with `VALARM` blocks:

```ics
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
```

The example above sets reminders for one day before and two hours before the
event start time.

### Create an event

```bash
calendula items create <calendar-id>
```

This opens a new iCalendar draft in your `$EDITOR`.

### Update an Event

```bash
calendula items update <calendar-id> <item-id>
```

This opens the iCalendar (`.ics`) data in your `$EDITOR`.

### Practical event workflow

```bash
# 1. Find the calendar
calendula calendars list

# 2. Create a new event in that calendar
calendula items create default

# 3. List items to find the event ID later
calendula items list default

# 4. Update the event to change the title, date, time, location, or alerts
calendula items update default <item-id>
```

When editing the iCalendar body:

- Change `SUMMARY` to rename the event
- Change `DTSTART` and `DTEND` to move the date or time
- Set `LOCATION` to the venue or street address
- Put phone numbers, contact names, and notes in `DESCRIPTION`
- Add `VALARM` blocks for reminders

## Contacts (Cardamum)

Cardamum connects to Stalwart's CardDAV endpoint at `/dav/card`.

### List Address Books

```bash
cardamum addressbooks list
```

### List Contacts

```bash
cardamum cards list <addressbook-id>
```

### Update a Contact

```bash
cardamum card update <addressbook-id> <card-id>
```

This opens the vCard (`.vcf`) data in your `$EDITOR`.

## Timers (Comodoro)

Comodoro is a centralized Pomodoro timer with a client-server architecture. Multiple clients can control the same timer session.

### Default Cycles

The keystone module configures standard Pomodoro cycles:

| Cycle     | Duration |
| --------- | -------- |
| Work      | 25 min   |
| Rest      | 5 min    |
| Work      | 25 min   |
| Rest      | 5 min    |
| Work      | 25 min   |
| Long rest | 30 min   |

### Start the Server

```bash
comodoro server start
```

### Control the Timer

```bash
comodoro timer start    # Start the first cycle
comodoro timer get      # Show current timer state
comodoro timer pause    # Pause
comodoro timer resume   # Resume
```

### Notifications

The module enables desktop notifications by default:

- **Work started** — "Work started!"
- **Rest started** — "Take a break!"
- **Long rest started** — "Long break time!"

## OS Agents

Agents provisioned via `keystone.os.agents` automatically receive email, calendar, and contacts when mail is enabled. No extra configuration is needed — credentials are derived from the agent's mail account.

| Tool      | Agent Config                                                 |
| --------- | ------------------------------------------------------------ |
| Himalaya  | `keystone.terminal.mail.enable = true` (auto-configured)     |
| Calendula | `keystone.terminal.calendar.enable = true` (auto-configured) |
| Cardamum  | `keystone.terminal.contacts.enable = true` (auto-configured) |

Verify an agent's access:

```bash
agentctl drago exec himalaya envelope list
agentctl drago exec calendula calendars list
agentctl drago exec cardamum addressbooks list
```

## Stalwart DAV Endpoints

All CalDAV/CardDAV access goes through Stalwart's built-in DAV support:

| Protocol | Well-Known             | Direct URI  |
| -------- | ---------------------- | ----------- |
| CalDAV   | `/.well-known/caldav`  | `/dav/cal`  |
| CardDAV  | `/.well-known/carddav` | `/dav/card` |

The modules use direct URIs (`home-uri`) rather than discovery because Stalwart's well-known redirects trigger a nginx 400 on the follow-up PROPFIND.

## Debugging

### Authentication Failures

The `login` field is the Stalwart account **name** (e.g., `ncrmro`), not the email address. Using the email as login causes auth failures for all tools.

### Connection Issues

```bash
# Test CalDAV directly
curl -X PROPFIND -u "username:password" -H "Depth: 0" \
  https://mail.example.com/dav/cal

# Test CardDAV directly
curl -X PROPFIND -u "username:password" -H "Depth: 0" \
  https://mail.example.com/dav/card
```

### Debug Logging

All Pimalaya tools support `--debug` for verbose output:

```bash
himalaya --debug envelope list
calendula --debug calendars list
cardamum --debug addressbooks list
```
