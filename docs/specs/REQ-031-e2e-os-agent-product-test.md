# REQ-031: E2E OS Agent Product Test

Pluggable test harness that validates the full Keystone product-to-engineering
agent lifecycle by orchestrating a palindrome feature request through email
intake, specification, implementation, testing, and release verification.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Raw Design Notes

Let us make this async, with a progresivly generateing yaml report or json what ever is easier but we present to the use in a report, I belive pandoc is available, so this should also support a --print flag. which will print this when it's done. later we can add zpool scrubs/smart disk reports etc, sky is the limit in terms of hardware software checks. point being we
should put the extra effort into making this design pretty plugable/moduleur and paramaterizeble. Right now the only super long checks are indeed the email ping pong check, we should also have a palindrome test that the agent is supposed to complete, also handled via email. This script will be like hackerrank tests where the solution is handled by standrd in/out/pipes
and the output must be valid json schema. This means the agent can write the solution how ever it chooses. This is the engineering archetypes. it will get this job from product via a fj repo issue who has was assigned this via email. this repo will be dynamically cleaned up between runs.

. system procedrual code that checks software/hardware. And the full e2e keystone system os agents product worflow e2e demo. That is the test sends an email to the palindrome product requirements agent (in my personal system called luce, keystone repo needs its own name) via email, she creates the press release issue and
milestone (deepwork jobs, we need skills really start shining here), assigns this to the engieering agent on the product issue site, he creates the engineering ticket (also on the milestone, checking issues and milestones is important here) with the engineering issue, a branch is created for this milestone as a trunk branch, the test must check agent should have this as
a worktree in their trunch branch at the end of this, this should have the functional requirements defined a specs/REQ-\* (again this should be checekd there should be REQ-001-palindrome or something of that nature as we are using the palindrome example). The palindrome solver should actually be in a bun super simple html server serverd by what ever language is choosen
(this could very by model provider/model and should be interested to note maybe in model matrix evals later make sure to note this), the reason this is important, is the agent make have an e2e test written the screenshots which are uplaoded when the e2e test playright happy path golden test takes required screenshots via lfs

the bun server repo is already setup from a fork in this scneario, it has two packages/<web,e2e>, it has a very suscint agent.md each web and e2e of their own AGENT.md. at the start of the test the old repo is deleted it is then forked from this fork. Its is cleared from their disk each time, the project note hub is reset each time and any tagged notes with that project hub note (pluss some sort of e2e suffix to really ensure we don't clean up other things that shoul dstay)

This means the agents each have everything staged from the git go, they just have to handle the email and cordinating the palindrome feature added and tested in the bun html server with screenshots in git lfs, the screenshots follow test-name.step-index.step-name.png)

Finally the enginerring agent merges this into the trunk branch, a pr is made with the changed cherrypicked into and released. The engineering agent at this point can complete the issue, the engeer will comment the milestone pr mentiong what pr the feature was merged into. the product agent can then verify these changes on the release version verifying the lfs commeted screenshots and what she sees on the real environemnt are the same.

palindrome milestone complete. later on we can tac on other workflows like business analyast and marketing but right now we only focus on the engineering lifecyle

---

## Functional Requirements

### FR-001: Test Harness Framework

**REQ-031.1** The test harness MUST execute asynchronously, producing a
progressively-generated structured report as each check completes.

**REQ-031.2** The report MUST be YAML format, written incrementally to a
well-known output path.

**REQ-031.3** The harness MUST support a `--print` flag that renders the
final report to stdout via pandoc when all checks complete.

**REQ-031.4** The harness MUST implement a pluggable check architecture
where each check is an independent module that receives a shared context
and appends results to the report.

**REQ-031.5** Each check result MUST include: `name`, `status`
(pass | fail | skip | running), `started_at`, and an optional `details`
string. `completed_at` MUST be present for terminal statuses (pass, fail,
skip) and MUST be null or omitted while the status is `running`.

**REQ-031.6** The harness MUST accept parameters for: product agent name,
engineering agent name, platform (forgejo), and model provider.

**REQ-031.7** The harness MUST support a `--dry-run` flag that validates
configuration and environment prerequisites without executing the
workflow.

### FR-001a: Agent Quiescence

