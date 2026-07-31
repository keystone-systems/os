---
title: External Mail Providers
description: Configuring Himalaya, Calendula, and Cardamum with external mail providers
---

# External Mail Providers

This guide covers configuring Himalaya (email), Calendula (calendars), and Cardamum (contacts) with external providers. For self-hosted Stalwart configuration, see [Personal Information Management](personal-info-management.md).

## Provider Overview

| Feature          | Gmail            | iCloud                    |
| ---------------- | ---------------- | ------------------------- |
| IMAP email       | ✓ (App Password) | ✓ (App-Specific Password) |
| SMTP email       | ✓ (App Password) | ✓ (App-Specific Password) |
| CalDAV calendars | ✗ (OAuth2 only)  | ✓ (App-Specific Password) |
| CardDAV contacts | ✗ (deprecated)   | ✓ (App-Specific Password) |

## Prerequisites

### Gmail: Generate an App Password

Gmail requires an App Password when two-step verification is enabled (which it must be for App Passwords to work):

1. Go to **Google Account** → **Security** → **2-Step Verification** → **App passwords**
2. Select **Mail** and your device, then click **Generate**
3. Store the 16-character password in rbw: `rbw add gmail-app-password`

### iCloud: Generate an App-Specific Password

1. Go to **appleid.apple.com** → **Sign-In and Security** → **App-Specific Passwords**
2. Click **+**, give it a name (e.g. "Keystone"), and copy the generated password
3. Store it in rbw: `rbw add icloud-app-password`

---

## Gmail Configuration

### Human User (nixos-config)

```nix
keystone.terminal.mail = {
  enable = true;
  accountName = "gmail";
  email = "nicholas@gmail.com";
  displayName = "Nicholas";
  login = "nicholas@gmail.com";  # Gmail uses full email as login
  host = "imap.gmail.com";
  passwordCommand = "rbw get gmail-app-password";
  smtp = {
    host = "smtp.gmail.com";
    port = 465;
    encryption = "tls";
  };
  folders = {
    sent = "[Gmail]/Sent Mail";
    drafts = "[Gmail]/Drafts";
    trash = "[Gmail]/Trash";
  };
};
```

### Agent (keystone.os.agents)

Agents using a Gmail account follow the same pattern. The `passwordCommand` must read from wherever the agent's credentials are stored (typically agenix):

```nix
keystone.os.agents.drago = {
  # ... other agent options ...
};

# In the agent's home-manager config (via home-manager.nix or users.nix extra config):
keystone.terminal.mail = {
  enable = true;
  accountName = "gmail";
  email = "agent@gmail.com";
  displayName = "Drago";
  login = "agent@gmail.com";
  host = "imap.gmail.com";
  passwordCommand = "cat /run/agenix/drago-gmail-app-password";
  smtp = {
    host = "smtp.gmail.com";
    port = 465;
    encryption = "tls";
  };
  folders = {
    sent = "[Gmail]/Sent Mail";
    drafts = "[Gmail]/Drafts";
    trash = "[Gmail]/Trash";
  };
};
```

### Gmail Folder Names

Gmail uses non-standard folder names under `[Gmail]/`:

| Himalaya alias | Gmail folder        |
| -------------- | ------------------- |
| `sent`         | `[Gmail]/Sent Mail` |
| `drafts`       | `[Gmail]/Drafts`    |
| `trash`        | `[Gmail]/Trash`     |
| (starred)      | `[Gmail]/Starred`   |
| (all mail)     | `[Gmail]/All Mail`  |

### Calendars and Contacts (Gmail)

Google Calendar's CalDAV endpoint requires OAuth2 — App Passwords do not grant calendar access. Google has also deprecated CardDAV for new applications.

**Workarounds:**

- **Calendars**: Export from calendar.google.com as `.ics` and import into Stalwart, or use a dedicated OAuth2 client
- **Contacts**: Export from contacts.google.com as vCard (`.vcf`), or use Google People API

---

## iCloud Configuration

### Human User (nixos-config)

```nix
keystone.terminal.mail = {
  enable = true;
  accountName = "icloud";
  email = "user@icloud.com";
  displayName = "User Name";
  login = "user@icloud.com";
  host = "imap.mail.me.com";
  passwordCommand = "rbw get icloud-app-password";
  smtp = {
    host = "smtp.mail.me.com";
    port = 587;
    encryption = "start-tls";
  };
  folders = {
    sent = "Sent Messages";
    drafts = "Drafts";
    trash = "Deleted Messages";
  };
};

keystone.terminal.calendar = {
  enable = true;
  accountName = "icloud";
  url = "https://caldav.icloud.com";
  login = "user@icloud.com";
  passwordCommand = "rbw get icloud-app-password";
};

keystone.terminal.contacts = {
  enable = true;
  accountName = "icloud";
  url = "https://contacts.icloud.com";
  login = "user@icloud.com";
  passwordCommand = "rbw get icloud-app-password";
};
```

### Agent (keystone.os.agents)

```nix
# In the agent's home-manager config:
keystone.terminal.mail = {
  enable = true;
  accountName = "icloud";
  email = "agent@icloud.com";
  displayName = "Agent";
  login = "agent@icloud.com";
  host = "imap.mail.me.com";
  passwordCommand = "cat /run/agenix/drago-icloud-app-password";
  smtp = {
    host = "smtp.mail.me.com";
    port = 587;
    encryption = "start-tls";
  };
  folders = {
    sent = "Sent Messages";
    drafts = "Drafts";
    trash = "Deleted Messages";
  };
};

keystone.terminal.calendar = {
  enable = true;
  accountName = "icloud";
  url = "https://caldav.icloud.com";
  login = "agent@icloud.com";
  passwordCommand = "cat /run/agenix/drago-icloud-app-password";
};

keystone.terminal.contacts = {
  enable = true;
  accountName = "icloud";
  url = "https://contacts.icloud.com";
  login = "agent@icloud.com";
  passwordCommand = "cat /run/agenix/drago-icloud-app-password";
};
```

### iCloud Folder Names

| Himalaya alias | iCloud folder      |
| -------------- | ------------------ |
| `sent`         | `Sent Messages`    |
| `drafts`       | `Drafts`           |
| `trash`        | `Deleted Messages` |

---

## Multi-Account Setup

Himalaya supports multiple accounts. The `default = true` field controls which account is used when no `-a <account>` flag is given:

```nix
# Only one mail module is supported at a time — for multiple accounts,
# write ~/.config/himalaya/config.toml directly via home.file:

home.file.".config/himalaya/config.toml".text = ''
  [accounts.work]
  email = "me@example.com"
  display-name = "Me"
  default = true
  # ... Stalwart IMAP/SMTP config

  [accounts.gmail]
  email = "me@gmail.com"
  display-name = "Me (Gmail)"
  # ... Gmail IMAP/SMTP config
'';
```

---

## Usage

After rebuilding with your new configuration:

```bash
# List inbox
himalaya envelope list

# List inbox for a specific account
himalaya -a gmail envelope list

# Read a message
himalaya message read <id>

# List calendars (iCloud)
calendula calendars list

# List contacts (iCloud)
cardamum addressbooks list
```

## Debugging

```bash
# Test IMAP connection
himalaya --debug account check-up

# Test CalDAV directly
curl -X PROPFIND -u "user@icloud.com:$(rbw get icloud-app-password)" \
  -H "Depth: 0" https://caldav.icloud.com

# Test CardDAV directly
curl -X PROPFIND -u "user@icloud.com:$(rbw get icloud-app-password)" \
  -H "Depth: 0" https://contacts.icloud.com
```
