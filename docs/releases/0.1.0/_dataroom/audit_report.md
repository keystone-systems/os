# Release Infrastructure Audit: Keystone

**Repository**: .repos/ncrmro/keystone
**Audit Date**: 2026-03-03
**Default Branch**: main

## Version Control Structure

### Branches

| Branch             | Purpose                                                                       | Status                    |
| ------------------ | ----------------------------------------------------------------------------- | ------------------------- |
| main               | Default development branch                                                    | Active, 12 local branches |
| feat/007-combined  | Combined OS agents feature work                                               | Active, merged to main    |
| feat/007-agent-\*  | Various agent feature branches (bitwarden, desktop, email, ssh, provisioning) | Stale (pruned remotes)    |
| feat/rust-tui      | Rust TUI development                                                          | Active (remote exists)    |
| spec/007-os-agents | Spec authoring for OS agents                                                  | Stale (pruned remote)     |

Only `main` and `feat/rust-tui` have active remote tracking branches. All `feat/007-*` branches appear to be local-only remnants of completed work.

### Tags & Versioning

- **Versioning scheme**: Ad hoc — one tag exists but doesn't follow a consistent pattern
- **Latest tag**: `latest-iso`
- **Tag pattern**: No version-based tags. The single `latest-iso` tag appears to mark a specific ISO build
- **Total tags**: 1

### ROADMAP Versioning

The project has a well-defined `ROADMAP.md` using semantic versioning with a pre-1.0 numbering scheme:

- v0.1.0 — Secure Foundation (core complete, polish pending)
- v0.0.2 — Developer Environment (core complete, integration pending)
- v0.0.3 — Workstation Desktop (implemented, testing phase)
- v0.0.4 — Universal Development (planning)
- v0.1.0 — Production (future: backups, monitoring, secrets, DR)
- v0.2.0 — Infrastructure (future: k3s, services, mesh VPN)
- v0.3.0 — Enterprise (future: LDAP, compliance, audit, PKI)

This roadmap provides a natural versioning scheme to adopt for releases.

## Existing Release Artifacts

| Artifact        | Exists | Format/Notes                                                 |
| --------------- | ------ | ------------------------------------------------------------ |
| CHANGELOG.md    | No     | N/A                                                          |
| GitHub Releases | No     | No releases created                                          |
| VERSION file    | No     | No explicit version file; version is implicit from roadmap   |
| Release docs    | No     | ROADMAP.md exists with version-based milestones              |
| Spec directory  | Yes    | 7 specs in `specs/` following sequential numbering (001-007) |

## CI/CD Platform

- **Platform**: GitHub Actions
- **Existing workflows**: 3 files, all currently commented out or minimal
  - `test.yml` — Active: runs `nix flake check` on PRs (only the `flake-check` job is enabled; ISO build, installer test, and path-filtered jobs are commented out)
  - `docs.yml` — Fully commented out: Jekyll-based GitHub Pages deployment
  - `copilot-setup-steps.yml` — Fully commented out: Copilot validation
- **Release automation**: None — no tag-triggered workflows, no release publish steps
- **Release tools**: None — no semantic-release, release-please, changesets, or similar
- **Build system**: Nix flake with `nix build .#iso` for ISO builds, `Makefile` for developer convenience

### Relevant Workflow Files

| File                                        | Status           | Purpose                                |
| ------------------------------------------- | ---------------- | -------------------------------------- |
| `.github/workflows/test.yml`                | Partially active | `nix flake check` on PRs only          |
| `.github/workflows/docs.yml`                | Commented out    | Jekyll docs deployment to GitHub Pages |
| `.github/workflows/copilot-setup-steps.yml` | Commented out    | Copilot setup validation               |

## Release Channels

| Channel     | Status            | Version Pattern                | Branch                 |
| ----------- | ----------------- | ------------------------------ | ---------------------- |
| Unstable    | Active (implicit) | Rolling commits on main        | main                   |
| Stable      | Not established   | Proposed: semver (v0.0.x)      | Proposed: tags on main |
| LTS         | Not applicable    | N/A — pre-1.0 project          | N/A                    |
| Quarterly   | Not applicable    | N/A — milestone-driven roadmap | N/A                    |
| Pre-release | Not established   | Proposed: v0.0.x-beta.N        | Tags on main           |

Given the project's pre-1.0 state and milestone-driven roadmap, the most natural release model is **tag-based releases on main** following the existing v0.0.x versioning from `ROADMAP.md`. LTS and quarterly channels are not appropriate until the project reaches v1.0.

## Gaps & Recommendations

### Missing Infrastructure

- **No CHANGELOG.md**: Should adopt [Keep a Changelog](https://keepachangelog.com/) format. The project already uses conventional commits (`feat()`, `fix()`, `chore()`, `docs()`) which map naturally to changelog categories.
- **No GitHub Releases**: Need to create first release. The ROADMAP provides clear milestone definitions to scope releases.
- **No version tags**: The single `latest-iso` tag is not version-based. Need to establish `v0.0.x` tag convention.
- **No release automation**: No CI workflow for building/publishing on tag push. Currently only `nix flake check` runs on PRs.
- **Stale local branches**: 10+ local branches with pruned remotes should be cleaned up before first release.

### Strengths to Build On

- **ROADMAP.md is excellent**: Clear version-based milestones with component status tracking. This is the natural basis for release scoping.
- **Conventional commits**: Already in use (`feat(scope):`, `fix(scope):`, etc.), enabling automated changelog generation.
- **Spec-driven development**: 7 specs in `specs/` directory provide traceable feature documentation.
- **Makefile targets**: `make build-iso`, `make test`, etc. provide the building blocks for CI release workflows.
- **Nix flake**: Reproducible builds via `nix build .#iso` make release artifacts deterministic.

### Recommended Next Steps

1. **Create CHANGELOG.md** with Keep a Changelog format, retroactively documenting major milestones
2. **Tag and release v0.1.0** on main — the Secure Foundation milestone is core-complete per ROADMAP
3. **Add tag-triggered GitHub Action** that runs full test suite and creates a GitHub Release with ISO artifact
4. **Clean up stale branches** — remove local branches whose remotes are pruned

### Future CI/CD Automation

The highest-value automation for Keystone releases:

1. **Tag-triggered release workflow**: On `v*` tag push → `nix flake check` → `nix build .#iso` → create GitHub Release with ISO attachment
2. **CHANGELOG validation**: PR check ensuring `CHANGELOG.md` is updated for `feat/` and `fix/` branches
3. **ISO artifact caching**: Use Cachix or GitHub Actions cache to speed up Nix builds in CI
