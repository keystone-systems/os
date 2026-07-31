# Keystone HA Operator Specification

**Package**: `keystone-ha-operator`
**Created**: 2025-12-14
**Status**: Draft
**Technology**: Rust (kube-rs)

## Overview

The `keystone-ha-operator` is a Kubernetes operator responsible for enforcing cross-realm resource sharing policies. It manages the lifecycle of `Grant`, `Realm`, and `SuperEntity` custom resources, ensuring that workloads deployed by external entities adhere to the specified resource limits and network policies.

## Architecture

The operator is built using Rust and the `kube-rs` ecosystem. It runs as a deployment within the `keystone-system` namespace.

### Core Components

1.  **CRD Definitions**: Rust structs deriving `CustomResource` for:
    - `Grant`
    - `Realm`
    - `SuperEntity`
2.  **Controllers**:
    - **Grant Controller**: Reconciles `Grant` objects. It creates and manages underlying Kubernetes `ResourceQuota` and `NetworkPolicy` objects to enforce the grant's terms.
    - **Realm Controller**: Manages connection details and health checks for remote realms (integration with Tailscale/Headscale).
3.  **Webhook Server** (Optional/Future): For validating admission of workloads against active grants if standard Quotas are insufficient.

## Custom Resource Definitions (CRDs)

### 1. Grant

Defines a contract allowing a `grantee` to use resources from a `grantor`.

```yaml
apiVersion: keystone.io/v1alpha1
kind: Grant
metadata:
  name: alice-to-bob-compute
spec:
  grantorRealm: alice-home
  granteeRealm: bob-home
  hard:
    requests.cpu: "2"
    requests.memory: "4Gi"
    limits.cpu: "4"
    limits.memory: "8Gi"
    requests.storage: "100Gi"
  networkPolicy:
    egressAllowed: false
    allowedDestinations: []
  validity:
    validUntil: "2026-01-01T00:00:00Z"
status:
  phase: Active # Pending, Active, Revoked, Expired
  actualUsage:
    requests.cpu: "1.5"
```

### 2. Realm

Represents a known Keystone realm (local or remote).

```yaml
apiVersion: keystone.io/v1alpha1
kind: Realm
metadata:
  name: bob-home
spec:
  identity: "bob-home.tailnet-name.ts.net"
  connectionType: "tailscale"
  trustLevel: "partner" # internal, partner, public
status:
  connectionState: Connected
  lastSeen: "2025-12-14T10:00:00Z"
```

## Controller Logic

### Grant Reconciliation Loop

1.  **Watch** `Grant` resources.
2.  **Validate**: Ensure `granteeRealm` is a known/valid `Realm`.
3.  **Enforce Resources**:
    - Create/Update a Kubernetes `ResourceQuota` in the namespace dedicated to the `granteeRealm`.
    - Namespace naming convention: `guest-<realm-name>`.
4.  **Enforce Network**:
    - Create/Update a Kubernetes `NetworkPolicy` in the guest namespace.
    - Default: Deny all egress except to `localhost` and the `granteeRealm`'s ingress (if applicable).
    - If `egressAllowed: true`, allow traffic to `allowedDestinations`.
5.  **Update Status**: Reflect current usage and phase (e.g., set to `Expired` if `validUntil` is passed).

### Realm Reconciliation Loop

1.  **Watch** `Realm` resources.
2.  **Connectivity Check**: Verify reachability via Tailscale/Headscale.
3.  **Update Status**: Set `connectionState`.

## Dependencies

- `kube`: Kubernetes client and runtime.
- `k8s-openapi`: Kubernetes API definitions.
- `schemars`: JSON schema generation for CRDs.
- `tokio`: Async runtime.
- `serde`: Serialization.

## Development Plan

1.  **Project Init**: Initialize Rust project with `kube-rs`.
2.  **CRD Codegen**: Define structs and generate CRD manifests.
3.  **Controller Implementation**:
    - Implement `Grant` controller logic.
    - Implement `ResourceQuota` mapping.
    - Implement `NetworkPolicy` mapping.
4.  **Integration Testing**: Run against a local k3s cluster.
