Route engineering requests to the appropriate DeepWork workflow.

Use this skill for implementation tasks, code review, architecture decisions,
bug fixes, refactoring, and CI/CD work.

## Supporting references

Before starting implementation, review the relevant convention files
(co-located in this skill directory) for standards and process:

- **Software engineer role**: [software-engineer.md](software-engineer.md) -- implementation behavior, scope discipline, output format
- **Code reviewer role**: [code-reviewer.md](code-reviewer.md) -- review focus, security checks, style enforcement
- **Architect role**: [architect.md](architect.md) -- system design, trade-off analysis, spec writing
- **Feature delivery**: [process.feature-delivery.md](process.feature-delivery.md) -- end-to-end lifecycle from issue through merged PR
- **Pull requests**: [process.pull-request.md](process.pull-request.md) -- PR structure, squash merge rules, demo requirements
- **Code review ownership**: [process.code-review-ownership.md](process.code-review-ownership.md) -- review assignment and approval flow
- **Continuous integration**: [process.continuous-integration.md](process.continuous-integration.md) -- CI pipeline standards
- **Refactoring**: [process.refactor.md](process.refactor.md) -- safe refactoring process
- **Version control**: [process.version-control.md](process.version-control.md) -- commit discipline, conventional commits
- **Version control (advanced)**: [process.version-control-advanced.md](process.version-control-advanced.md) -- rebase, conflict resolution, lock files
- **VCS context continuity**: [process.vcs-context-continuity.md](process.vcs-context-continuity.md) -- PR progress tracking and resumability
- **Git repos**: [process.git-repos.md](process.git-repos.md) -- repo cloning, worktree layout
- **Shell scripts**: [code.shell-scripts.md](code.shell-scripts.md) -- shell script standards
- **Code comments**: [code.comments.md](code.comments.md) -- commenting standards
- **Nix devshell**: [tool.nix-devshell.md](tool.nix-devshell.md) -- project-specific Nix environments

## Available workflows

### engineer

- **engineer/implement** -- implement a feature, fix, or refactor with TDD and quality gates
- **engineer/doctor** -- diagnose and fix engineering environment issues

### platform_engineer

- **platform_engineer/incident_investigation** -- full incident investigation from triage to report
- **platform_engineer/quick_investigate** -- rapid incident triage without formal report
- **platform_engineer/doctor** -- debug local dev environment issues and unblock developer
- **platform_engineer/error_tracking** -- set up exception monitoring (Sentry, Honeybadger, etc.)
- **platform_engineer/dashboard_management** -- inspect and develop Grafana dashboards for services
- **platform_engineer/cicd_optimization** -- review CI/CD pipelines and suggest optimizations
- **platform_engineer/release_builder** -- set up CI release pipeline, release branches, and release notes
- **platform_engineer/infrastructure_audit** -- document and assess infrastructure setup against conventions
- **platform_engineer/cloud_spend** -- analyze cloud costs and identify waste
- **platform_engineer/vulnerability_scan** -- security vulnerability scanning and review
- **platform_engineer/observability_setup** -- set up Prometheus/Loki/VictoriaMetrics monitoring stack
- **platform_engineer/infrastructure_migration** -- plan and execute infrastructure migrations with validation gates
- **platform_engineer/soc_audit** -- assess SOC 2 readiness and produce compliance document
- **platform_engineer/platform_issue** -- create a platform engineering issue from current context

## Routing rules

- Implementation tasks, feature work, bug fixes --> `engineer/implement`
- Code review requests --> read `code-reviewer.md`, then review directly
- Architecture or design questions --> read `architect.md`, then answer directly or start `engineer/implement` for spec-driven work
- Engineering environment issues --> `engineer/doctor` or `platform_engineer/doctor`
- Incidents, outages, or triage --> `platform_engineer/incident_investigation` or `platform_engineer/quick_investigate`
- Monitoring, dashboards, observability --> `platform_engineer/dashboard_management` or `platform_engineer/observability_setup`
- CI/CD, release pipelines --> `platform_engineer/cicd_optimization` or `platform_engineer/release_builder`
- Infrastructure, cloud costs, migrations --> `platform_engineer/infrastructure_audit`, `platform_engineer/cloud_spend`, or `platform_engineer/infrastructure_migration`
- Security, compliance --> `platform_engineer/vulnerability_scan` or `platform_engineer/soc_audit`
- Filing a platform issue --> `platform_engineer/platform_issue`
- Keystone module or convention changes --> use `/ks-system` instead
- Filing general issues for discovered problems --> use `/ks-system` instead
- If unclear, ask the user which workflow to run before starting

## How to start a workflow

1. Call `get_workflows` to confirm available workflows.
2. Call `start_workflow` with `job_name: "engineer"` or `job_name: "platform_engineer"`, `workflow_name: <chosen>`, and `goal: "$ARGUMENTS"`.
3. Follow the step instructions returned by the MCP server.
