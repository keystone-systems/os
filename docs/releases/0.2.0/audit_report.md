# Release Infrastructure Audit: Keystone

**Repository**: .repos/ncrmro/keystone
**Audit Date**: 2026-03-04
**Default Branch**: main
**Target Version**: 0.2.0
**Target Commit**: 0bdc2b3 (2025-12-25)

## Version Control Structure

### Branches

| Branch                 | Purpose                         | Status                  |
| ---------------------- | ------------------------------- | ----------------------- |
| main                   | Default/unstable development    | Active                  |
| feat/007-combined      | Agent architecture feature work | Active (local)          |
| feat/007-agent-desktop | Agent desktop runtime           | Active (local)          |
| feat/rust-tui          | Rust TUI installer              | Active (local + remote) |
| spec/007-os-agents     | OS agents specification         | Active (local)          |

No release branches exist. All work flows through `main`.

### Tags & Versioning

- **Versioning scheme**: Semantic versioning (adopted with v0.1.0)
- **Latest tag**: `v0.1.0` (tagged 2026-03-03, points to commit 59ffa5f from 2025-11-08)
- **Tag pattern**: `v{major}.{minor}.{patch}`
- **Total tags**: 2 (`v0.1.0`, `latest-iso`)

Recent tags:

- `v0.1.0` — 2026-03-03 (first alpha: working desktop with encryption)
- `latest-iso` — 2025-12-12 (rolling ISO build tag)

### Semver Correctness

v0.1.0 correctly uses a minor version for the first feature release (17+ features including encrypted install, Hyprland desktop, TPM, Secure Boot). The previous `v0.0.1` tag was re-tagged as `v0.1.0` per commit `e47c4ac` ("retag v0.0.1 as v0.1.0 (correct semver for feature release)").

The proposed v0.2.0 is appropriate: it represents significant new features (four-pillar architecture consolidation, module exports, templates) without breaking changes to the v0.1.0 API.

## Existing Release Artifacts

| Artifact              | Exists | Format/Notes                                            |
| --------------------- | ------ | ------------------------------------------------------- |
| CHANGELOG.md          | Yes    | Keep a Changelog format, semver                         |
| GitHub Releases       | Yes    | 2 releases (v0.1.0 pre-release, latest-iso pre-release) |
| VERSION file          | No     | Version tracked in CHANGELOG.md only                    |
| Release docs          | No     | No RELEASING.md                                         |
| Release artifacts dir | Yes    | `releases/0.1.0/` with full artifact set                |

### CHANGELOG.md

Uses [Keep a Changelog](https://keepachangelog.com/) format with semantic versioning. Current structure:

- `[Unreleased]` section (empty)
- `[0.1.0] - 2025-11-08` with Added/Changed/Fixed categories
- Compare links at bottom

### GitHub Releases

- **v0.1.0** (pre-release, 2026-03-03): Full release notes with highlights, features, bug fixes, getting started guide
- **latest-iso** (pre-release, 2025-12-12): Rolling installer ISO build

### Release Artifacts (releases/0.1.0/)

Complete artifact set from the v0.1.0 release workflow:

- `audit_report.md` (in `_dataroom/`)
- `pre_release_announcement.md`
- `release_scope.md`
- `release_notes.md`
- `changelog_entry.md`
- `release_summary.md`

## CI/CD Platform

- **Platform**: GitHub Actions
- **Existing workflows**:
  - `test.yml` — `nix flake check` on PRs (basic flake validation)
  - `docs.yml` — Documentation workflow
  - `copilot-setup-steps.yml` — Copilot agent setup
- **Release automation**: None (no tag-triggered release workflow)
- **Release tools**: None (manual release process via DeepWork release job)

### Relevant Workflow Files

| File                                        | Trigger | Purpose                      |
| ------------------------------------------- | ------- | ---------------------------- |
| `.github/workflows/test.yml`                | PR      | `nix flake check` validation |
| `.github/workflows/docs.yml`                | Unknown | Documentation                |
| `.github/workflows/copilot-setup-steps.yml` | Unknown | Copilot setup                |

Note: The test workflow has commented-out sections for ISO build verification and installer testing (conditional on path changes). These are aspirational but not active.

## Release Channels

| Channel     | Status             | Version Pattern                             | Branch       |
| ----------- | ------------------ | ------------------------------------------- | ------------ |
| Unstable    | Active (implicit)  | Rolling                                     | main         |
| Stable      | Active (1 release) | semver: v0.1.0                              | Tags on main |
| Pre-release | Active             | v{major}.{minor}.{patch} marked pre-release | Tags on main |
| LTS         | N/A                | —                                           | —            |
| Quarterly   | N/A                | —                                           | —            |

The project currently tags releases on `main` and marks them as pre-releases on GitHub. There's no stable/release branch strategy yet — all releases come from main via tag.

## Gaps & Recommendations

### Missing Infrastructure

- **No release automation**: Releases are fully manual (tag, changelog update, GitHub release creation). A tag-triggered GitHub Action would streamline this.
- **No RELEASING.md**: The release process is encoded in the DeepWork release job but not documented in-repo for contributors.
- **v0.1.0 "What's Next" section is stale**: Lists `v0.0.2`, `v0.0.3`, `v0.0.4` — these should be updated or removed since versioning was corrected to minor versions.

### No Blockers

The existing infrastructure is sufficient for v0.2.0:

- CHANGELOG.md exists with correct format
- GitHub Releases are set up
- The release workflow (DeepWork job) is proven from v0.1.0
- Commit history between v0.1.0 and 0bdc2b3 is clean (48 commits)

### Recommended Next Steps

1. **Proceed with v0.2.0 release** — infrastructure is ready
2. **Fix stale "What's Next" in v0.1.0 release** — update to reference v0.2.0+ (low priority, cosmetic)
3. **Add tag-triggered release GitHub Action** — automate CHANGELOG update and GitHub Release creation on `v*` tags (future improvement)

### Future CI/CD Automation

A `release.yml` GitHub Action triggered on `v*` tag push could:

1. Extract the matching CHANGELOG entry
2. Create a GitHub Release with the extracted notes
3. Build and attach the installer ISO as a release asset
4. Mark as pre-release or stable based on version pattern

This is not blocking for v0.2.0 but would be valuable for v0.3.0+.

<promise>✓ Quality Criteria Met</promise>
