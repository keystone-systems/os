## Version Control

## Pre-Commit Hygiene

Before committing, ensure the working tree is clean and matches the intended state. For strategic guidance on searching project history and discovering requirements using git tools, see `process.project-navigation`.

1. Before committing, the working tree MUST be checked for files that should be gitignored (e.g., `.env`, `node_modules/`, build artifacts).
2. `git status` MUST be reviewed before every commit to verify only intended files are staged.
3. Files matching `.gitignore` patterns MUST NOT be committed — if they appear in status, the `.gitignore` MUST be fixed first.

## Conventional Commits

4. Commit messages MUST follow the Conventional Commits format: `type(scope): subject`.
5. Valid types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, `perf`, `build`.
6. The scope SHOULD identify the affected area (e.g., `backend`, `frontend`, `nix`, `ci`).
7. PR titles MUST also follow the `type(scope): subject` format.
8. The subject SHOULD match an existing spec, milestone, or issue name — avoid introducing new subjects when an existing one fits.

## Commit Discipline

9. Commits MUST be early and often — each commit SHOULD represent one logical change.
10. Dependency additions or updates MUST be in their own dedicated commit (e.g., `chore(deps): add serde`).
11. When doing TDD, the failing test MUST be committed separately from the implementation that makes it pass.
12. Commits MUST NOT bundle unrelated changes — split them into separate commits.

## Cloning Repositories

15. Repos MUST be cloned to `.repos/{owner}/{repo}` relative to the agent-space root — never to the home directory or agent-space root.
16. Internal Forgejo repos MUST use SSH URLs: `git clone ssh://forgejo@git.ncrmro.com:2222/{owner}/{repo}.git .repos/{owner}/{repo}`.
17. GitHub repos MUST use `gh repo clone {owner}/{repo} .repos/{owner}/{repo}`.
18. Full clones MUST be used — do NOT use `--depth 1` unless explicitly requested.
19. The `.repos/` directory MUST be gitignored.

## Rebasing & Lock Files

For rebase conflict resolution, lockfile handling, and advanced git operations, see `process.version-control-advanced`.
