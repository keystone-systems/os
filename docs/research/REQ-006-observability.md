# Research: Observability Stack

**Relates to**: REQ-006 (Clusters, FR-008)

## Stack

| Component              | Role                                                                     |
| ---------------------- | ------------------------------------------------------------------------ |
| kube-prometheus-stack  | Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics |
| Loki (Simple Scalable) | Log aggregation with S3/Ceph RGW backend                                 |
| Grafana Alloy          | Unified collection agent (replaces Promtail) — logs, metrics, traces     |

## Key Decisions

| Decision                  | Rationale                                                                         |
| ------------------------- | --------------------------------------------------------------------------------- |
| Loki Simple Scalable mode | Handles up to 100GB/day, separates read/write paths, simpler than microservices   |
| Alloy over Promtail       | Unified agent for logs+metrics+traces, active development, component-based config |
| Dashboard provisioning    | Dashboards-as-code via ConfigMap with `grafana_dashboard: "1"` label              |

## Retention

- **Metrics**: 15 days local (ceph-block PVC), ~2GB/day for small cluster
- **Logs**: 7 days hot (ingesters), 90 days cold (S3/Ceph RGW), ~10GB/day for small cluster

## Keystone-Specific Alert Rules

- `ZFSPoolDegraded`: ZFS pool state != online (critical, 5m)
- `CephHealthWarning`: Ceph health status WARN (warning, 5m)
- `HeadscaleNodeOffline`: Node offline (warning, 5m)
- `PrimerServerUnreachable`: Primer down (critical, 2m)

## Alert Routing

Severity-based: critical → PagerDuty, warning → Slack, Watchdog/InfoInhibitor → null.

## Resource Overhead

~2-4GB RAM total for small cluster: Prometheus 1GB, Loki 1GB, Grafana 512MB, Alloy 256MB per node.
