# Gather Presentation Requirements

## Objective

Collect everything needed to plan a presentation end-to-end: topic, audience, key
messages, duration, tone, and Immich media preferences. This drives all downstream
steps.

## Task

You were invoked with `topic`, `audience`, and `duration_minutes` as inputs. Use
these as a starting point, then ask structured questions to fill in the gaps before
writing the requirements document.

### Process

1. **Confirm core inputs** — if any of the three inputs are missing, vague, or
   contradictory, ask structured questions using the AskUserQuestion tool before
   continuing.

2. **Ask structured questions** to gather:
   - The 3–5 key messages the audience should remember
   - The desired tone (formal/professional, casual/conversational, technical)
   - Whether there is an opening hook (story, statistic, demo, bold claim)
   - Whether to search Immich for relevant photos, screenshots, or videos, and if
     so, what search parameters to use (topic keywords, locations, people, date range,
     screenshot subject matter)

3. **Calculate target slide count** using: `target_slides = max(5, round(duration_minutes / 1.5))`.

4. **Write presentation_requirements.md** — see Output Format below.

## Output Format

### presentation_requirements.md

A structured requirements document covering all inputs needed by downstream steps.

**Structure**:

```markdown
# Presentation requirements

## Core details
- **Topic**: Keystone infrastructure overview
- **Audience**: Engineering new-hires
- **Duration**: 20 minutes → target ~13 slides
- **Tone**: Technical, conversational

## Key messages
1. Keystone is a fully declarative NixOS platform — you never configure a server by hand.
2. Secrets are encrypted at rest with agenix and unlocked at boot via TPM/hardware key.
3. The dev workflow is: edit → `ks build` to verify → `ks update` to deploy.

## Opening hook
"Show a diff where one line of Nix adds a full service to the fleet — no SSH, no
Ansible, no manual steps."

## Media preferences
- **Search Immich**: yes
- **Search parameters**: screenshots of the terminal, photos of the server rack,
  OCR search for "ks build" in screenshots, date range 2025-2026
```

## Quality Criteria

- At least 3 key messages are captured and specific (not "explain what Keystone is")
- Media preferences are confirmed: `immich_search` is explicitly `yes` or `no`; if
  yes, search parameters are concrete enough to drive the presentation_search_media step
- Target slide count is calculated and present in the document
- Tone is stated as one of: formal/professional, casual/conversational, or technical

## Context

This is the first step of the `presentation` workflow. Its output feeds directly into
`presentation_search_media` (to scope the Immich query) and `presentation_outline` (to structure the
narrative). Getting the key messages right here prevents back-and-forth in later steps.
