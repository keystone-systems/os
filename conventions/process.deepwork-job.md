<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->

# Convention: DeepWork Job Design (process.deepwork-job)

This convention governs the design of [DeepWork](https://deepwork.dev) jobs — when to create a job vs. a workflow, how to structure steps, when to create slash commands, and how to version and document jobs. The job schema at `.deepwork/job.schema.json` is authoritative for structural validation; this convention covers design decisions.

## Terminology

1. A **job** MUST represent a single capability area packaged at `.deepwork/jobs/{name}/job.yml` (or `.deepwork/jobs-internal/{name}/job.yml` for keystone-development-only jobs — see `process.keystone-development` rules 21–22) containing steps, workflows, and shared context — jobs define what is possible.
2. A **workflow** MUST be a named execution path through a job's steps, invoked via `start_workflow(job_name, workflow_name, ...)` — workflows define how to execute.
3. A **step** MUST be the atomic unit of work within a job, with its own instructions, inputs, outputs, and optional quality reviews.

## Job Scope

4. A job MUST represent a capability area, not a single task.
5. Related workflows MUST be grouped in one job — agents MUST NOT create separate jobs for what should be workflows within a single job.
6. If two proposed jobs share more than half their steps, they SHOULD be merged into one job with multiple workflows.
7. A new job is warranted only when the capability area, steps, and shared context are distinct from all existing jobs.

## Workflow Design

8. Every step MUST appear in at least one workflow — orphaned steps MUST NOT exist.
9. The primary workflow SHOULD share the job's name.
10. Subset workflows SHOULD represent real user scenarios (e.g., "review only", "quick check"), not arbitrary step subsets.
11. Steps grouped as arrays in a workflow (parallel execution) MUST be truly independent with no shared inputs or outputs.

## Step Design

12. Steps MUST be designed for reuse across multiple workflows within the job.
13. Each step MUST produce at least one required output.
14. Step instruction files MUST follow the structure: Objective, Task (Process), Output Format, Quality Criteria, Context.

## Slash Commands and Skills

15. Workflows that agents or users invoke regularly (daily or weekly) SHOULD get a dedicated slash command or skill registration.
16. Skill definitions MUST use the platform-appropriate mechanism:
    - **Claude Code**: `.claude/skills/{name}/SKILL.md` with frontmatter (`name`, `description`).
    - **OpenCode**: OpenCode skill directory or equivalent configuration.
    - **Gemini**: Gemini skill registration.
    - **Codex**: Codex skill registration.
17. Skills MUST call the DeepWork MCP tools (`start_workflow`, `finished_step`) and MUST NOT duplicate step logic inline.
18. Skills MUST document which job and workflow they invoke.
19. Good candidates for dedicated skills include task loops, status checks, and code delivery — workflows invoked regularly.
20. One-off workflows (setup, bootstrapping, onboarding) SHOULD NOT get dedicated skills — invoke them via the generic `/deepwork` command.

## Versioning and Documentation

21. Job versions MUST follow semantic versioning: patch (0.0.x) for instruction tweaks, minor (0.x.0) for review criteria or input/output changes, major (x.0.0) for step additions/removals or workflow restructuring.
22. Job-specific learnings MUST be captured in `.deepwork/jobs/{job}/AGENTS.md` (or `.deepwork/jobs-internal/{job}/AGENTS.md` for keystone-development-only jobs).
23. The AGENTS.md file MUST include a "Last Updated" section with date and conversation context.

## Golden Example

**Correct**: One `research` job with multiple workflows sharing steps.

```yaml
# .deepwork/jobs/research/job.yml
name: research
version: "1.1.0"
summary: "Conduct structured research on any topic"

workflows:
  - name: research # Primary workflow shares job name (rule 9)
    summary: "Full research from scoping through final report"
    steps:
      - scope # All steps appear in at least one workflow (rule 8)
      - [search_web, search_docs] # Parallel — truly independent (rule 11)
      - synthesize
      - report

  - name: quick_check # Subset for a real scenario (rule 10)
    summary: "Fast web-only research without deep synthesis"
    steps:
      - scope
      - search_web
      - report

steps:
  - id: scope # Reusable across both workflows (rule 12)
    # ...
  - id: search_web
    # ...
  - id: search_docs
    # ...
  - id: synthesize
    # ...
  - id: report
    # ...
```

**Anti-pattern**: Two separate jobs for the same capability area.

```yaml
# WRONG: .deepwork/jobs/full_research/job.yml
name: full_research
steps: [scope, search_web, search_docs, synthesize, report]
workflows:
  - name: full_research
    steps: [scope, [search_web, search_docs], synthesize, report]

# WRONG: .deepwork/jobs/quick_research/job.yml
name: quick_research
steps: [scope, search_web, report]  # Shares 3/5 steps with full_research!
workflows:
  - name: quick_research
    steps: [scope, search_web, report]
```

This violates rules 5 and 6 — the two jobs share most of their steps and should be one job with two workflows.

## References

- [DeepWork documentation](https://deepwork.dev)
- Job schema: `.deepwork/job.schema.json`
- Job creation workflow: `deepwork_jobs/new_job`
