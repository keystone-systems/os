# Release Context for Keystone

## Distribution model

Keystone distributes by **branch**, like nixpkgs — not by version tag.
Consumers track `main` (unstable channel) or a `release/<M>.<m>` line (stable
channel), and `ks update` follows the branch head. There is no `vX.Y.Z` tag to
cut; shipping a fix means landing it on the line. The historical `v0.x` /
`v1.0.0-rc.*` tags below remain as inert history and are not read by the update
path. See [`docs/releasing.md`](../releasing.md) for the full model. The
release-line *numbering* (`release/1.0`, `release/2.0`) still follows the semver
intent described next.

## Versioning (release-line numbering)

The ROADMAP.md originally used `v0.0.x` for feature milestones, but this is incorrect — patch-level changes are for bug/security fixes only.

**Correct mapping of ROADMAP milestones to semver:**

| ROADMAP Label         | Correct Version | Content                              |
| --------------------- | --------------- | ------------------------------------ |
| Secure Foundation     | v0.1.0          | ZFS, LUKS, TPM, Secure Boot, desktop |
| Developer Environment | v0.2.0          | Home-manager, remote dev             |
| Workstation Desktop   | v0.3.0          | Remote desktop, multi-monitor        |
| Universal Development | v0.4.0          | Portable config, Codespaces, macOS   |
| Production            | v1.0.0          | Backups, monitoring, secrets, DR     |

**Rules:**

- **Patch (0.x.Y)**: Bug fixes and security patches ONLY
- **Minor (0.Y.0)**: New features and capabilities (most milestones)
- **Major (Y.0.0)**: Breaking changes requiring migration

## Conventions

- Historical release artifacts stored in `docs/releases/[version]/` — see `docs/releases/0.1.0/` for the established pattern
- `CHANGELOG.md` at repo root follows Keep a Changelog format
- The stable line is the `release/<M>.<m>` branch (currently `release/1.0`); the starter installer ISO is published as a rolling `latest-iso` GitHub release on each `release/*` push
- v1 ship criteria live at [`docs/milestones/M9-v1-stabilization/`](../milestones/M9-v1-stabilization/)

## Last Updated

- Date: 2026-06-13
- From conversation about: switch distribution from version tags to branch tracking (nixpkgs model)
