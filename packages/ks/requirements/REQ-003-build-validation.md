# REQ-003: Build and end-to-end validation

This document defines the automated validation contract for ks.
It covers generated configuration evaluation, generated configuration builds,
installer ISO generation, installer-mode end-to-end validation, and
post-install first-boot validation.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Requirements

### Test Infrastructure

**REQ-003.1** The test MUST be a Nix derivation importable as a flake check
via `checks.x86_64-linux.template-evaluation`.

**REQ-003.2** The test MUST provide a `mkTemplateConfig` helper function
that accepts the same data model inputs as REQ-002 and produces a NixOS
module importing `keystone.nixosModules.operating-system`.

**REQ-003.3** The `mkTemplateConfig` helper MUST mirror the configuration
structure that the TUI will generate, ensuring the test validates the same
output contract.

### Template evaluation coverage

**REQ-003.4** The test MUST include at least 4 distinct configuration
variants covering: single-disk ZFS, multi-disk ZFS mirror, single-disk
ext4, and ZFS with desktop module.

**REQ-003.5** Each test configuration MUST evaluate successfully via
`nixpkgs.lib.nixosSystem` without errors.

**REQ-003.6** Each test configuration MUST force deep evaluation by
serializing `users.users`, `users.groups`, and `systemd.services` via
`builtins.toJSON`.

### Output

**REQ-003.7** The test derivation MUST write inspectable JSON output to
`$out/<config-name>.json` for each test configuration, containing at
minimum `users`, `groups`, and `services` keys.

**REQ-003.8** The test output SHOULD be examinable via
`nix build .#template-evaluation && cat result/<config-name>.json`.

### Generated config and ISO validation

**REQ-003.9** The test suite MUST validate that representative generated
server, laptop, and workstation configurations evaluate successfully
against the local Keystone modules.

**REQ-003.10** The test suite SHOULD build representative generated
server, laptop, and workstation configurations to catch missing packages
and broken derivations.

**REQ-003.11** The test suite MUST validate that the base Keystone
installer ISO is buildable from the local repository.

**REQ-003.12** The test suite MUST validate that a pre-baked installer ISO
containing generated TUI output evaluates successfully.

**REQ-003.13** The test suite SHOULD build a pre-baked installer ISO
containing generated TUI output into a real ISO artifact.

### Installer-mode end-to-end validation

**REQ-003.14** The automated validation contract MUST include a VM-based
end-to-end test that simulates installer mode by providing
`/etc/keystone/install-config/` to the TUI environment.

**REQ-003.15** The installer-mode test MUST verify that mode detection
selects the install flow when `/etc/keystone/install-config/` is present.

**REQ-003.16** The installer-mode test MUST verify that the install flow
copies `flake.nix`, `configuration.nix`, and `hardware.nix` into
`~/repos/<user>/keystone-config/` for the installed user.

**REQ-003.17** The installer-mode test MUST verify that the install flow
creates `~/repos/<user>/keystone-config/.first-boot-pending`.

**REQ-003.18** The installer-mode test MUST verify that the copied repo
content is owned by the installed user.

**REQ-003.19** The installer-mode test MUST verify that embedded
`/etc/keystone/install-config/` content is copied into a writable staged
directory distinct from the embedded source before disk selection or
installation begins.

**REQ-003.20** The installer-mode test MUST verify that when the
generated config contains `__KEYSTONE_DISK__`, selecting a disk updates
the staged config copy rather than the embedded
`/etc/keystone/install-config/` tree.

### Post-install first-boot validation

**REQ-003.21** The automated validation contract MUST include a post-install
test that verifies first-boot mode is selected when
`~/repos/<user>/keystone-config/.first-boot-pending` exists.

**REQ-003.22** The first-boot validation MUST verify that the TUI can
generate a hardware reconciliation plan before writing any files.

**REQ-003.23** The first-boot validation SHOULD cover both a no-change case
and a changes-detected case.

### Real ISO boot validation

**REQ-003.24** The automated validation contract SHOULD include a slower
full-VM test that boots a generated pre-baked installer ISO.

**REQ-003.25** The real ISO boot test SHOULD verify boot into installer
mode, successful installation, reboot into the installed system, and
activation of first-boot mode.

**REQ-003.26** The real ISO boot test MUST NOT be required in default
per-PR CI.

**REQ-003.27** The real ISO boot test SHOULD be exposed as an on-demand
validation path for release-style verification.

### Integration and execution surfaces

**REQ-003.28** The fast validation layer MUST be includable in
`nix flake check` so CI can automatically validate template configs and
other non-boot-heavy checks on every commit.

**REQ-003.29** The test suite MUST provide a clear developer entrypoint for
template evaluation, generated-config validation, and ISO generation
validation.

**REQ-003.30** Slow VM-based installer-mode and real ISO boot tests SHOULD
be available through explicit, separate commands so developers can run them
on demand without invoking them accidentally.

## Current status

The current implementation in this worktree provides strong local test
coverage for TUI logic, but it does not yet satisfy the full VM-backed
end-to-end contract above.

- Current crate unit tests: `155`
- Current config-generation integration tests: `4`
- Current multi-screen flow tests: `6`
- Current render snapshot tests: `10`
- Current ignored Nix-backed integration tests: `9`
- Current visible VM-based installer-mode end-to-end tests in this worktree: `0`

These counts are informative only and MUST NOT be treated as the long-term
validation contract.
