# Rank and Filter

## Objective

Score and rank discovered events by relevance to the user's interests, filter out low-value options, and produce a prioritized shortlist.

## Task

Apply a structured scoring system to evaluate each event candidate against the interest profile. Remove low-relevance events and rank the rest.

### Process

1. **Read inputs**
   - Parse interest_profile.md for interests, priorities, and preferences
   - Parse event_candidates.md for all discovered events

2. **Define scoring criteria**
   - Interest match (0-3): How well does the event match a stated interest area? Weight by interest priority.
   - Logistics fit (0-2): Does the location, date, cost, and format match preferences?
   - Networking value (0-2): Does the event offer relevant networking opportunities?
   - Quality signals (0-1): Known organizer, past editions, speaker quality

3. **Score each event**
   - Apply the scoring criteria to each event
   - Calculate a total score (max 8)
   - Note the rationale for each score

4. **Filter and rank**
   - Remove events scoring below 3 (clearly irrelevant)
   - Rank remaining events by total score, highest first
   - For ties, prefer events that match higher-priority interests

5. **Note filtered-out events**
   - Briefly explain why low-scoring events were cut

## Output Format

### ranked_events.md

Events ranked by relevance with scores and rationale.

**Structure**:

```markdown
# Ranked Events

- **Total Candidates**: [count from search]
- **After Filtering**: [count remaining]
- **Filtered Out**: [count removed]

## Top Events

### Rank 1: [Event Name] — Score: [X/8]

- **Date**: [date]
- **Location**: [location]
- **Cost**: [cost]
- **URL**: [link]
- **Scores**:
  - Interest Match: [0-3] — [rationale]
  - Logistics Fit: [0-2] — [rationale]
  - Networking Value: [0-2] — [rationale]
  - Quality Signals: [0-1] — [rationale]
- **Best For**: [which interest area / goal]

### Rank 2: [Event Name] — Score: [X/8]

[same structure]

[Continue for all ranked events]

## Filtered Out

| Event  | Score   | Reason                                                                |
| ------ | ------- | --------------------------------------------------------------------- |
| [name] | [score] | [why it was cut — e.g., wrong location, too expensive, low relevance] |
```

## Quality Criteria

- Each event has a clear score and rationale tied to specific interest areas
- Low-relevance events are excluded with brief justification
- Scoring is consistent — similar events get similar scores
- The ranking prioritizes the user's highest-priority interests
- The filtered-out table gives transparency into what was removed

## Context

This ranking step bridges raw discovery and final recommendations. A clear, justified scoring system helps the user trust the recommendations and makes it easy to override if they disagree with a ranking.
