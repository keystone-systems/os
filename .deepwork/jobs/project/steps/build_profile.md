# Build Project Profile

## Objective

Synthesize all gathered information and investigation findings into a structured `projects/{slug}/README.yaml` profile document and update `PROJECTS.yaml` with the new project entry.

## Task

Read both intake_notes.md and investigation_report.md, then produce two outputs:

1. A comprehensive `projects/{slug}/README.yaml` — the canonical structured profile for this project
2. An updated `PROJECTS.yaml` — with the new project appended

### Process

1. **Determine the slug**
   - Use the slug from intake_notes.md
   - Ensure it's lowercase, hyphenated, and unique (not already in PROJECTS.yaml)

2. **Create the project directory**
   - Create `projects/{slug}/` if it doesn't exist

3. **Build README.yaml**
   - Merge information from both intake_notes.md and investigation_report.md
   - Fill in all fields from the schema below
   - For lean canvas fields that weren't discussed, use `null` rather than guessing
   - For repos, include access status from the investigation

4. **Prioritize riskiest assumptions**
   - Rank assumptions by: impact if wrong \* likelihood of being wrong
   - Map each risky assumption to the downstream workflow that would help validate it:
     - Market/customer uncertainty → `research` (competitive analysis, market research)
     - Product/feature uncertainty → `user_story` (user story definition)
     - Technical uncertainty → `research` (technical research)
     - Business model uncertainty → `research` (business model research)

5. **Generate recommended next steps**
   - Order recommendations by which riskiest assumption they address
   - The highest-risk assumption's validation workflow goes first
   - Include a brief rationale for each recommendation

6. **Update PROJECTS.yaml**
   - Read the current PROJECTS.yaml from the repo root
   - Append the new project at the end (lowest priority) unless the user specified otherwise
   - Preserve all existing projects exactly as they are
   - Add: name, description, status, priority, updated (today's date)

## Output Format

### projects/{slug}/README.yaml

**Structure**:

```yaml
---
name: "[Project Name]"
slug: "[project-slug]"
description: "[One-paragraph description]"
mission: "[One-sentence mission statement]"
type: "[commercial / nonprofit / open-source / mission-focused]"
status: "[idea / prototype / active / launched / maintenance]"
created_at: "[YYYY-MM-DD]"

domains:
  - name: "[domain.com]"
    purpose: "[marketing / app / docs / api]"
    status: "[active / planned / down]"

repos:
  - url: "[git@github.com:org/repo.git or https://...]"
    platform: "[github / forgejo / other]"
    description: "[What this repo contains]"
    agent_access:
      drago: "[yes / no / untested]"
      luce: "[yes / no / untested]"

lean_canvas:
  problem:
    - "[Problem 1]"
    - "[Problem 2]"
  customer_segments:
    - "[Segment 1]"
  unique_value_proposition: "[UVP statement]"
  unfair_advantage: "[Advantage or null]"
  key_metrics:
    - "[Metric 1]"
  # Optional fields (null if not discussed)
  solution: null
  channels: null
  cost_structure: null
  revenue_streams: null

riskiest_assumptions:
  - assumption: "[What we're betting on]"
    risk_level: "[high / medium]"
    validation_approach: "[How to test this]"
    recommended_workflow: "[research / user_story / requirements]"

recommended_next_steps:
  - workflow: "[workflow name]"
    rationale: "[Why this should be done first — tied to riskiest assumption]"
  - workflow: "[workflow name]"
    rationale: "[Why this comes next]"

user_stories_mentioned:
  - "[User story or feature mentioned during intake, if any]"

notes: "[Any additional context]"
```

### PROJECTS.yaml

The existing file with the new project appended. Example new entry:

```yaml
- name: "[project-name]"
  description: "[One-sentence description]"
  status: active
  priority: [next number]
  updated: "[YYYY-MM-DD]"
```

## Quality Criteria

- README.yaml includes all required fields: name, slug, description, mission, repos, lean_canvas, riskiest_assumptions, recommended_next_steps, status, created_at
- Riskiest assumptions are ranked and each maps to a specific downstream workflow
- Recommended next steps are ordered by risk priority (highest risk first)
- PROJECTS.yaml preserves all existing projects unchanged
- The new project is added with correct priority numbering
- README.yaml is valid, parseable YAML

## Context

This profile becomes the canonical reference for the project across the agent workspace. Downstream workflows (user_story, requirements, research) will read this README.yaml to understand the project context. The riskiest assumptions and recommended next steps are the most actionable part — they tell the user (and the agent's task loop) what to work on next.
