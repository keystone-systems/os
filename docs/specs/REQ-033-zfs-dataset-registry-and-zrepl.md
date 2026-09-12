# REQ-033: ZFS Dataset Registry and zrepl Replication

Keystone replaces implicit recursive Sanoid/Syncoid policy with a classed ZFS
dataset registry and zrepl 0.7.0. The registry is the single source of truth
for dataset creation, snapshot eligibility, and replication selection.

Key words: RFC 2119 (MUST, MUST NOT, SHOULD, SHOULD NOT, MAY).

## Dataset registry

**REQ-033.1** `keystone.os.storage.zfs.datasets` MUST register datasets by ZFS
name with one of `system`, `state`, `critical-state`, `log`, `cache`,
`ephemeral`, or `key-escrow` classes.

**REQ-033.2** A registration MUST declare whether Keystone manages creation and
properties. Externally provisioned datasets MAY be observed without being
created or mutated.

**REQ-033.3** The reconciler MUST create and reassert only managed datasets and
properties. It MUST NOT destroy a dataset or mount over a non-empty path.

**REQ-033.4** Durable classes (`system`, `state`, and `critical-state`) MUST use
24 hourly, 7 daily, 4 weekly, and 6 monthly local snapshots by default.
`cache`, `ephemeral`, and the current `log` policy MUST NOT be snapshotted or
replicated. `key-escrow` MUST be handled only by its dedicated credstore stream.

## Topology

**REQ-033.5** The existing `zfs.backups.<pool>.targets = [ "<host>:<pool>" ]`
interface MUST remain valid. Each target MUST have a corresponding
`targetPolicies."<host>:<pool>"` declaration with a stable source port,
receiver retention, optional receive bandwidth limit, and schedule. The
schedule MUST default to hourly.

**REQ-033.6** Both endpoints of every remote target MUST declare literal
`tailscaleIP` values. Source listeners and firewall rules MUST bind only to
`tailscale0`. Evaluation MUST reject unknown targets, missing identities,
malformed targets, and port collisions.

## Job generation and encryption

**REQ-033.7** Each source pool MUST produce one central snapshot job and a
distinct source job per receiver. Snapshot selection MUST be derived from the
registry and MUST use the `zrepl_` prefix.

**REQ-033.8** Native-encrypted filesystems and the `rpool/credstore` LUKS zvol
MUST use separate jobs and separate zrepl daemon instances so their send
policies can differ while both preserve the same receiver hierarchy.

**REQ-033.9** The data job MUST select only registry-derived encrypted durable
filesystems and set `send.encrypted = true`. The credstore job MUST select
exactly `rpool/credstore`, set `send.raw = true`, and set `encrypted = false`.
A receiver MUST remain unable to read the native-encrypted data stream; the
credstore remains protected by its inner LUKS container.

**REQ-033.10** Receivers MUST own pull jobs. A same-host source and receiver
MUST use local transport; remote receivers MUST use authenticated TCP over the
tailnet. Fan-out jobs MUST be independent and MUST NOT relay one receiver
through another.

**REQ-033.11** Every destination MUST preserve a one-to-one copy of the source
hierarchy below `<pool>/replicas/<source>/`. A source dataset
`<source-pool>/<path>` MUST land at
`<pool>/replicas/<source>/<source-pool>/<path>` without transport-specific
dataset levels.

**REQ-033.12** Receiver retention MUST default to 24 hourly, 30 daily, and 12
monthly snapshots. Initial replication MUST use `most_recent`. Invalid
retention or bandwidth values MUST fail evaluation.

**REQ-033.13** zrepl pruning MUST select only `zrepl_` snapshots. It MUST NOT
delete manual, `migration-*`, `autosnap_*`, or other pre-zrepl snapshots.

## Observability

**REQ-033.14** zrepl Prometheus metrics MUST listen on loopback and Alloy MUST
scrape them. Derived alert rules MUST cover filesystem replication errors,
last success older than twice the interval, no snapshot activity for two
intervals, absent metrics, and pool capacity.

**REQ-033.15** Critical alerts MUST inhibit warning twins. Acceptance MUST
prove actual delivery through the configured in-cluster Alertmanager.

## Recovery and rollout

**REQ-033.16** Every LUKS container MUST retain and physically prove a human
recovery credential. TPM enrollment MUST NOT satisfy this requirement. A
replicated credstore MUST be treated as an additional artifact, not the only
credential copy.

**REQ-033.17** Fleet rollout MUST build every host closure and deploy sources
before receivers in the documented order. Deployment remains operator-owned.
Legacy Sanoid/Syncoid services and `autosnap_*` snapshots MUST remain until an
initial and incremental replication to every receiver, resumable interruption,
notification delivery, restore drills from both destinations, and a seven-day
healthy soak have succeeded.

**REQ-033.18** A guarded post-soak cleanup MAY remove only `autosnap_*`
snapshots. Manual and `migration-*` snapshots MUST remain outside automatic
pruning.

**REQ-033.19** Pull receivers MUST set `recv.placeholder.encryption = "off"`
for structural placeholder filesystems. Native-encrypted child streams MUST
remain raw encrypted, and received datasets MUST remain nonmounting.

Amendment (2026-08-31): Pull receivers MUST NOT apply filesystem-only
`mountpoint` or `canmount` overrides to received streams because a stream MAY
contain ZFS volumes. Receiver-root provisioning MUST keep structural parent
filesystems nonmounting with `mountpoint=none` and `canmount=off`. Pull jobs
MUST set `org.openzfs.systemd:ignore=on`, which is valid for filesystems and
volumes, on received datasets.

## Verification

Module evaluation tests MUST reject mixed streams, unknown
targets, missing tailnet identities, port conflicts, and invalid bandwidth or
retention settings. A three-host VM test MUST prove exclusions, strict
raw-encrypted fan-out, receiver-owned pruning, bandwidth configuration,
credstore zvol replication, incremental recovery after lag, and resumable
receives. Release verification MUST include `zrepl configcheck`, `zrepl test
filesystems`, Keystone flake checks, consumer host evaluation, and exact source
and receiver closure builds.

## Hardened follow-ups

- Each declared YubiKey SHOULD independently unlock every applicable LUKS
  container.
- An age/SOPS-encrypted `cryptsetup luksHeaderBackup` SHOULD be refreshed after
  enrollment changes.
