## Himalaya Email

## Sending Email

1. Email MUST be sent by piping a raw RFC 2822 message into `himalaya message send` via stdin: `printf "..." | himalaya message send`.
2. The `From` header MUST use the agent's name and email from `SOUL.md`.
3. Line endings MUST be CRLF (`\r\n`) — this is the RFC 2822 standard.
4. Headers and body MUST be separated by a blank line (`\r\n\r\n`).
5. A `Date:` header MUST be included using `$(date -R)`.
6. The message MUST NOT be passed as positional arguments — this causes the command to hang.
7. `himalaya message write`, `message reply`, and `template send` MUST NOT be used — they all hang without a TTY.
8. Subject and body MUST use plain ASCII characters only — no em dashes (`—`), curly quotes, or other non-ASCII. Non-ASCII causes the MIME type to default to `application/octet-stream` instead of `text/plain`.

```bash
# New message — substitute name/email from SOUL.md
printf "From: {name} <{email}>\r\nTo: recipient@example.com\r\nSubject: ...\r\nDate: $(date -R)\r\n\r\nBody text" | himalaya message send

# Reply — same pattern, just change Subject to Re: ...
printf "From: {name} <{email}>\r\nTo: sender@example.com\r\nSubject: Re: Original Subject\r\nDate: $(date -R)\r\n\r\nReply body text" | himalaya message send
```

## Reading Email

9. All read commands MUST use `-o json` for machine-readable output.
10. Preview mode (`-p`) SHOULD be used when reading messages to avoid marking them as seen.

```bash
# List envelopes (inbox)
himalaya envelope list -o json

# List envelopes with filter (e.g., unseen only)
himalaya envelope list -o json 'not flag seen'

# Read a message by envelope ID (preview mode)
himalaya message read -o json -p <ID>

# Read a message and mark as seen
himalaya message read -o json <ID>
```

**JSON shapes:**

- `envelope list` returns an array of objects with `id`, `flags`, `subject`, `from` (`name`, `addr`), `to`, `date`, `has_attachment`.
- `message read` returns a JSON string containing the raw RFC 2822 message (headers + body).

## Threading

11. Threading MAY be used via `himalaya envelope thread -i <id> -o json` and `himalaya message thread -p <id>`.
12. Cross-folder limitation: outbound messages (in "Sent Items") appear as phantom ID 0 nodes when threading from INBOX. Threading works best within a single folder.

## Nix-Managed Config

13. Himalaya config files in `/nix/store/` or symlinked from it MUST NOT be edited directly. Changes require updating the home-manager configuration.
