# Define Content Strategy

## Objective

Define the project's social media content strategy — posting schedule, content pillars, and brand voice — for each successfully set up platform.

## Task

Using the platform status from the previous step, create a content strategy tailored to the platforms that are active. Collaborate with the user to define their brand identity and goals.

### Process

1. **Review platform status**
   - Read platform_status.md to know which platforms are active
   - Only define strategy for platforms with completed setup

2. **Ask structured questions** to understand the brand:
   - What is the project's core value proposition?
   - Who is the target audience? (demographics, interests, pain points)
   - What tone fits the brand? (professional, casual, technical, playful, authoritative)
   - What are 3-5 topic areas the content should cover?
   - How often can they realistically post? (daily, 3x/week, weekly)
   - Are there any topics or tones to avoid?

3. **Define content pillars**
   - Create 3-5 themed content categories based on user input
   - Each pillar should have a clear purpose and example topics
   - Pillars should be balanced across educational, promotional, and engagement content

4. **Create posting schedule**
   - Define a realistic cadence per platform
   - Account for platform-specific best practices:
     - X: higher frequency OK (1-3x/day)
     - LinkedIn: lower frequency (2-4x/week)
     - Instagram: visual content focus (3-5x/week)
     - Bluesky: conversational tone (1-2x/day)
   - Suggest optimal posting times based on audience

5. **Define brand voice guidelines**
   - Document tone, vocabulary, and style rules
   - Provide do/don't examples for each platform
   - Note platform-specific adaptations (more formal on LinkedIn, more casual on Bluesky)

## Output Format

### content_strategy.md

**Save to**: `projects/[project_name]/marketing/content_strategy.md`

```markdown
# Content Strategy: [Project Name]

## Brand Overview

- **Value Proposition**: [one sentence]
- **Target Audience**: [description]
- **Brand Personality**: [3-4 adjectives]

## Content Pillars

### 1. [Pillar Name]

- **Purpose**: [what this content achieves]
- **Topics**: [example topics]
- **Content ratio**: [% of total content]

### 2. [Pillar Name]

...

[3-5 pillars total]

## Posting Schedule

| Platform          | Frequency | Best Times | Content Focus |
| ----------------- | --------- | ---------- | ------------- |
| [active platform] | [cadence] | [times]    | [focus]       |

[one row per active platform only — omit skipped platforms]

## Brand Voice

### Tone

[Description of overall tone]

### Do's

- [example of good voice]
- [example of good voice]

### Don'ts

- [example of what to avoid]
- [example of what to avoid]

### Platform Adaptations

- **X**: [how voice adapts]
- **LinkedIn**: [how voice adapts]
- **Instagram**: [how voice adapts]
- **Bluesky**: [how voice adapts]

## Topics to Avoid

- [list any sensitive or off-brand topics]
```

## Quality Criteria

- Strategy covers all platforms that were successfully set up
- Posting schedule is specific (days/times) and realistic
- Brand voice guidelines are concrete enough to follow, not generic platitudes
- Content pillars are distinct and cover a balanced mix of content types
- Platform-specific adaptations reflect actual platform culture differences

## Context

This strategy document becomes the operational playbook for future content creation workflows. It should be specific enough that an agent or team member can create on-brand content without further guidance. The strategy will be summarized in PROJECTS.yaml in the next step for quick reference.
