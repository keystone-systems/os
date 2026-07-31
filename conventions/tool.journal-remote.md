# Convention: Journal Remote (tool.journal-remote)

Procedures for querying, diagnosing, and managing centralized journal logs
collected via `systemd-journal-remote` on keystone infrastructure. All fleet
hosts forward their journals to the server host (the host with
`journalRemote = true` in `keystone.hosts`). This convention covers the
commands and patterns for working with those collected logs.

This module is a canonical example of the `process.enable-by-default` convention — one host registry field (`journalRemote = true`) drives config for the entire fleet.

## Architecture

The journal-remote system has three components:

- **`systemd-journal-upload`** — runs on every non-server host, forwards local journal entries to the server over HTTPS via `journal.<domain>` when a domain is configured, or direct HTTP as fallback.
- **nginx** — runs on the server host, terminates HTTPS and proxies to the local `systemd-journal-remote` backend. Access is restricted to Tailscale IPs.
- **`systemd-journal-remote`** — runs on the server host, receives and stores journals in `/var/log/journal/remote/`.

Configuration is auto-derived from `keystone.hosts`: set `journalRemote = true` on the server host entry and all other hosts auto-forward. No per-host config needed.

For local agent journal queries, see `process.agent-cronjobs` (`agentctl <name> journalctl`).

## Querying Remote Journals

1. Remote journals MUST be queried with `journalctl --directory=/var/log/journal/remote/` on the server host.
2. Queries MUST be run as root or a user in the `systemd-journal-remote` group — unprivileged users get a permissions error.
3. Remote journal queries SHOULD use `ssh root@<server> journalctl --directory=/var/log/journal/remote/ <filters>` from any fleet host.
4. The `--directory` flag MUST be used instead of `--file` — `--directory` reads all journal files in the directory, while `--file` reads only a single file.

```bash
# Query all remote journals (all hosts)
ssh root@ocean journalctl --directory=/var/log/journal/remote/ -n 20

# Filter by source hostname
ssh root@ocean journalctl --directory=/var/log/journal/remote/ _HOSTNAME=ncrmro-workstation -n 20

# Filter by systemd unit across all hosts
ssh root@ocean journalctl --directory=/var/log/journal/remote/ -u sshd --since '1 hour ago'

# Filter by priority (errors and above, all hosts)
ssh root@ocean journalctl --directory=/var/log/journal/remote/ -p err --since '1 hour ago'
```

## Filtering by Host

5. Agents MUST use `_HOSTNAME=<hostname>` to filter remote journals by source host — this is the standard journald field populated by each host.
6. Remote journal files are named `remote-<tailscale-ip>@<machine-id>-<seqnum>-<timestamp>.journal` — agents SHOULD NOT parse filenames to identify hosts; use `_HOSTNAME` instead.

```bash
# Logs from workstation only
ssh root@ocean journalctl --directory=/var/log/journal/remote/ _HOSTNAME=ncrmro-workstation -n 50

# Logs from maia only
ssh root@ocean journalctl --directory=/var/log/journal/remote/ _HOSTNAME=maia -n 50

# List all hostnames present in remote journals
ssh root@ocean journalctl --directory=/var/log/journal/remote/ -F _HOSTNAME
```

## Common Diagnostic Patterns

7. Agents SHOULD use `--since` and `--until` for time-bounded queries to avoid scanning the full journal history.
8. Agents SHOULD use `-p err` or `-p warning` to filter by priority when diagnosing failures.
9. Boot history across the fleet MAY be inspected with `--list-boots` on the remote journal directory.
10. Agents MUST NOT read full journal output into conversation context — use `-n <count>` or `--since` to bound the output, and pipe to a file if needed.

```bash
# Recent errors across the fleet
ssh root@ocean journalctl --directory=/var/log/journal/remote/ -p err --since '30 min ago' --no-pager

# Failed units on a specific host (last hour)
ssh root@ocean journalctl --directory=/var/log/journal/remote/ _HOSTNAME=ncrmro-workstation -p err -u '*.service' --since '1 hour ago' --no-pager

# Boot history (shows boot IDs from all forwarding hosts)
ssh root@ocean journalctl --directory=/var/log/journal/remote/ --list-boots

# Follow live logs from all hosts (tail -f equivalent)
ssh root@ocean journalctl --directory=/var/log/journal/remote/ -f

# Save output to file for offline analysis
ssh root@ocean journalctl --directory=/var/log/journal/remote/ -p err --since '1 hour ago' > /tmp/fleet-errors.log
```

## Service Health Checks

11. Upload health on a client host MUST be checked with `systemctl status systemd-journal-upload.service`.
12. Server health MUST be checked with `systemctl status systemd-journal-remote.service` on the server host.
13. If `systemd-journal-upload` is in a restart loop, agents SHOULD check connectivity to the server: `curl -sk https://journal.<domain>/` from the client host when a domain is configured, or `curl -s http://<server>:19532/` otherwise.
14. Disk usage of collected journals SHOULD be monitored with `du -sh /var/log/journal/remote/` on the server host.

```bash
# Client-side: check upload service
systemctl status systemd-journal-upload.service

# Server-side: check receiver service
ssh root@ocean systemctl status systemd-journal-remote.service

# Check disk usage of collected journals
ssh root@ocean du -sh /var/log/journal/remote/
```

## Integration with ks doctor

See also `os.zfs-backup` rules 28-30 for ZFS-specific health checks in the same
diagnostic framework.

15. `ks doctor` SHOULD check `systemd-journal-upload` status on the current host and flag retry loops or failures.
16. `ks doctor` SHOULD verify the server host's `systemd-journal-remote` is running when checking the server.
17. When deploying journal-remote for the first time, the server MUST be deployed before clients — clients will retry-loop until the server is available.

## Golden Example

End-to-end diagnostic session: an agent notices a failed service on the workstation and investigates via remote journals from ocean.

```bash
# 1. Check current host for problems
systemctl --failed
# → syncoid-rpool-to-maia.service (failed)

# 2. Query remote journals for the failure (from any host)
ssh root@ocean journalctl --directory=/var/log/journal/remote/ \
  _HOSTNAME=ncrmro-workstation -u syncoid-rpool-to-maia.service \
  --since '1 hour ago' --no-pager

# 3. Cross-reference with the target host's perspective
ssh root@ocean journalctl --directory=/var/log/journal/remote/ \
  _HOSTNAME=maia -u sshd --since '1 hour ago' --no-pager

# 4. Check fleet-wide error summary
ssh root@ocean journalctl --directory=/var/log/journal/remote/ \
  -p err --since '1 hour ago' -o short-monotonic --no-pager | head -30

# 5. Verify journal infrastructure is healthy
systemctl status systemd-journal-upload.service
ssh root@ocean systemctl status systemd-journal-remote.service
ssh root@ocean du -sh /var/log/journal/remote/
```
