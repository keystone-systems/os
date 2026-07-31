# REQ-001: Keystone OS

Reproducible, secure operating system distribution deployable to any hardware
with full disk encryption, automatic hardware-based unlock, and mesh network
integration.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Functional Requirements

### FR-001: Declarative Configuration

The system configuration MUST be fully declarative and reproducible.

- All system state MUST be defined in version-controllable expressions
- The same configuration MUST produce identical systems across deployments
- The system MUST produce a single output per target system configuration
- Configuration changes MUST be applied atomically with rollback capability

### FR-002: Full Disk Encryption

All user data MUST be encrypted at rest.

- Storage volumes MUST be encrypted before any user data is written
- Encryption keys MUST NOT be stored in plaintext on disk
- Key material MUST be protected by hardware security module when available
- The system MUST provide a fallback authentication method when hardware security is unavailable
- Swap space MUST be encrypted with ephemeral keys

### FR-003: Automatic Unlock

Systems MUST unlock automatically when boot integrity is verified.

- No manual password entry SHALL be required under normal boot conditions
- Unlock MUST be bound to verified boot state measurements
- Automatic unlock MUST fail safely if boot integrity is compromised
- The system MUST provide clear notification when manual unlock is required
- The system MUST provide a first-boot enrollment workflow for hardware security binding

### FR-004: Verified Boot Chain

The boot process MUST be cryptographically verified from firmware to userspace.

- Custom signing keys MUST be enrolled for platform ownership
- Boot artifacts MUST be signed and verified at each stage
- Tampering with boot components MUST prevent automatic unlock
- The system MUST support firmware in "setup mode" during initial deployment
- The system MUST support transition from setup mode to user mode after key enrollment

### FR-005: Copy-on-Write Storage

The filesystem MUST support efficient snapshots and data integrity when ZFS is selected.

- The system MUST provide point-in-time snapshots without performance penalty
- The system MUST provide automatic data compression
- The system MUST provide data integrity verification (checksums)
- The system MUST provide remote replication capability for backups
- The system MUST support per-dataset configuration (quotas, compression, snapshots)

### FR-006: Storage Backend Selection

The system MUST support two storage backends:

| Type   | Use Case             | Features                                              |
| ------ | -------------------- | ----------------------------------------------------- |
| `zfs`  | Default, recommended | Snapshots, compression, checksums, encryption, quotas |
| `ext4` | Laptops, hibernation | LUKS encryption, minimal overhead, wide compatibility |

- When `ext4` is selected, the system MUST use LUKS encryption directly on the partition
- When `ext4` is selected, the system MUST support hibernation via persistent swap
- The system MUST support single and multi-disk configurations
- Multi-disk ZFS configurations MUST support modes: single, mirror, stripe, raidz1, raidz2, raidz3
- Partition sizes (ESP, swap, credstore) MUST be configurable

### FR-007: Remote Installation

Systems MUST be deployable to any SSH-accessible target.

- The system MUST support deployment over network to a running system (kexec-based)
- The system MUST support bootable installer media generation with SSH key injection
- Disk partitioning MUST be defined declaratively and applied automatically
- The system MUST support injecting additional files during deployment
- Installation progress MUST be observable via SSH

### FR-008: Mesh Network Client

Systems MUST be able to join private mesh networks.

- The system MUST automatically connect to a coordination server on first boot
- Node discovery MUST work without manual IP configuration
- The system MUST provide secure remote access without port forwarding or NAT traversal
- The system MUST provide DNS-based node resolution within the mesh
- The system MUST provide exit node capability for routing traffic through specific nodes

### FR-009: Mesh Network Server

Systems MUST be able to host mesh network coordination services.

- The system MUST support a self-hosted coordination server for mesh network
- The system MUST provide node authentication and authorization management
- The system MUST provide access control list (ACL) configuration
- The system MUST provide DNS integration for automatic node name resolution
- The system MUST provide a web-based administration interface

### FR-010: Server Role

The system MUST support always-on server configurations.

- The system MUST support headless operation without display manager
- SSH access MUST be enabled by default
- The system MUST support service discovery via multicast DNS (mDNS)
- The system MUST provide a firewall with secure defaults
- The system MUST support network gateway, DNS, and storage services

### FR-011: Workstation Role

The system MUST support interactive desktop workstation configurations.

