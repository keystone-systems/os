# Keystone HA TUI Client Specification

**Package**: `keystone-ha-tui-client`
**Created**: 2025-12-13
**Status**: Draft
**Technology**: Rust with ratatui

## Overview

A terminal user interface for managing cross-realm resource sharing between Keystone clusters. Enables users to create grants, connect to other realms, deploy workloads, and manage distributed storage.

## Primary Workflows

### 1. Grant Management

#### Create a New Grant

Allow another entity to use resources on your infrastructure.

**Flow**:

1. Select "Create Grant" from main menu
2. Enter grantee realm identifier (Tailscale/Headscale domain or manual ID)
3. Configure resource limits:
   - CPU cores (slider or numeric input)
   - Memory (MB/GB)
   - Storage (GB)
   - Bandwidth (Mbps)
4. Configure network policy:
   - Egress allowed? (yes/no toggle)
   - If yes: specify allowed destinations (CIDR blocks or realm IDs)
5. Set validity period (optional expiration)
6. Review and confirm
7. Share grant token with grantee (display + copy to clipboard)

**Options** (following Kubernetes ResourceQuota pattern):
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| requests.cpu | string | "1" | CPU requests limit |
| requests.memory | string | "1Gi" | Memory requests limit |
| limits.cpu | string | "2" | CPU limits |
| limits.memory | string | "2Gi" | Memory limits |
| requests.storage | string | "10Gi" | Storage requests limit |
| requests.nvidia.com/gpu | int | 0 | GPU requests limit |
| Egress Allowed | bool | false | Allow outbound traffic beyond requesting realm |
| Allowed Destinations | list | [] | If egress allowed, which destinations |
| Expires | datetime | none | Optional grant expiration |

#### View/Revoke Grants

**Flow**:

1. Select "My Grants" from main menu
2. View list of active grants (granted by you)
3. Select a grant to view details or revoke
4. Confirm revocation (warns about active workloads)

---

### 2. Realm Connection

#### Connect to Another Realm (Accept Grant)

Use resources granted to you by another entity.

**Flow**:

1. Select "Connect Realm" from main menu
2. Enter connection method:
   - **Tailscale/Headscale**: Enter their machine name or IP on shared tailnet
   - **Direct**: Enter grant token received out-of-band
3. System validates connection and grant
4. Connected realm appears in "Available Realms" for workload placement

**Connection Options**:
| Method | Input Required | Notes |
|--------|----------------|-------|
| Tailscale Domain | `hostname.tailnet-name.ts.net` | Requires shared tailnet |
| Headscale Domain | `hostname.headscale.example.com` | Requires shared Headscale server |
| Grant Token | Base64 encoded token | For manual exchange |

#### View Connected Realms

**Flow**:

1. Select "Connected Realms" from main menu
2. View list showing:
   - Realm name/ID
   - Grantor identity
   - Resource limits
   - Current usage
   - Network policy (egress status)
3. Disconnect option per realm

---

### 3. Workload Deployment

#### Deploy Workload to Remote Realm

**Flow**:

1. Select "Deploy Workload" from main menu
2. Select target realm (your own or connected remote)
3. Configure workload:
   - Container image (OCI reference)
   - Resource requests (must be within grant limits)
   - Environment variables
   - Port mappings
4. Review network policy constraints (shown from grant)
5. Deploy and monitor status

---

### 4. Super Entity Management

#### Form Super Entity

Create shared infrastructure with other entities (e.g., family backup pool).

**Flow**:

1. Select "Super Entities" → "Create New"
2. Enter name and purpose
3. Add member realms (by domain/ID)
4. Each member must approve via their TUI
5. Once all approve, super entity is active
6. Configure shared resources:
   - Storage pool (Ceph/ZFS)
   - Backup policy
   - Replication factor

#### Contribute to Super Entity

**Flow**:

1. Select super entity from list
2. Select "Contribute Resources"
3. Choose storage device/pool to contribute
4. Confirm contribution

---

### 5. Backup Verification

#### View Backup Status

**Flow**:

1. Select "Backups" from main menu
2. View backup sets:
   - Local backups
   - Super entity distributed backups
3. Per backup: copy count, locations, last verified
4. Trigger manual verification

---

## Screen Structure

```
┌─────────────────────────────────────────────────┐
│  Keystone Cross-Realm Manager                   │
├─────────────────────────────────────────────────┤
│                                                 │
│  [1] Grant Management                           │
│      • Create Grant                             │
│      • View My Grants                           │
│                                                 │
│  [2] Realm Connections                          │
│      • Connect to Realm                         │
│      • View Connected Realms                    │
│                                                 │
│  [3] Workloads                                  │
│      • Deploy Workload                          │
│      • View Running Workloads                   │
│                                                 │
│  [4] Super Entities                             │
│      • Create Super Entity                      │
│      • View My Super Entities                   │
│                                                 │
│  [5] Backups                                    │
│      • View Backup Status                       │
│      • Verify Backups                           │
│                                                 │
│  [q] Quit                                       │
│                                                 │
└─────────────────────────────────────────────────┘
```

## Key Interactions

### Keyboard Navigation

- Arrow keys / j,k: Navigate lists
- Enter: Select/confirm
- Esc: Back/cancel
- Tab: Next field in forms
- q: Quit (with confirmation if changes pending)

### Grant Token Format

When sharing grants out-of-band, the TUI generates a shareable token:

```
keystone-grant://v1/<base64-encoded-grant-data>
```

Users can paste this token or scan a QR code (if terminal supports).

## Technologies

- **Language**: Rust
- **TUI Framework**: ratatui
- **Async Runtime**: tokio
- **Network**: Tailscale/Headscale client integration
- **Kubernetes Client**: kube-rs for CRD interaction
- **Config Storage**: Local kubeconfig + Kubernetes API

## Success Criteria

- User can create and share a grant in under 2 minutes
- User can connect to a remote realm in under 1 minute
- All screens navigable via keyboard only
- Clear feedback on grant limits and policy constraints
