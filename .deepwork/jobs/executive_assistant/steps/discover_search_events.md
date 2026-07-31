# Search Events

## Objective

Search for events matching the interest profile, producing a comprehensive list of candidates with full details.

## Task

Use web search to find events across multiple platforms and sources. Cast a wide net — filtering happens in the next step.

### Process

1. **Read the interest profile**
   - Parse interest_profile.md for all interest areas, keywords, location, and date range
   - Note priority levels to guide search effort allocation

2. **Search across multiple sources**
   - Use WebSearch to query event platforms:
     - Eventbrite, Meetup, Luma for general events
     - Conference-specific sites for tech events
     - Industry-specific event calendars
     - Local tech community calendars
   - Search for each high-priority interest area first, then medium and low
   - Use location and date filters where possible

3. **Gather event details**
   - For each event found, capture:
     - Event name
     - Date and time
     - Location (physical address or "remote")
     - URL (registration or info page)
     - Brief description
     - Cost (free / ticket price)
     - Expected attendance size (if available)
     - Organizer

4. **Deduplicate**
   - Remove duplicate listings from different sources
   - Merge information from multiple sources for the same event

## Output Format

### event_candidates.md

Raw list of all discovered events.

**Structure**:

```markdown
# Event Candidates

- **Search Date**: [timestamp]
- **Interest Profile**: [summary of what was searched for]
- **Events Found**: [total count]

## Events

### 1. [Event Name]

- **Date**: [date and time]
- **Location**: [venue, city, state OR "Remote"]
- **URL**: [registration/info link]
- **Cost**: [free / $X]
- **Size**: [expected attendance if known]
- **Organizer**: [who's hosting]
- **Description**: [2-3 sentence summary]
- **Matched Interest**: [which interest area this relates to]

### 2. [Event Name]

[same structure]

[Continue for all discovered events]

## Search Coverage

- **Sources Searched**: [list of platforms/sites checked]
- **Interest Areas Covered**: [which interests had results, which didn't]
- **Gaps**: [any interest areas with no events found]
```

**Example**:

```markdown
### 1. NixCon 2026

- **Date**: 2026-05-15 to 2026-05-17
- **Location**: Berlin, Germany
- **URL**: https://nixcon.org/2026
- **Cost**: $200 early bird
- **Size**: ~500 attendees
- **Organizer**: NixOS Foundation
- **Description**: Annual conference for the Nix ecosystem. Talks on NixOS, Nix packages, and infrastructure management. Includes workshops and community sprints.
- **Matched Interest**: Nix/NixOS
```

## Quality Criteria

- All listed events are plausibly relevant to at least one stated interest area
- Each event includes name, date, location, URL, and brief description
- Multiple sources were searched (not just one platform)
- High-priority interest areas have more search coverage
- No obviously duplicate entries

## Context

This is the raw discovery step. Quantity and coverage matter here — the ranking step will filter and prioritize. It's better to include a borderline-relevant event than to miss a great one.
