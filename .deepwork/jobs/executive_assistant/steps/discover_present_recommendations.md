# Present Recommendations

## Objective

Create a polished, decision-ready recommendations document with the top events, including everything the user needs to decide whether to attend.

## Task

Transform the ranked event list into an executive-ready recommendations document. Focus on actionability — the user should be able to register directly from this document.

### Process

1. **Read ranked events**
   - Parse ranked_events.md for the top-ranked events
   - Select the top 5-8 events for the final recommendations (or fewer if the list is short)

2. **Enrich each recommendation**
   - For each top event, use WebFetch to get additional details from the event page:
     - Speaker lineup or agenda highlights
     - Registration deadline
     - Early bird pricing if available
     - Any discount codes or group rates
   - Note if CFP (Call for Papers) is open, if the user expressed speaking interest

3. **Write recommendation blurbs**
   - For each event, write a concise recommendation explaining:
     - Why this event matters for the user's goals
     - What they'll get out of attending
     - Any urgency (early bird deadline, limited capacity)

4. **Create the final document**
   - Lead with a brief executive summary
   - Present events in recommended order
   - Include a quick-reference comparison table
   - End with clear next steps

## Output Format

### event_recommendations.md

The final curated recommendations document.

**Structure**:

```markdown
# Event Recommendations

- **Prepared**: [date]
- **Period**: [date range searched]
- **Location**: [base location]
- **Top Picks**: [count]

## Executive Summary

[2-3 sentences: what was searched, how many events found, top highlight]

## Quick Comparison

| Event  | Date   | Location | Cost   | Match              |
| ------ | ------ | -------- | ------ | ------------------ |
| [name] | [date] | [city]   | [cost] | [primary interest] |

## Recommendations

### 1. [Event Name]

**Date**: [date] | **Location**: [location] | **Cost**: [cost]
**Registration**: [URL]

**Why Attend**: [2-3 sentences on why this matters for the user's goals]

**Highlights**:

- [Speaker or session highlight]
- [Networking opportunity]
- [Other notable feature]

**Action Items**:

- [ ] Register by [deadline] for early bird pricing
- [ ] Submit talk proposal by [CFP deadline] (if applicable)
- [ ] Book travel by [date] for best rates

---

### 2. [Event Name]

[same structure]

---

## Next Steps

1. Review recommendations and select events to attend
2. [Specific action for the top-priority event]
3. [Calendar blocking suggestion]
```

## Quality Criteria

- Each recommendation includes enough information to decide whether to attend
- For each event, the reason it matters to the human's goals is stated
- Registration links or next steps are included for each recommended event
- The executive summary gives a quick overview without needing to read details
- Action items have specific deadlines where available
- The document is polished and ready for executive review

## Context

This is the final deliverable of the event discovery workflow. The user should be able to scan this document in 2 minutes and make attendance decisions. Clarity and actionability matter more than thoroughness.
