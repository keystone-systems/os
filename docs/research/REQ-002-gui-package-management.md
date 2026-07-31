# Research: GUI-Driven Package Management with Git Automation

**Relates to**: REQ-002 (Keystone Desktop)

## Concept

Abstract the "edit config → git commit → push → nixos-rebuild" loop into a GUI with Install/Uninstall buttons.

## Architecture

1. User clicks Install in GUI
2. Backend modifies a structured `gui-packages.nix` (not arbitrary Nix code)
3. Git commit with conventional commit format (`feat(pkg): install firefox`)
4. Git push to configured remote
5. `nixos-rebuild switch --flake .#<host>`
6. On failure: revert commit, restore config, notify user

## Key Decisions

- **Config editing**: Maintain a separate structured file (`gui-packages.nix` or JSON) imported by main config. Avoids programmatically editing arbitrary Nix.
- **Commit format**: Conventional Commits with `Keystone-Managed: true` trailer for distinguishing GUI vs manual edits.
- **Conflict handling**: Always `git pull --rebase` before changes. Abort and notify on conflict.
- **Validation**: Run `nix-instantiate --parse` before committing to catch syntax errors.

## Risks

| Risk             | Mitigation                                    |
| ---------------- | --------------------------------------------- |
| Concurrent edits | File locking, check git status before writes  |
| Broken config    | Validate syntax before commit                 |
| Network failure  | Queue pushes for later, allow local operation |
| Auth failure     | Check SSH/Git credentials on startup          |
