# Gather Context

## Objective

Research the project and frame the customer problem, solution, and value proposition into a structured brief that will drive the press release draft.

## Task

Take the user-provided project name and feature brief, then build a structured context document that identifies the customer, articulates the problem they face, and frames the solution in terms of customer benefit. This brief serves as the foundation for the working-backwards press release.

### Process

1. **Ask clarifying questions — always**
   Before doing any research or drafting, ask the user these scoping questions. Do not skip this step even if the brief seems complete — the answers prevent scope creep and ensure the press release makes a promise the team can keep.

   **If the `AskUserQuestion` tool is available, use it** — structured question UI is faster and clearer for the user than a wall of text. Ask the six questions as separate structured questions in a single `AskUserQuestion` call, with short option lists where applicable (e.g. multiple-choice for customer segment) and free-text "Other" fallback.

   If `AskUserQuestion` is not available, batch all six as plain text in one message:
   - **Who is the primary customer?** — Be specific: not "developers" but "backend engineers building multi-tenant SaaS apps"
   - **What is the one problem this solves?** — What does the customer struggle with today that this fixes?
   - **What is in scope?** — What will actually be built or shipped as part of this?
   - **What is explicitly out of scope?** — What might the customer expect but won't be delivered?
   - **What is the single most important customer benefit?** — The headline should be this.
   - **How does the customer get started?** — A URL, a command, a signup flow

   Wait for answers before proceeding to the next steps.

2. **Identify the customer**
   - Who is the primary customer segment?
   - What is their role, context, or situation?
   - What do they care about most?

3. **Frame the problem**
   - What does the customer struggle with today?
   - What is the cost of the status quo (time, money, frustration)?
   - Why hasn't this been solved before, or why are existing solutions inadequate?

4. **Frame the solution**
   - How does this feature solve the problem?
   - What can the customer now do that they couldn't before?
   - What is the single most compelling benefit?

5. **Define key claims**
   - What specific, defensible claims can the press release make?
   - Claims MUST NOT exceed what the planned feature set can deliver
   - Each claim should be something the development team can build toward

If the feature brief is ambiguous about the customer segment, the problem being solved, or the scope of what will be built, ask structured questions to resolve the ambiguity before proceeding.

## Output Format

### context_brief.md

A structured markdown document that provides all the raw material needed to write the press release.

**Structure**:

```markdown
# Context Brief: [Feature/Product Name]

## Project

- **Name**: [project name]
- **Mission**: [project's overall business mission, derived from the brief]

## Customer

- **Segment**: [who the customer is]
- **Role/Context**: [their situation — e.g., "developers building web applications"]
- **Primary Need**: [what they need most]

## Problem

[2-3 sentences describing what the customer struggles with today. Be specific and concrete — not "it's hard to do X" but "developers spend 3 hours configuring Y before they can Z."]

## Solution

[2-3 sentences describing what the feature enables. Focus on what the customer can now do, not how the technology works.]

## Key Claims

- [Claim 1 — must be deliverable by the planned feature set]
- [Claim 2]
- [Claim 3]

## Call to Action

[How the customer gets started — sign up, visit a page, try a demo, etc.]

## Scope Notes

[What this feature implies must be built. This section helps development teams understand the commitment the press release makes.]
```

**Concrete example** (for reference):

```markdown
# Context Brief: Amazon S3

## Project

- **Name**: Amazon Web Services
- **Mission**: Make web-scale computing accessible and affordable for developers

## Customer

- **Segment**: Web developers and startups
- **Role/Context**: Developers building web applications who need to store and serve files
- **Primary Need**: Reliable, scalable storage without managing infrastructure

## Problem

Developers building web applications must provision, manage, and scale their own storage servers. When traffic spikes, storage fails. When it's quiet, they're paying for idle hardware. Most of their time goes to infrastructure instead of their actual product.

## Solution

Amazon S3 provides a simple web services interface to store and retrieve any amount of data, at any time, from anywhere on the web. Developers get the same storage infrastructure Amazon uses internally — without managing a single server.

## Key Claims

- Store and retrieve any amount of data
- Simple web services interface (REST/SOAP)
- Same infrastructure Amazon uses for its own sites
- Pay only for what you use

## Call to Action

Sign up for the Amazon S3 beta at aws.amazon.com/s3.

## Scope Notes

Implies building: REST API for object storage, pay-per-use billing, multi-region availability, and a developer console for account management.
```

## Quality Criteria

- The brief clearly identifies a specific customer segment and their needs
- The problem is stated before the solution, and both are concrete — not vague or generic
- Key claims do not exceed what the planned feature set can deliver
- The brief implies what must be built, providing development scoping value
- The customer quote direction captures genuine value, not marketing fluff
- The call to action is specific and actionable

## Context

This is the foundation step. The press release will be written directly from this brief, so the quality of the context determines the quality of the final output. The brief also serves a scoping purpose — by articulating what the press release will promise, the team can evaluate whether the development investment is justified before writing a single line of code.
