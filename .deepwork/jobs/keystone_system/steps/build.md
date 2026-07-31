# Build

## Objective

Verify the changes are correct using the fastest possible feedback loop. Only escalate to full system builds when necessary.

## Task

Run targeted, fast verification first. Escalate to broader builds only when the change scope requires it. The goal is rapid iteration — don't wait minutes for a full rebuild when a 5-second check will catch the issue.

### Process

1. **Targeted verification first (seconds)**
   - **Shell scripts**: Run `shellcheck` on any modified `.sh` files
   - **Nix syntax** (`.nix` files only): Run `nix-instantiate --parse` on individual changed `.nix` files to catch syntax errors
   - **Unit tests**: If `tests/module/` has relevant test files, run them individually:
     `nix eval --file tests/module/agent-evaluation.nix --json` (fast, no build)
   - Fix any errors found at this level before proceeding

2. **Evaluation check (10-30 seconds)**
   - Run `nix flake check --no-build`
   - This evaluates all NixOS configurations and checks assertions without building derivations
   - If this fails, the issue is in the Nix evaluation — fix it and re-check
   - If this fails, call `go_to_step` with `step_id: "implement"` to fix

3. **Build check (only if needed)**
   - **Home-manager-only changes**: Run `ks build` (builds home-manager profiles, no sudo, ~30s)
   - **OS-level changes**: The full system build happens during `ks update --lock` in deploy. Do NOT attempt a full nixos-rebuild here — it's slow and requires sudo
   - For OS changes, `nix flake check --no-build` passing is sufficient for this step

4. **Evaluate results**
   - If all checks pass: proceed to merge
   - If targeted checks or eval fails: call `go_to_step` with `step_id: "implement"` to fix
   - Document all output including warnings

**Maximum loop iterations**: If this is the 3rd build failure, stop looping and ask the user for guidance.

## Output Format

### build_result.md

```markdown
# Build Result

## Change Scope

- **Type**: [OS-level | home-manager-only | both]
- **Modified files**: [list of key files changed]

## Targeted Checks

| Check              | Status        | Time |
| ------------------ | ------------- | ---- |
| shellcheck [file]  | PASS/FAIL/N/A | Xs   |
| nix parse [file]   | PASS/FAIL     | Xs   |
| module test [test] | PASS/FAIL/N/A | Xs   |

## Evaluation Check

- **Command**: `nix flake check --no-build`
- **Status**: [PASS | FAIL]
- **Time**: [Xs]
- **Errors**: [none | error details]

## Build Check

- **Command**: [ks build | skipped — OS changes build at deploy]
- **Status**: [PASS | FAIL | SKIPPED]
- **Time**: [Xs]
- **Warnings**: [notable warnings, or "none beyond upstream deprecations"]

## Decision

- **Proceed to merge**: [yes | no — loop back to implement]
```

## Quality Criteria

- Targeted checks (shellcheck, nix parse) pass on all modified files
- `nix flake check --no-build` passes without errors
- For home-manager-only changes, `ks build` also passes
- The build strategy matches the change scope

## Context

Speed matters here. The develop workflow is designed for rapid iteration. A 5-second shellcheck or nix parse catches most errors instantly. The 30-second `nix flake check --no-build` catches evaluation issues. Only home-manager changes need `ks build` — OS changes get their full build during deploy. Don't make the developer wait for a full system rebuild when faster feedback is available.
