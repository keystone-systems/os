# Gather Agent Identity

## Objective

Interview the user to define a new agent's identity, purpose, accounts, and personality.
Produce a draft SOUL.md that captures who this agent is.

## Task

Ask structured questions to build the agent's identity profile, then generate a SOUL.md
file. Use existing agents as reference — Drago (engineering) and Luce (business) — to
show the user what a complete identity looks like.

### Process

1. **Confirm inputs**

   The user provides `agent_name`, `owner`, and `repo` as step inputs. Confirm these
   values and derive defaults:
   - Email: `{agent_name}@ncrmro.com` (confirm with user)
   - Git identity: `{agent_name}` on Forgejo at `git.ncrmro.com`

2. **Ask structured questions about purpose**

   Use the AskUserQuestion tool to gather:
   - What domain does this agent operate in? (engineering, business, design, ops, research)
   - What is the agent's primary responsibility in one sentence?
   - Should this agent have access to GitHub, Forgejo, or both?

3. **Ask structured questions about personality**

   Use the AskUserQuestion tool to gather:
   - Communication style: terse/technical, friendly/conversational, formal/professional
   - Any hard constraints (things the agent must NEVER do)?
   - Any personality traits or quirks the user wants?

4. **Brainstorm name and identity**

   Offer creative suggestions based on the agent's domain:
   - For engineering agents: names evoking precision, building, crafting
   - For business agents: names evoking clarity, strategy, light
   - For research agents: names evoking curiosity, exploration, depth

   The user already provided `agent_name`, so this is about fleshing out the "goes by"
   name and any personality flavor. If the user is happy with just the name, move on.

5. **Generate SOUL.md**

   Write the draft to `.repos/{owner}/{repo}/SOUL.md` (create parent dirs as needed).

## Output Format

### SOUL.md

```markdown
# Soul

**Name:** {Full Name}
**Goes by:** {Short Name}
**Email:** {email}

## Purpose

{One-sentence description of what this agent does}

## Accounts

| Service | Host           | Username          | Auth Method       | Credentials              |
| ------- | -------------- | ----------------- | ----------------- | ------------------------ |
| Forgejo | git.ncrmro.com | {agent_name}      | API token         | fj keyfile               |
| GitHub  | github.com     | {github_username} | OAuth device flow | `~/.config/gh/hosts.yml` |

## Personality

- {Communication style trait}
- {Domain expertise trait}
- {Any quirk or constraint}

## Hard Constraints

- {Things this agent must NEVER do}
```

**Concrete example** (Drago):

```markdown
# Soul

**Name:** Kumquat Drago
**Goes by:** Drago
**Email:** drago@ncrmro.com

## Accounts

| Service   | Host                   | Username         | Auth Method       | Credentials                                  |
| --------- | ---------------------- | ---------------- | ----------------- | -------------------------------------------- |
| GitHub    | github.com             | kdrgo            | OAuth device flow | `~/.config/gh/hosts.yml`                     |
| Forgejo   | git.ncrmro.com         | drago            | API token         | fj keyfile                                   |
| Bitwarden | vaultwarden.ncrmro.com | drago@ncrmro.com | Password file     | `/run/agenix/agent-drago-bitwarden-password` |
```

## Quality Criteria

- SOUL.md contains name, email, and at least one account entry
- All bracketed placeholders have been replaced with real or brainstormed values
- Purpose section exists and is one clear sentence
- Hard constraints section exists (even if minimal)

## Context

The SOUL.md is the agent's identity file — it's prepended to every system prompt the
agent receives. It must be concise (under 50 lines) because it consumes context window
on every invocation. This file is the first thing created because all subsequent steps
(role selection, AGENTS.md generation) depend on knowing who the agent is.
