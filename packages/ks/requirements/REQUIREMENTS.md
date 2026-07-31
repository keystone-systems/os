# Requirements Index

| ID | Title | Phase | File |
|----|-------|-------|------|
| REQ-001 | Config Generation | 1 | [REQ-001-config-generation.md](REQ-001-config-generation.md) |
| REQ-002 | Template Data Model | 1 | [REQ-002-template-data-model.md](REQ-002-template-data-model.md) |
| REQ-003 | Build and End-to-End Validation | 1 | [REQ-003-build-validation.md](REQ-003-build-validation.md) |
| REQ-004 | User Input | 2 | [REQ-004-user-input.md](REQ-004-user-input.md) |
| REQ-005 | Publishing | 2 | [REQ-005-publishing.md](REQ-005-publishing.md) |
| REQ-006 | Remote Connection | 3 | [REQ-006-remote-connection.md](REQ-006-remote-connection.md) |
| REQ-007 | Template Command | 2 | [REQ-007-template-command.md](REQ-007-template-command.md) |
| REQ-008 | Onboarding Journey | 1-3 | [REQ-008-onboarding-journey.md](REQ-008-onboarding-journey.md) |

## Phases

- **Phase 1** (foundation): Config generation contract, data model, and the
  automated validation contract for generated configs and ISO artifacts.
  Establishes what the TUI must produce and how that output is validated.
- **Phase 2**: Interactive TUI, CLI subcommands with JSON I/O, template
  scaffolding, git/GitHub publishing, ISO build + burn. Builds on Phase 1.
- **Phase 3**: Remote connection, mDNS discovery, nixos-anywhere deployment,
  first-boot security enrollment, secrets + services onboarding.
