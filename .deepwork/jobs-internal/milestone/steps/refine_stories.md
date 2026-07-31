# Refine User Stories

## Objective

Transform raw scope content (from an issue or freehand notes) into properly formatted user stories with acceptance criteria, priority tags, and ownership labels. Also generate a milestone title from the scope.

## Task

Read the raw scope document and decompose it into discrete user stories following the standard format. The input may be rough notes, bullet points, or partially formed ideas — your job is to identify the distinct units of work and express each as a clear user story.

### Process

1. **Read the raw scope**
   - Read `raw_scope.md` from the previous step
   - Identify all distinct features, tasks, or deliverables mentioned
   - Note any priorities or categories the author implied (e.g., "nice to have", "must have")

2. **Generate the milestone title**
   - Derive a concise title from the issue title (if present) or the overall theme of the notes
   - The title should capture the product/feature name or customer benefit
   - Keep it short (3-8 words), title case
   - Write it to `milestone_title.md`

3. **Decompose into user stories**
   - Each distinct feature or deliverable becomes its own story
   - Group related items if they are too granular to stand alone
   - Split items that contain multiple distinct deliverables

4. **Write each story in standard format**
   - Choose an appropriate persona (developer, user, operator, admin, etc.)
   - Express the action clearly — what capability does the persona gain?
   - Articulate the benefit — why does this matter?
   - Write acceptance criteria as a testable checklist

5. **Assign ownership and priority**
   - Tag each story as `engineering` or `product`:
     - `engineering`: implementation, infrastructure, code, deployment
     - `product`: documentation, processes, communications, analytics, UX, design
   - Assign priority based on cues in the original content:
     - `high`: core functionality, explicitly required, blocking other work
     - `medium`: important but not blocking, enhances core functionality
     - `low`: nice-to-have, future improvements, polish

6. **Add traceability**
   - Each story must include a "Derived from" line that points back to the specific item in the raw scope

## Output Format

### refined_stories.md

**Structure**:

```markdown
# User Stories

## Engineering Stories

### [Concise action statement]

**As a** [persona], **I want** [action], **so that** [benefit].

**Acceptance Criteria:**

- [ ] [Testable criterion 1]
- [ ] [Testable criterion 2]
- [ ] [Testable criterion 3]

**Derived from:** [quote or reference to raw scope item]
**Priority:** [high | medium | low]

---

[Repeat for each engineering story]

## Product Stories

### [Concise action statement]

[Same format as above]

---

[Repeat for each product story]
```

**Concrete example**:

```markdown
# User Stories

## Engineering Stories

### Deploy Prometheus metrics collection

**As a** homelab operator, **I want** Prometheus deployed and scraping all nodes, **so that** I have centralized metrics for troubleshooting and capacity planning.

**Acceptance Criteria:**

- [ ] Prometheus server is deployed and accessible
- [ ] Node exporter is installed on all managed machines
- [ ] Scrape targets are auto-discovered or explicitly configured
- [ ] Metrics are retained for at least 30 days

**Derived from:** "Prometheus for metrics collection" and "Node exporter on all machines"
**Priority:** high

---

### Set up Grafana dashboards

**As a** homelab operator, **I want** Grafana dashboards showing key system metrics, **so that** I can monitor health at a glance.

**Acceptance Criteria:**

- [ ] Grafana is deployed and connected to Prometheus
- [ ] Dashboard exists for CPU, memory, disk, and network per node
- [ ] Dashboards are provisioned as code (not manual)

**Derived from:** "Grafana dashboards"
**Priority:** high

---

### Configure Slack alerting

**As a** homelab operator, **I want** alerts sent to Slack when services are unhealthy, **so that** I'm notified of problems without watching dashboards.

**Acceptance Criteria:**

- [ ] Alertmanager is configured with Slack webhook
- [ ] Alerts fire for node-down, high CPU, high disk usage
- [ ] Alert messages include actionable context (which node, which metric)

**Derived from:** "Alerting to Slack when stuff breaks"
**Priority:** medium

## Product Stories

(none for this scope)
```

### milestone_title.md

A single-line file containing the milestone title.

**Structure**:

```
[Milestone Title in Title Case]
```

**Example**:

```
Homelab Monitoring Stack
```

## Quality Criteria

- Every distinct scope item from the raw input maps to at least one user story
- Each story follows the format: As a [persona], I want [action], so that [benefit]
- Each story has a checklist of testable acceptance criteria
- Each story is tagged as `engineering` or `product` with logical distinction
- Each story has a priority tag (high / medium / low)
- Each story has a "Derived from" line tracing back to the raw scope
- The milestone title is concise and captures the overall theme

## Context

This step is the intellectual core of the workflow. The raw input may be messy, incomplete, or informal — your job is to interpret it charitably, identify the real intent, and express it in a structured format that enables clear review and task tracking. When in doubt about scope or intent, err on the side of capturing what was stated rather than adding assumptions.
