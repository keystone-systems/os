# Gather Project Basics

## Objective

Collect core project information through an interactive conversation with the user, covering identity, mission, infrastructure, and lean canvas fundamentals.

## Task

Have a structured conversation with the user to gather everything needed to build a project profile. Ask structured questions using the AskUserQuestion tool. Start with what the user has already provided (the project_name input), then fill in gaps through focused follow-up questions.

### Process

1. **Establish project identity**
   - Confirm the project name and derive a slug (lowercase, hyphens)
   - Ask for a one-sentence mission statement
   - Ask for a longer description if the mission statement isn't sufficient

2. **Collect infrastructure details**
   - Ask about domains (websites, landing pages, documentation sites)
   - Ask about git repositories — collect URLs for each
   - For each repo, note the platform (GitHub, Forgejo/git.ncrmro.com, other)
   - Ask if any repos need to be created

3. **Lean Canvas discovery (ask 3-5 of these)**

   Ask structured questions to fill in lean canvas fields. Prioritize based on what the user hasn't already covered. You don't need to ask all of these — pick the 3-5 most relevant:
   - **Problem**: "What are the top 1-3 problems this project solves?"
   - **Customer Segments**: "Who are the target users or beneficiaries?"
   - **Unique Value Proposition**: "What's the single clearest reason someone would choose this over alternatives?"
   - **Unfair Advantage**: "Is there anything you have that can't be easily copied? (expertise, data, network, etc.)"
   - **Key Metrics**: "How will you measure success for this project?"

4. **Identify riskiest assumptions**
   - Based on the conversation, identify what the project is betting on that hasn't been validated
   - Ask the user: "What's the thing that would kill this project if it turned out to be wrong?"
   - Note 2-4 riskiest assumptions

5. **Surface potential user stories**
   - Ask: "Are there specific user stories or features you already have in mind that should be tracked?"
   - Note any mentioned but don't deep-dive — that's for a downstream workflow

6. **Determine project type and status**
   - Ask structured questions about project type (commercial, nonprofit, open-source, mission-focused)
   - Ask about current status (idea, prototype, active development, launched, maintenance)

### Conversation Tips

- Don't ask all questions at once — batch them into 2-4 at a time using AskUserQuestion
- If the user has a public website, note it for the investigate step but don't browse it yet
- If the user mentions repos, collect the full URLs
- Keep the conversation moving — 3-5 rounds of questions maximum

## Output Format

### intake_notes.md

A structured summary of everything gathered during the conversation.

**Structure**:

```markdown
# Project Intake Notes: [Project Name]

## Identity

- **Name**: [project name]
- **Slug**: [lowercase-hyphenated]
- **Type**: [commercial / nonprofit / open-source / mission-focused]
- **Status**: [idea / prototype / active / launched / maintenance]
- **Mission**: [one-sentence mission]
- **Description**: [longer description if provided]

## Infrastructure

### Domains

- [domain1.com] — [purpose: marketing site, app, docs, etc.]

### Git Repositories

- [url] — [platform] — [description]
- [url] — [platform] — [needs to be created: yes/no]

## Lean Canvas

### Problem

[Top 1-3 problems]

### Customer Segments

[Target users/beneficiaries]

### Unique Value Proposition

[Single clearest reason to choose this]

### Unfair Advantage

[What can't be easily copied, or "none identified yet"]

### Key Metrics

[How success is measured]

## Riskiest Assumptions

1. [Assumption] — [Why it's risky]
2. [Assumption] — [Why it's risky]

## User Stories Mentioned

- [Any user stories or features the user brought up, or "None mentioned"]

## Notes

[Any other relevant context from the conversation]
```

## Quality Criteria

- Project name, slug, and mission are captured
- At least one domain or git repo is documented
- At least 3 of 5 lean canvas fields have substantive answers
- Riskiest assumptions are identified (not just listed generically)
- The notes are comprehensive enough for someone who wasn't in the conversation to understand the project

## Context

This is the first step in project onboarding. The information gathered here drives everything downstream: the investigate step will check repos and websites, build_profile will synthesize it into a structured YAML document, and the riskiest assumptions will determine which downstream workflows (user stories, requirements, competitive research) are recommended first.
