## Bitwarden CLI

## How It Works

Keystone provisions each agent's Bitwarden master password as an agenix secret at `/run/agenix/agent-{name}-bitwarden-password` (mode 0400, owned by the agent user). A custom pinentry script (`rbw-pinentry-agenix`) reads this file automatically, so `rbw` and `bw` operate without interactive prompts.

## Authentication

1. The Bitwarden CLI MUST be configured to use the internal Vaultwarden server at `https://vaultwarden.ncrmro.com`. Account details are in `SOUL.md`.
2. The password file path is `/run/agenix/agent-{name}-bitwarden-password` — substitute the agent's name (e.g., `agent-drago`, `agent-luce`).
3. Non-interactive login MUST use the password file: `bw login {email} --passwordfile /run/agenix/agent-{name}-bitwarden-password`.
4. The vault MUST be unlocked before use: `export BW_SESSION=$(bw unlock --passwordfile /run/agenix/agent-{name}-bitwarden-password --raw)`.

## Usage

5. Passwords SHOULD be retrieved with: `bw get password <item-name-or-id>`.
6. Full item details MAY be retrieved with: `bw get item <item-name-or-id>`.
7. API tokens and other fields MAY be retrieved with: `bw get notes <item-name-or-id>` or by parsing JSON from `bw get item`.
8. Credential paths (email, password file) MUST come from `SOUL.md` — never hardcode them.

## Troubleshooting

9. If `bw` reports "not logged in", run the login command from step 3 first.
10. If unlock fails, verify the agenix secret exists: `test -r /run/agenix/agent-{name}-bitwarden-password`.
11. `BW_SESSION` MUST be exported in the same shell session where `bw get` is called — it does not persist across shells.
