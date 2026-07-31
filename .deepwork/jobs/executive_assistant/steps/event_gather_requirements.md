# Gather Event Requirements

## Objective

Collect all necessary details about the event from the user to produce a structured requirements document that guides venue research and planning.

## Task

Ask structured questions to fully understand the event the user wants to plan. Use the AskUserQuestion tool to gather information interactively. Do not assume details — clarify ambiguities before proceeding.

### Process

1. **Review provided inputs**
   - Read the event description, date range, attendee count, and budget provided as inputs
   - Identify any gaps or ambiguities in the provided information

2. **Ask structured questions to fill gaps**
   - Event type and formality level (casual meetup, formal dinner, workshop, conference)
   - Location preferences (city, neighborhood, indoor/outdoor, accessibility needs)
   - Catering requirements (dietary restrictions, meal type, open bar vs. cash bar)
   - AV or special equipment needs
   - Accommodation needs for out-of-town guests
   - Any hard constraints (must-haves or deal-breakers)

3. **Confirm understanding**
   - Summarize all requirements back to the user
   - Ask if anything is missing or needs adjustment

4. **Write the requirements document**
   - Organize all gathered information into the output format below

## Output Format

### event_requirements.md

A structured requirements document capturing every parameter for the event.

**Structure**:

```markdown
# Event Requirements

## Overview

- **Event**: [event name/description]
- **Type**: [e.g., team offsite, dinner, workshop]
- **Date Range**: [preferred dates]
- **Attendee Count**: [number]
- **Budget**: [range]

## Venue Requirements

- **Location**: [city/area preference]
- **Setting**: [indoor/outdoor/hybrid]
- **Capacity**: [minimum needed]
- **Accessibility**: [requirements]

## Catering

- **Meal Type**: [breakfast/lunch/dinner/snacks]
- **Dietary Restrictions**: [list]
- **Beverage**: [open bar/cash bar/non-alcoholic only]

## Equipment & Logistics

- **AV Needs**: [projector, microphone, etc.]
- **Special Equipment**: [whiteboards, breakout rooms, etc.]
- **Accommodation**: [needed/not needed, details]

## Constraints

- **Must-Haves**: [non-negotiable requirements]
- **Deal-Breakers**: [things to avoid]
- **Other Notes**: [any additional context]
```

## Quality Criteria

- All user-provided inputs are captured in the document
- No unresolved ambiguities — gaps were clarified through questions
- Requirements are specific enough to guide venue and logistics research
- Budget and date range are clearly stated
- Format is clean and scannable

## Context

This is the foundation step for event planning. A thorough requirements document prevents wasted research on unsuitable options and ensures the final plan meets the user's actual needs.
