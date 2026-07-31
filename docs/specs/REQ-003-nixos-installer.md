# REQ-003: NixOS Installer TUI

Guided terminal installer for Keystone that deploys a NixOS system (server or
client) onto a target disk with minimal prompts.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Functional Requirements

### FR-001: Startup

The installer MUST present network status and MUST block progression until
basic connectivity is confirmed (or provide a clear retry path).

### FR-002: Install Methods

The installer MUST offer at least "Local installation" (on this machine). The
installer MAY provide stubs for remote/clone flows as future options.

### FR-003: Disk Enumeration

The installer MUST enumerate installable disks and MUST surface size/model
hints for each disk.

### FR-004: Disk Confirmation

The installer MUST confirm destructive actions before proceeding with disk
operations.

### FR-005: Disk Modes

The installer MUST support an unencrypted ext4 path. The installer SHOULD
support an encrypted ZFS/LUKS flow.

### FR-006: Disk Mounting

The installer MUST use generated disko configs. Target mounts MUST land at
`/mnt` for subsequent steps.

### FR-007: Identity Inputs

The installer MUST collect hostname, username, and password with validation
and confirmation.

### FR-008: System Role

The installer MUST allow choosing server vs client module set for the
generated flake config.

### FR-009: Config Generation

The installer MUST produce flake + host files, disko config(s), and hardware
configuration under `/mnt/home/<user>/nixos-config`.

### FR-010: Install Execution

The installer MUST run `nixos-install` with the generated flake, MUST set
the user password, and MUST log all operations to `/tmp/keystone-install.log`.

### FR-011: Logging/UX

The installer MUST stream progress and errors. The installer MUST provide a
tail of the install log on failure.

## Non-Functional Requirements

### NFR-001: Automated Testing

The full happy path MUST run headlessly in VM tests via `./bin/test-installer`.
Failures MUST exit non-zero and print diagnostic tails.

### NFR-002: Determinism

The installer MUST NOT rely on external state. Network checks MAY use a simple
local IP presence test.

### NFR-003: Observability

All operations (partitioning, mounts, config moves, install) MUST be logged
with timestamps to `/tmp/keystone-install.log`.

### NFR-004: Resilience

If automatic mounts fail, the installer MUST surface clear errors and MUST
continue logging to aid debugging.

## Out of Scope

- Secure Boot/TPM2 flows during install
- Remote/clone install workflows beyond stubs
- Post-install reboot orchestration
