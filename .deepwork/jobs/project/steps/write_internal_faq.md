# Write Internal FAQ

## Objective

Produce the engineering internal FAQ — the reality check that must be completed before any code commitment. This document answers the four critical questions for every user story: feasibility, architecture, cost/effort, and risk. It is the engineering team's voice in the working-backwards process.

## Background

Before a single line of code is written or a project is greenlit, engineering must respond to the press release with an honest internal assessment. This is not a blocker — it is a quality gate that prevents the organization from approving a product that demands impossible physics or non-existent APIs.

The Internal FAQ serves three purposes:
1. **Reality check** — surfaces hidden complexity before commitment
2. **Scope negotiation input** — provides the data needed for the document review step
3. **Audit trail** — records why decisions were made before implementation

## Task

Read the scope analysis from the previous step and the press release embedded in the milestone issue body. For every user story, answer four questions. Then produce a summary verdict.

### Process

1. **Read the scope analysis**
   - Load `scope_analysis.md` from the `review_milestone` step
   - Extract all user stories, system boundaries, and implied prerequisites

2. **Read the press release**
   - Fetch the milestone issue body to get the embedded press release
   - Understand the customer promise being made — this is what engineering must validate

3. **Answer four questions per story**

   For each user story (`US-001`, `US-002`, etc.):

   **Feasibility**
   - Is this achievable with the current technology stack?
   - What would need to change (new libraries, new services, infrastructure upgrades)?
   - Are there hard blockers (missing APIs, unsupported features, licensing constraints)?

   **Architecture**
   - What hidden dependencies does this story imply?
   - Are there bottlenecks or systemic overhauls required?
   - Does this touch shared infrastructure that affects other systems?
   - What ordering constraints does this create?

   **Cost/Effort** (T-shirt sizing)
   - XS: < 1 day, 1-2 files
   - S: 1-3 days, contained change
   - M: 1-2 weeks, multiple components
   - L: 2-4 weeks, cross-cutting change
   - XL: > 1 month, significant architectural work
   - Provide a brief justification — not just the size

   **Risk**
   - Latency: could this slow down critical paths?
   - Scaling: does this break under load or at scale?
   - Security: does this introduce attack surface, data exposure, or auth risks?
   - Data integrity: could this corrupt or lose data?
   - Reversibility: how hard is it to undo if something goes wrong?

4. **Identify required technical spikes**
   - A spike is needed when a story relies on a novel mechanism or unproven technology
   - Each spike should have a clear blocking question and a time box
   - Spikes that cannot complete within 2-3 days indicate the story needs renegotiation

5. **Produce the summary verdict**
   - `green`: all stories are feasible, risks are manageable, proceed to document review and specs
   - `yellow`: some stories have unresolved questions — spikes required before specs can be written
   - `red`: one or more stories are infeasible or require scope renegotiation before proceeding

6. **Post the internal FAQ as a comment**
   - Post the internal FAQ as a comment on the milestone issue (visible to all stakeholders)
   - GitHub: `gh issue comment {number} --repo {owner}/{repo} --body "$BODY"`
   - Forgejo: `fj issue comment {number} -r {owner}/{repo} --body "$BODY"`

## Output Format

### internal_faq.md

```markdown
# Internal FAQ: [Milestone Title]

## Summary verdict: green | yellow | red

[1-2 sentences on the overall engineering assessment. Be direct.]

## Required spikes

- [SP-001]: [Spike question/hypothesis] — [Why this blocks specs]
- [SP-002]: [Spike question/hypothesis] — [Why this blocks specs]

(or: "None — all stories are feasible with current stack.")

## Story-by-story analysis

### US-001: [Story title]

**Feasibility**: [Can we do this? What would need to change? Any hard blockers?]

**Architecture**: [Hidden dependencies, bottlenecks, systemic overhauls, ordering constraints]

**Cost/Effort**: [XS/S/M/L/XL] — [Brief justification]

**Risk**: [Latency, scaling, security, data integrity, reversibility concerns — or "Low risk, no concerns."]

---

### US-002: [Story title]

...

## System-level concerns

[Cross-cutting concerns that affect multiple stories — shared infrastructure, ordering dependencies, deployment risks, etc.]
```

**Concrete example** (abbreviated):

```markdown
# Internal FAQ: Recipe Sharing Platform

## Summary verdict: yellow

Core recipe CRUD (US-001, US-003) is straightforward. Full-text search (US-002) needs a spike to
validate whether pg_trgm is sufficient or if Elasticsearch is required — this blocks the search spec.

## Required spikes

- [SP-001]: Does pg_trgm full-text search meet the performance requirement for 100k recipes? — Blocks US-002 spec: if insufficient, architecture changes significantly.

## Story-by-story analysis

### US-001: Add recipe creation form

**Feasibility**: Feasible with current stack (Next.js + Prisma + PostgreSQL). No new dependencies required.

**Architecture**: Requires a new `recipes` table migration. The image upload path needs S3 or local storage — this is an implied prerequisite not yet provisioned.

**Cost/Effort**: M — 1-2 weeks. Form component + API route + migration + image upload wiring.

**Risk**: Low for core CRUD. Image upload adds S3 IAM surface — must use pre-signed URLs, not direct upload to avoid credential exposure.

---

### US-002: Add recipe search

**Feasibility**: Uncertain. pg_trgm works for simple fuzzy search but may degrade at scale. Elasticsearch would be reliable but adds infrastructure cost and complexity.

**Architecture**: If pg_trgm: add GIN index to recipes table. If Elasticsearch: new service, sync pipeline, added operational burden.

**Cost/Effort**: S (pg_trgm) or XL (Elasticsearch) — spike required to decide.

**Risk**: Performance risk at scale. pg_trgm can cause table bloat if not maintained. Elasticsearch introduces eventual consistency.
```

## Quality Criteria

- Every user story from the scope analysis has feasibility, architecture, cost/effort, and risk answers
- T-shirt sizing is concrete (not "TBD") with a written justification for each story
- Required spikes are listed with a clear blocking question (not just "needs investigation")
- Summary verdict is one of `green`, `yellow`, or `red` with supporting rationale
- Internal FAQ is posted as a comment on the milestone issue before the step completes

## Context

This step is engineering's answer to the press release. The internal FAQ surfaces hidden complexity before any stakeholder commitment is made. A `green` verdict means the team has confidence in the proposed scope. A `yellow` verdict means spikes are needed before specs can be written. A `red` verdict means the scope must be renegotiated in the document review step. The goal is not to block — it is to ensure that the scope agreed upon in the next step is one engineering can actually deliver.
