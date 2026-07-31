# Gather Interests

## Objective

Build a structured profile of the human's interests, current projects, and event preferences to guide event discovery.

## Task

Combine the user-provided interest areas with context from the project environment to create a comprehensive interest profile. Ask structured questions to fill gaps.

### Process

1. **Review provided inputs**
   - Read interest_areas, location, and date_range inputs
   - Parse interest areas into distinct topics

2. **Enrich from project context**
   - Check PROJECTS.yaml or project files for active projects and their domains
   - Review SOUL.md and TEAM.md for role context and professional focus areas
   - Identify technologies, industries, and communities relevant to current work

3. **Ask structured questions to refine**
   - Use the AskUserQuestion tool to clarify preferences:
     - Event types: conferences, meetups, workshops, hackathons, networking dinners?
     - Size preference: intimate (< 50) vs. large-scale (500+)?
     - Willingness to travel vs. local-only vs. remote?
     - Budget for event attendance (free only, or paid events OK)?
     - Networking goals: hiring, partnerships, learning, speaking?

4. **Build the interest profile**
   - Organize interests by category
   - Weight by relevance to current projects and stated priorities

## Output Format

### interest_profile.md

A structured profile to guide event search.

**Structure**:

```markdown
# Interest Profile

- **Location**: [base location]
- **Travel Radius**: [local only / regional / national / international]
- **Date Range**: [search period]
- **Budget**: [free only / up to $X / no limit]

## Interest Areas

### 1. [Interest Area] (Priority: high/medium/low)

- **Keywords**: [search terms]
- **Related Projects**: [current projects in this area]
- **Event Types**: [conferences, meetups, workshops, etc.]

### 2. [Interest Area] (Priority: high/medium/low)

[same structure]

## Event Preferences

- **Preferred Size**: [range]
- **Format**: [in-person / remote / hybrid]
- **Networking Goals**: [what the user wants from events]
- **Speaking Interest**: [yes/no — open to CFPs?]

## Active Projects Context

[Brief summary of current projects that might influence event relevance]
```

## Quality Criteria

- All user-provided interest areas are captured
- Interests are enriched with project context, not just echoed back
- Priority levels reflect the user's current focus
- Preferences are specific enough to filter events effectively
- The profile is useful as a search guide, not just a list

## Context

This profile drives the event search. A well-constructed profile with weighted interests and clear preferences produces better, more relevant event recommendations.
