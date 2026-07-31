# Convention: Grafana dashboard development (process.grafana-dashboard-development)

Standards for designing, storing, provisioning, and iterating on Grafana
dashboards in keystone. This convention defines the dashboard source-of-truth
model, the rapid-development path for `keystone.development`, and the telemetry
contract needed to build drill-down dashboards for hosts, agents, ZFS backups,
and future keystone services.

## Dashboard source of truth

1. Grafana dashboards managed by keystone MUST be stored as checked-in JSON
   files in the keystone repository, not authored only through ad hoc edits in
   the Grafana UI.
2. Dashboard JSON files MUST live in a repo directory owned by the subsystem
   they describe, or in a shared observability dashboard directory when they
   span multiple subsystems.
3. Every provisioned dashboard JSON file MUST declare a stable `uid`, `title`,
   `tags`, and `refresh` value so links and drill-downs remain stable across
   rebuilds and imports.
4. Dashboard filenames SHOULD be lowercase-hyphenated and SHOULD match the
   dashboard `uid` when practical.
5. A dashboard generated or modified in the Grafana UI MUST be exported back to
   the checked-in JSON source before the change is considered complete.

## Provisioning and development mode

See `process.keystone-development-mode` for the generic path-resolution rules
that apply to all repo-backed assets in development mode.

6. Nix modules that provision Grafana dashboards MUST treat the checked-in JSON
   files as the canonical input and MUST provision them through
   `services.grafana.provision.dashboards`.
7. The `keystone.server.services.grafana.extraDashboardPaths` option SHOULD be used
   to provision non-keystone dashboards. It supports both simple directory paths
   and complex provider attribute sets (e.g., for dashboards sourced via `linkFarm`
   or `fetchurl`).
8. When `keystone.development = true`, keystone-managed dashboards MUST use the
   CLI/API sync path rather than Grafana file provisioning.
9. In development mode, the built-in keystone dashboard set MUST NOT be added
   to `services.grafana.provision.dashboards`. Non-keystone dashboard providers
   MAY remain provisioned through host-specific config.
10. Dashboard development flows MUST preserve the locked-build behavior from
   `process.keystone-development-mode` when `keystone.development = false`;
   development mode MUST only change path resolution and iteration speed.
11. The repo MUST provide a documented dashboard iteration path, such as a
    helper command, development-mode provisioning path, or API-driven import
    flow, that lets a developer edit repo JSON and apply the changed dashboard
    to Grafana without rebuilding unrelated services.
12. If a rapid-apply helper imports dashboards through the Grafana API or
    Grafana MCP, it MUST still write back to the checked-in JSON source and
    MUST NOT create a second, unmanaged source of truth.

## Datasources and query model

See `os.zfs-backup` for the concrete ZFS metrics and health signals that host
dashboards are expected to consume.

12. Keystone dashboards MUST prefer Grafana datasources backed by Prometheus and
    Loki.
13. When `keystone.server.services.prometheus` or `loki` are enabled, the Grafana
    module MUST automatically provision them as datasources using the well-known
    UIDs (`prometheus` and `loki`).
14. A new datasource, Alloy pipeline change, or JSON/API bridge MAY be added
    only when the required data cannot be represented cleanly through the
    existing Prometheus and Loki model.
15. Dashboard JSON, alert rules, and links MUST use the well-known datasource
    UIDs defined by keystone modules rather than ad hoc per-dashboard strings.
16. Metrics that represent durable numeric state, such as backup age, backup
    success, host health, and timer success timestamps, MUST be exposed to
    Prometheus rather than reconstructed from log lines.
17. Event streams, execution traces, task transitions, parsed URLs, and
    human-readable failure context SHOULD be emitted to Loki as structured
    logfmt logs.

## Dashboard topology

16. Keystone observability dashboards MUST follow a hierarchy:
    a system index dashboard,
    per-host dashboards,
    per-agent dashboards, and
    service-specific dashboards for subsystems such as nginx or headscale.
17. The system index dashboard MUST show fleet-wide health and MUST link to the
    per-host dashboards.
18. Every host dashboard MUST show, at minimum, host health, agent activity, ZFS
    backup state, and links to dashboards for each agent running on that host.
19. Every agent dashboard MUST support drill-down from a summary view into
    individual runs, tasks, and error logs.
20. Cross-dashboard navigation MUST use stable dashboard UIDs and template
    variables so links survive provisioning, exports, and rebuilds.

## Telemetry contract for agents and jobs

21. Systemd units, task-loop stages, schedulers, backup jobs, and similar
    keystone automation MUST emit structured telemetry that records, at minimum,
    the host, unit, agent, task or run identifier, start time, end time,
    outcome, and log location or queryable stream for each execution.
22. Agent task execution logs SHOULD include stable identifiers for the task
    file entry, workflow or task kind, execution duration, token counts when
    available, and parsed URLs such as issues or pull requests.
23. Loki log streams intended for dashboards MUST use a documented label set and
    MUST avoid embedding critical dimensions only inside free-form message text.
24. When an execution outcome is important for alerting or roll-up dashboards,
    the corresponding success, failure, and last-run timestamps SHOULD also be
    exported as Prometheus metrics.
25. New keystone automation that cannot satisfy this telemetry contract MUST NOT
    ship with a dashboard requirement until either the logs or metrics are
    extended to make the dashboard actionable.

## Review and evolution

26. A dashboard change MUST be reviewed together with the data source contract it
    depends on; if the panel requires a new log label, metric, or collector,
    that dependency MUST be implemented or explicitly tracked in the same change.
27. Keystone-specific dashboards SHOULD be organized so future service pages can
    reuse the same hierarchy, datasource UIDs, variable names, and drill-down
    patterns established for system, host, and agent dashboards.
28. Documentation for dashboard development MUST describe the local edit/export
    workflow, the provisioning path, and the expected telemetry fields so new
    dashboards can be created without reverse-engineering existing JSON.

## Golden example

A developer is improving keystone observability for agents and backups.

1. They add a system index dashboard JSON, a host dashboard JSON, and an agent
   dashboard JSON to the repo under the keystone observability dashboard tree.
2. The host dashboard uses Prometheus panels for ZFS backup recency and timer
   success, and Loki panels for recent agent failures and task execution logs.
3. The agent dashboard links from a run summary to a Loki query filtered by the
   task identifier, exposing execution duration, token counts, and parsed issue
   URLs captured by structured logs.
4. With `keystone.development = true`, Grafana provisions the dashboards from
   the local checkout so the developer can edit JSON, reapply quickly, and
   verify the links and variables without waiting for a full immutable rebuild.
5. Before finishing, they export the final Grafana dashboard JSON back into the
   repo, confirm the provisioned dashboard still renders correctly, and update
   the dashboard-development documentation for the new telemetry fields.
