<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->

# Convention: Code Review Ownership (process.code-review-ownership)

This convention defines code ownership areas, maps them to team roles from `TEAM.md`, and ensures the right reviewers are automatically notified when a PR is ready for review. It relies on CODEOWNERS files with the task loop's notification-driven ingestion as the discovery mechanism.

**Platform** refers to the git hosting service (GitHub, Forgejo, or other CODEOWNERS-compatible git service).

## Ownership Matrix

1. Code ownership MUST be defined by team role (CPO, CTO, CEO), not by hardcoded usernames.
2. Usernames for each role MUST be resolved from `TEAM.md` using the platform-appropriate column.
3. The ownership areas MUST follow this matrix:

| Area                    | File Patterns                                                                             | Reviewer Role(s) |
| ----------------------- | ----------------------------------------------------------------------------------------- | ---------------- |
| Documentation & content | `docs/` (incl. `docs/specs/`), `blog/`                                                                | CPO              |
| Infrastructure & Nix    | `*.nix`, `flake.*`, `modules/`, `hosts/`                                                  | CTO, CEO         |
| CI/CD pipelines         | `.github/workflows/`, `.forgejo/workflows/`, `Makefile`, `Dockerfile`, `docker-compose.*` | CTO, CEO         |
| Application source code | `src/`, `packages/`, `*.ts`, `*.rs`, `*.py`, `*.go`                                       | CTO              |
| Agent & root config     | `CLAUDE.md`, `TEAM.md`, `SOUL.md`, `AGENTS.md`                                            | CEO              |

4. When a file matches multiple ownership areas, ALL matching owners MUST be requested as reviewers.
5. The CPO SHOULD be added as reviewer for any PR that modifies cross-references between documentation files, even if the PR is primarily code.

## CODEOWNERS Files

6. Every repository MUST contain a CODEOWNERS file implementing the ownership matrix.
7. On GitHub, the CODEOWNERS file MUST use glob patterns and be placed at the repo root or in `.github/CODEOWNERS`.
8. On Forgejo, the CODEOWNERS file MUST use Go regex patterns and be placed at the repo root or in `.forgejo/CODEOWNERS`.
9. CODEOWNERS files MUST use usernames resolved from `TEAM.md` for the target platform.
10. CODEOWNERS files MUST be regenerated when `TEAM.md` role assignments or usernames change.
11. CODEOWNERS files SHOULD include a comment header referencing this convention and `TEAM.md` as the source of truth.
12. Repos SHOULD enable branch protection requiring code owner review so that CODEOWNERS auto-requests reviewers on PR creation/undraft. If branch protection is not enabled, the authoring agent MUST manually request reviewers per the ownership matrix.

## Notification-Driven Discovery

13. CODEOWNERS MUST be relied upon to auto-request reviews when a PR is created or undrafted, provided branch protection is configured per rule 12.
14. The task loop's pre-fetch phase discovers review requests via the platform's notifications API, filtering for review-requested notifications — see `process.agent-cronjobs` for task loop details.
15. Agents MUST NOT poll for review assignments outside the task loop.
16. The notification-driven flow via CODEOWNERS is the sole discovery mechanism for PR review requests.

## Interaction with Existing Conventions

17. This convention extends `process.feature-delivery` rules 21-23 by codifying which reviewers are "appropriate" for each file area.
18. Copilot reviews per `process.copilot-agent` remain supplementary and MAY be requested in addition to ownership-based reviewers.
19. The `code-reviewer` role in `archetypes.yaml` SHOULD list this convention so agents in code-review mode have the ownership matrix available.
20. On Forgejo, `tool.forgejo` rule 18 (repo owner as reviewer) is satisfied by including the repo owner in the CODEOWNERS file's ownership matrix. Forgejo supports CODEOWNERS natively.

## Golden Example

### GitHub CODEOWNERS (`.github/CODEOWNERS`)

Resolve `{ceo}`, `{cpo}`, `{cto}` from the GitHub column of `TEAM.md`:

```
# CODEOWNERS — Source of truth: TEAM.md
# Convention: process.code-review-ownership

# Documentation & content — CPO reviews
docs/                    @{cpo}
docs/specs/              @{cpo}
blog/                    @{cpo}

# Infrastructure & Nix — CTO + CEO review
*.nix                    @{cto} @{ceo}
flake.*                  @{cto} @{ceo}
modules/                 @{cto} @{ceo}
hosts/                   @{cto} @{ceo}

# CI/CD — CTO + CEO review
.github/                 @{cto} @{ceo}
Makefile                 @{cto} @{ceo}
Dockerfile               @{cto} @{ceo}
docker-compose*          @{cto} @{ceo}

# Application source — CTO reviews
src/                     @{cto}
packages/                @{cto}

# Agent & root config — CEO reviews
/CLAUDE.md               @{ceo}
/TEAM.md                 @{ceo}
/SOUL.md                 @{ceo}
/AGENTS.md               @{ceo}
```

### Forgejo CODEOWNERS (`.forgejo/CODEOWNERS`)

Same ownership matrix but uses Go regex patterns. Resolve `{ceo}`, `{cpo}`, `{cto}` from the Forgejo column of `TEAM.md`:

```
# CODEOWNERS — Source of truth: TEAM.md
# Convention: process.code-review-ownership

# Documentation & content — CPO reviews
docs/.* @{cpo}
docs/specs/.* @{cpo}
blog/.* @{cpo}

# Infrastructure & Nix — CTO + CEO review
.*\.nix$ @{cto} @{ceo}
flake\..* @{cto} @{ceo}
modules/.* @{cto} @{ceo}
hosts/.* @{cto} @{ceo}

# CI/CD — CTO + CEO review
\.forgejo/workflows/.* @{cto} @{ceo}
Makefile @{cto} @{ceo}
Dockerfile @{cto} @{ceo}
docker-compose.* @{cto} @{ceo}

# Application source — CTO reviews
src/.* @{cto}
packages/.* @{cto}

# Agent & root config — CEO reviews
^CLAUDE\.md$ @{ceo}
^TEAM\.md$ @{ceo}
^SOUL\.md$ @{ceo}
^AGENTS\.md$ @{ceo}
```

### End-to-End Flow

```
1. Developer pushes PR touching src/api/handler.ts
2. Platform reads CODEOWNERS → matches src/ → CTO
3. Platform auto-requests review from CTO's username
4. Notification generated: reason=review_requested
5. Task loop pre-fetch: notifications API → finds review request
6. Task loop ingest: creates task in TASKS.yaml
7. Agent executes review in code-reviewer role
```
