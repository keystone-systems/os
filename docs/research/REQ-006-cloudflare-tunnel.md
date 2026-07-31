# Research: Cloudflare Tunnel for Ingress

**Relates to**: REQ-006 (Clusters, FR-010)

## Decision

Use `cloudflared` as Kubernetes Deployment with ConfigMap-based ingress rules. No inbound ports required — all connections outbound to Cloudflare edge.

## Why Cloudflare Tunnel

- No public IP or open inbound ports needed
- DDoS protection included
- TLS termination handled by Cloudflare
- Works behind NAT, CGNAT, or restrictive firewalls
- Zero-trust access policies via Cloudflare Access (SSO + per-service policies)

## Deployment Pattern

- 2+ `cloudflared` replicas with pod anti-affinity for HA
- Tunnel credentials stored as Kubernetes Secret
- Ingress rules in ConfigMap mapping hostnames to cluster services
- Catch-all rule returns 404

## Setup Flow

```bash
cloudflared tunnel login
cloudflared tunnel create keystone-cluster
kubectl create secret generic cloudflared-credentials --from-file=credentials.json
cloudflared tunnel route dns keystone-cluster grafana.keystone.example.com
```

## Hybrid Approach (Recommended)

- Cloudflare Tunnel for most services (simplicity, DDoS protection)
- Dedicated ingress nodes for specific high-performance or compliance needs
- Both can coexist in the same cluster

## Monitoring

`cloudflared` exposes Prometheus metrics at `:2000` — request count, error rate, latency. Create ServiceMonitor for automatic scraping.

## Gotchas

- Tunnel credential rotation: create new tunnel, update Secret, rolling restart
- Supports TCP/UDP via `cloudflared access tcp` (Spectrum for paid features)
- Latency overhead: 10-50ms depending on Cloudflare edge proximity
