# REQ-006: Clusters

Nix flake for deploying Kubernetes infrastructure on VPS or bare metal servers.
Extends Keystone OS (Secure Boot, TPM unlock, ZFS) to create a self-sovereign
cluster architecture centered around a "Primer Server" that bootstraps and
manages the entire cluster lifecycle.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Functional Requirements

### FR-001: Primer Server Bootstrap

The system MUST allow a user to bootstrap a Primer Server from a Keystone OS
installation using the TUI installer.

- The Primer Server MUST serve as the root of trust for the entire cluster
- The Primer Server MUST store encrypted root secrets (CA certificates, etcd encryption keys, OIDC signing keys)
- The Primer Server MUST bootstrap the initial etcd quorum
- The Primer Server MUST manage cloud provider integrations via OIDC

### FR-002: Offline Secret Storage

The Primer Server MUST store all root secrets encrypted with TPM-sealed keys,
allowing the server to go offline while the cluster continues to operate.

- All root secrets MUST be encrypted at rest using TPM-sealed keys
- ZFS snapshots MUST capture the complete system state before going offline
- The cluster MUST continue to operate independently once bootstrapped
- The Primer MUST be restorable for recovery, rotation, or expansion operations

### FR-003: ZFS Snapshot Automation

The system MUST automatically create and manage ZFS snapshots according to a
configurable retention policy.

- Hourly snapshots MUST be retained for 24 hours
- Daily snapshots MUST be retained for 7 days
- Weekly snapshots MUST be retained for 4 weeks
- Monthly snapshots MUST be retained for 12 months

### FR-004: Cloud Provider OIDC

The system MUST authenticate to cloud providers using OIDC, eliminating the
need for long-lived API credentials.

- The Primer MUST act as an OIDC identity provider
- Cloud providers MUST trust Primer-issued tokens
- All cloud operations MUST use short-lived credentials
- No static API keys SHALL be stored in the cluster

### FR-005: Kubernetes Node Scheduling

The Kubernetes operator MUST provision and manage control plane and worker
nodes across bare metal and cloud infrastructure.

- The operator MUST support control plane nodes (etcd, API server, scheduler, controller-manager)
- The operator MUST support worker nodes for executing workloads (bare metal + cloud mix)
- The operator MUST support dedicated storage nodes for Ceph OSDs
- The operator MUST handle node lifecycle (provisioning, updates, decommissioning)

### FR-006: Distributed Storage

The system MUST provide distributed block, file, and object storage via
Ceph/Rook running on ZFS.

- The system MUST provide RBD volumes for databases and stateful workloads (`ceph-block`)
- The system MUST provide CephFS for shared storage with ReadWriteMany support (`ceph-filesystem`)
- The system MUST provide S3-compatible object storage via RGW (`ceph-object`)

### FR-007: Blob Storage Integration

The system MUST integrate with cloud blob storage (S3) for backups, object
storage, and long-term retention.

- The system MUST support offsite backup of ZFS snapshots
- The system MUST support Ceph RGW backend for object storage
- The system MUST support container registry storage
- The system MUST support log and metrics long-term retention

### FR-008: Observability Stack

The system MUST deploy Grafana, Prometheus, and Loki for monitoring, alerting,
and log aggregation.

- The system MUST provide Prometheus for metrics collection and alerting
- The system MUST provide Grafana for visualization and dashboards
- The system MUST provide Loki for log aggregation and querying
- The system MUST provide pre-configured dashboards for cluster, node, pod, storage, and network metrics
- The system MUST provide default alert rules for node health, resource utilization, ZFS pool state, Ceph health, Kubernetes component failures, and certificate expiration

### FR-009: Secure Networking

All inter-node communication MUST be encrypted via WireGuard mesh (Headscale).

- All node-to-node traffic MUST be encrypted
- The mesh MUST work across NAT and firewalls
- The mesh MUST support node migration between networks
- The system MUST provide ACL-based access control
- The Primer Server MUST run the Headscale control plane

### FR-010: Ingress Options

The system MUST support both Cloudflare Tunnels and dedicated ingress nodes
for external access.

- Cloudflare Tunnels MUST support zero-trust ingress without exposing public IPs
- Dedicated ingress nodes MUST support bare metal or cloud nodes with public IPs
- The system MUST support MetalLB for bare metal environments
- The system MUST support cloud provider load balancers for cloud nodes

### FR-011: TUI Installation

The system MUST provide a terminal-based installer for guided setup of all
components.

- The installer MUST support hardware detection (disks, network, TPM, Secure Boot)
- The installer MUST support disk configuration (ZFS pool creation, encryption, TPM sealing)
- The installer MUST support network configuration (static IP / DHCP, Headscale enrollment)
- The installer MUST support cluster bootstrap (CA generation, etcd init, core component deployment)
- The installer MAY support cloud provider setup (OIDC trust, connectivity test, node pool init)
- The installer MAY support observability setup (Prometheus, Grafana, Loki deployment)

### FR-012: Air-Gap Capability

The cluster MUST continue to operate when the Primer Server is offline, with
the ability to restore from encrypted snapshots.