**REQ-031.7a** Before executing any workflow steps, the harness MUST
pause both agents' task loops (equivalent to `ks agents pause <agent>
"e2e test in progress"`) to prevent autonomous work from interfering
with the test.

**REQ-031.7b** If an agent has an active task at pause time, the harness
MUST prompt the operator to kill it and MUST NOT proceed until the
operator acknowledges or skips.

**REQ-031.7c** The harness MUST resume both agents' task loops when the
E2E run completes, whether it succeeds or fails.

**REQ-031.7d** In `--dry-run` mode, the harness MUST check agent pause
state but MUST NOT pause or resume agents.

### FR-002: Environment Lifecycle

**REQ-031.8** A bun server template repository MUST exist at
`ks-testing/agent-e2e-bun-template` on Forgejo with the structure
`packages/web/` and `packages/e2e/`, each containing its own `AGENTS.md`.

**REQ-031.9** The `packages/web/` template MUST contain a minimal bun HTTP
server with an HTML form for string input and no palindrome logic
pre-implemented. The agent is free to implement the backend in any
language.

**REQ-031.10** The `packages/e2e/` template MUST contain a Playwright
project scaffold configured to capture screenshots, with no test cases
pre-written.

**REQ-031.11** At the start of each test run, the harness MUST delete any
prior fork of the template repo on the target platform, then create a
fresh fork from `ks-testing/agent-e2e-bun-template`.

**REQ-031.12** At the start of each test run, the harness MUST remove the
bun server repo from each agent's disk (worktrees and clones).

**REQ-031.13** At the start of each test run, the harness MUST reset the
project hub note and any tagged notes bearing an e2e-specific suffix to
prevent collateral cleanup of unrelated notes.

**REQ-031.14** The template repo MUST configure git LFS for `*.png` files
in a `.gitattributes` at the repo root.

### FR-003: Product Agent — Requirement Intake

**REQ-031.15** The harness MUST send a palindrome feature requirement to
the product agent via email using `agent-mail` or equivalent.

**REQ-031.16** The product agent MUST create a press release issue on the
target platform following the `process.press-release` convention.

**REQ-031.17** The product agent MUST create a milestone on the target
platform and associate the press release issue with it.

**REQ-031.18** The product agent MUST assign the engineering agent to the
press release issue or create a linked engineering-intake issue assigned
to the engineering agent.

### FR-004: Engineering Agent — Specification

**REQ-031.19** The engineering agent MUST create an engineering issue on the
milestone with acceptance criteria derived from the press release.

**REQ-031.20** The engineering agent MUST create a trunk branch for the
milestone in the bun server repo.

**REQ-031.21** The engineering agent MUST create a worktree for the trunk
branch at the conventional path
`$HOME/repos/{owner}/{repo}/worktrees/{branch}/`.

**REQ-031.22** The engineering agent MUST define functional requirements in
`specs/REQ-001-palindrome.md` (or equivalent REQ-prefixed file) within the
bun server repo using RFC 2119 key words.

### FR-005: Engineering Agent — Implementation

**REQ-031.23** The engineering agent MUST implement a palindrome solver as a
backend service in the bun server repo. The agent MAY choose any language
or framework for the backend implementation.

**REQ-031.24** The palindrome solver MUST be accessible via the HTML form in
`packages/web/` — the form submits a string, and the page displays whether
it is a palindrome.

**REQ-031.25** The backend response MUST validate against a JSON schema
defined in the spec (e.g.,
`{"type":"object","properties":{"input":{"type":"string"},"is_palindrome":{"type":"boolean"}},"required":["input","is_palindrome"]}`).

**REQ-031.26** The language and framework chosen by the agent MUST be
recorded in the test report for model-matrix analysis.

### FR-006: Engineering Agent — Testing

**REQ-031.27** The engineering agent MUST write Playwright end-to-end tests
in `packages/e2e/` that exercise the palindrome happy path via the HTML
form.

**REQ-031.28** Playwright tests MUST capture screenshots at key steps
following the naming convention `{test-name}.{step-index}.{step-name}.png`.

**REQ-031.29** Screenshots MUST be committed via git LFS to the bun server
repo.

### FR-007: Engineering Agent — Release

**REQ-031.30** The engineering agent MUST merge the feature into the trunk
branch.

**REQ-031.31** The engineering agent MUST create a release PR with the
changes cherry-picked from the trunk branch.

**REQ-031.32** The engineering agent MUST comment on the milestone
referencing the merged feature PR.

**REQ-031.33** The engineering agent MUST close or complete the engineering
issue upon successful merge.

### FR-008: Product Agent — Verification

**REQ-031.34** The product agent MUST verify that git LFS screenshots in the
release PR match the live environment.

**REQ-031.35** The product agent MUST mark the milestone as complete after
verification passes.

### FR-009: Validation Checks

**REQ-031.36** The harness MUST assert that a `specs/REQ-*palindrome*` file
exists in the bun server repo with RFC 2119 key words.

**REQ-031.37** The harness MUST assert that the engineering agent's worktree
exists at the conventional path.

**REQ-031.38** The harness MUST assert that the milestone and all associated
issues reached their expected terminal states (closed or completed).

**REQ-031.39** The harness MUST assert that screenshots in the repo follow
the `{test-name}.{step-index}.{step-name}.png` naming convention.

**REQ-031.40** The harness MUST assert that the palindrome solver returns
valid JSON for known palindrome and non-palindrome inputs.

**REQ-031.41** The harness MUST assert that the release PR exists and
references the milestone.

### FR-010: Platform Abstraction

**REQ-031.42** The harness MUST define a platform interface for repo, issue,
milestone, and PR operations.

**REQ-031.43** The harness MUST implement the platform interface for Forgejo
using the Forgejo API or CLI.

**REQ-031.44** The platform interface SHOULD be extensible to GitHub in a
future iteration.

## Non-Functional Requirements

**NFR-001** The full E2E test SHOULD complete within 30 minutes on a
standard Keystone workstation.

**NFR-002** The harness MUST be idempotent — running twice in succession
MUST NOT leave stale state that causes the second run to fail.

**NFR-003** The harness MUST produce a non-zero exit code when any required
check fails.

**NFR-004** The progressive report MUST be valid YAML at any point during
execution (not just at completion).

**NFR-005** The harness SHOULD emit logfmt events to stderr for real-time
operator visibility, consistent with the task-loop pattern.