- The system MUST provide a graphical desktop environment with compositor
- The system MUST provide a display manager with auto-login capability
- The system MUST provide an audio system with application mixing
- The system MUST provide network management with graphical interface
- The system MUST support Bluetooth connectivity
- The system MUST provide a terminal development environment (editor, shell, multiplexer)

### FR-012: Testing via Flake Checks

All system features MUST be testable via standard flake check mechanism.

- Tests MUST be runnable with `nix flake check`
- The system MUST support virtual machine-based testing for system configurations
- The system MUST support hardware security emulation for TPM-dependent features
- The system MUST support Secure Boot verification in emulated environment
- Tests MUST support headless execution for CI/CD pipelines

### FR-013: Identity & UID Management

The system MUST enforce a clear partition between human users, service accounts, and AI agents through reserved UID ranges.

- **Human Users**: MUST use the standard range `1000 - 2999`.
- **Service Accounts**: MUST use the range `3000 - 3999`. This range is reserved for system services that require `isNormalUser = true` for features like rootless Podman subuids or systemd linger (e.g., Forgejo runners).
- **AI Agents**: MUST use the range `4000+`.
- The system MUST ensure that UIDs are assigned deterministically within these ranges to maintain stable file ownership across deployments.
- A NixOS assertion SHOULD verify that no UID collisions exist between these partitions.

## Non-Functional Requirements

### NFR-001: Reproducibility

- Identical inputs MUST produce identical outputs
- All dependencies MUST be pinned to specific versions
- The build MUST NOT rely on external state
- Offline builds MUST be possible with cached dependencies

### NFR-002: Security Posture

- The system MUST implement defense in depth with multiple security layers
- The system MUST maintain a minimal attack surface with only required services enabled
- Secure defaults MUST require explicit opt-out
- Production configurations MUST NOT have default passwords
- Secrets MUST NOT be committed to version control

### NFR-003: Observability

- Installation progress MUST be visible with detailed logging
- The boot process MUST be debuggable via serial console
- System logs MUST be aggregated and queryable
- Health metrics MUST be exportable for monitoring
- Error messages MUST include remediation guidance

## Testing Requirements

### TR-001: Fast Iteration Testing

Tests for rapid configuration development without full security stack.

- Quick virtual machine builds MUST complete in under 2 minutes
- Tests MUST NOT require disk encryption or verified boot overhead
- Tests MUST provide SSH access for interactive debugging
- Tests SHOULD support persistent disk state between runs
- Both headless (terminal) and graphical (desktop) modes MUST be supported

### TR-002: Full Stack Testing

Tests for complete deployment including all security features.

- Tests MUST include hardware security module emulation
- Tests MUST include verified boot in emulated UEFI environment
- Tests MUST verify full disk encryption with automatic unlock
- Tests MUST support end-to-end deployment via remote installation
- Tests MUST include post-deployment security state validation

### TR-003: Module Testing

Tests for individual module functionality.

- Tests MUST verify service startup
- Tests MUST validate configuration options
- Tests MUST cover module interaction
- Tests MUST support regression testing for module changes

## Success Criteria

### SC-001: Deployment Success

- Fresh system MUST be deployable from ISO in under 30 minutes
- Remote deployment to SSH target MUST complete in under 15 minutes
- First boot MUST complete without manual intervention (after hardware enrollment)

### SC-002: Security Verification

- Disk contents MUST be unreadable without proper authentication
- Boot tampering MUST be detected and automatic unlock prevented
- Hardware security enrollment MUST complete in under 5 minutes

### SC-003: Network Integration

- Mesh network connection MUST be established within 60 seconds of boot
- Node MUST be discoverable by hostname within mesh network
- Remote access MUST be functional without port forwarding

### SC-004: Test Coverage

- All functional requirements MUST have corresponding flake checks
- Tests MUST complete in under 30 minutes total
- Test failures MUST produce actionable diagnostics

## Out of Scope

- Automated backups: ZFS snapshot scheduling and remote replication automation
- Monitoring stack: Prometheus, Grafana, alerting infrastructure
- Multi-host deployment: Orchestrated deployment across multiple systems
- Container orchestration: Kubernetes/k3s integration
- Distributed storage: Ceph, GlusterFS, or similar
- Enterprise features: LDAP/AD integration, compliance automation, audit logging
- Laptop-specific features: Suspend/hibernate, battery management, lid switch handling
- Multi-GPU configurations: Complex graphics setups, GPU passthrough
