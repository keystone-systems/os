## Coding Subagent

## Usage

`bin/agent.coding-agent` orchestrates coding tasks in repos under `.repos/`. The script handles all git operations procedurally (branching, pushing, PR creation, review comments, marking ready). The LLM only handles actual coding and code review.

```bash
# Basic usage
bin/agent.coding-agent --repo ncrmro/catalyst --task "Add login page"

# With explicit branch and model
bin/agent.coding-agent --repo ncrmro/catalyst --branch fix/login-bug \
  --provider claude --model sonnet --task "Fix null pointer in login handler"

# Skip review, just create draft PR
bin/agent.coding-agent --repo ncrmro/catalyst --task "Add README" --skip-review

# Review an existing PR
bin/agent.coding-agent --repo ncrmro/catalyst --review-only 42
```

## Rules

1. The target repo MUST already be cloned to `.repos/OWNER/REPO` before invoking the coding agent.
2. Branch naming MUST use `prefix/slug` format (`feature/`, `fix/`, `chore/`, `refactor/`, `docs/`).
3. The coding agent MUST NOT perform git operations (branching, pushing, PR creation) — the script handles these.
4. Provider scripts are located at `bin/agent.coding-agent.{claude,codex,gemini}`.
5. Review uses sonnet by default; coding uses the provider default or `--model` override.
6. A maximum of 2 review/fix cycles is the default; after that the PR stays as draft.
7. After completion, the repo MUST be returned to the default branch.
