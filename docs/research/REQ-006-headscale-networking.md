# Research: Headscale Networking

**Relates to**: REQ-006 (Clusters, FR-009)

## Decision

Self-hosted Headscale as control plane for WireGuard mesh. No external dependencies, no per-seat costs, full data sovereignty.

## Two Access Patterns

1. **Machine Access**: SSH to individual nodes via mesh (`group:admins → group:machines:22`)
2. **Cluster Access**: kubectl to API server via mesh (`group:admins → tag:primer:6443`)

## Node Registration

Pre-auth keys with machine-specific tags. Flow: Primer generates key → cloud-init bakes key → Tailscale client registers with Headscale → node receives mesh IP.

## DERP Relay

Private DERP relay on Primer for low-latency traffic within infrastructure. Public DERP fallback for edge cases (mismatched NAT types).

## Kubernetes CNI

Flannel + Headscale underlay (simplest): Flannel vxlan over WireGuard mesh. Each node advertises its Headscale IP as internal IP via `kubelet --node-ip=$(tailscale ip -4)`.

## ACL Structure

Role-based: cluster-admins (full access), developers (API + SSH), monitoring (node-exporter + kubelet metrics). Inter-node communication unrestricted.

## HA Considerations

Single Primer: if it fails, existing mesh connections persist but new registrations fail. Multi-Primer (future): shared PostgreSQL backend, multiple DERP relays.

## Key Finding

Standard Tailscale client works with Headscale via `--login-server` flag. MagicDNS provides automatic `hostname.keystone.local` resolution.
