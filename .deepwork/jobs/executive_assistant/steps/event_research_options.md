# Research Event Options

## Objective

Research venues, catering, and logistics options that match the event requirements, presenting each with enough detail for the user to make a decision.

## Task

Using the event requirements document, search for and evaluate options across venues, catering, and logistics providers. Present a curated shortlist with pros, cons, and cost estimates.

### Process

1. **Read the requirements document**
   - Parse all constraints: budget, location, capacity, dietary needs, equipment
   - Note hard constraints vs. nice-to-haves

2. **Research venue options**
   - Use WebSearch to find venues matching location and capacity requirements
   - Identify 3-5 venue options at different price points
   - For each venue, gather: name, address, capacity, estimated cost, amenities, availability

3. **Research catering options**
   - Search for caterers in the target area or venues with in-house catering
   - Match to dietary restrictions and meal type requirements
   - Get estimated per-person pricing

4. **Identify logistics needs**
   - Transportation (parking, shuttle services)
   - Accommodation options if needed
   - AV rental if not included with venue

5. **Compile options with evaluation**
   - Rate each option against the requirements
   - Note pros and cons for each
   - Flag any that exceed budget or miss key requirements

## Output Format

### event_options.md

A structured document presenting all researched options.

**Structure**:

```markdown
# Event Options Research

## Requirements Summary

[Brief recap of key requirements from the input document]

## Venue Options

### Option 1: [Venue Name]

- **Address**: [full address]
- **Capacity**: [number]
- **Estimated Cost**: [price range]
- **Amenities**: [what's included]
- **Pros**: [advantages]
- **Cons**: [disadvantages]
- **Source**: [URL or reference]

### Option 2: [Venue Name]

[same structure]

### Option 3: [Venue Name]

[same structure]

## Catering Options

### Option 1: [Caterer/Service Name]

- **Cuisine**: [type]
- **Per-Person Cost**: [estimate]
- **Dietary Accommodations**: [what they handle]
- **Notes**: [minimum headcount, lead time, etc.]

[Repeat for 2-3 options]

## Logistics

### Transportation

[Options and costs]

### Accommodation

[Options if needed]

### Equipment Rental

[AV or special equipment if not included with venue]

## Budget Summary

| Category  | Low Estimate | High Estimate |
| --------- | ------------ | ------------- |
| Venue     | $X           | $Y            |
| Catering  | $X           | $Y            |
| Logistics | $X           | $Y            |
| **Total** | **$X**       | **$Y**        |
```

## Quality Criteria

- All options fall within the stated budget and date range
- Each option includes enough detail (name, cost estimate, capacity) to make a decision
- At least 3 venue options are presented
- Pros and cons are specific, not generic
- Budget summary table shows total cost range
- Sources are provided for key claims

## Context

This research step converts abstract requirements into concrete, comparable options. The quality of this research directly impacts the event plan — incomplete or inaccurate options waste the user's decision-making time.
