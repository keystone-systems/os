# Convention: Prefer systemd units over activation scripts (os.systemd-over-activation)

Standards for choosing between `system.activationScripts` and `systemd.services`
in NixOS modules. The default is **systemd**; activation scripts are the narrow
exception, not the norm.

This convention exists because `system.activationScripts` is outside systemd's
dependency graph. Anything that needs ordering against a unit (pool imports,
network-online, mounts, secret decryption, container runtimes) cannot express
that edge from an activation script and will race at boot. Rediscovered during
the ZFS backup receiver fix — see `os.zfs-backup` rule 17g.

## When a systemd oneshot is required

1. `system.activationScripts` MUST NOT be used when the work has any of the
   following properties:
   - Invokes a service-touching external binary — anything that talks to a
     subsystem systemd manages (e.g., `zfs`, `zpool`, `mount`, `umount`,
     `systemctl`, `docker`, `podman`, `curl`, `openssl`, `ssh`, `pg_dump`,
     `redis-cli`). Basic coreutils filesystem setup against permitted paths
     (`mkdir`, `install`, `ln`, `chmod`, `chown` under `/var/lib/<service>`,
     `/etc`, `/nix`, `/root`) is explicitly exempt and is covered by rules
     4–5.
   - Depends on a non-`rpool` ZFS pool, a non-root mount, a network
     interface, or a service that systemd brings up after activation runs.
   - Needs to retry, be re-triggered manually, or produce a failure state
     that is visible in `systemctl status` / `journalctl -u`.
   - Participates in the systemd ordering graph (expects `After=`,
     `Requires=`, `Wants=`, `PartOf=`, or `ConditionPathExists=`).
2. Work that matches any clause in rule 1 MUST be expressed as a
   `systemd.services.<name>` oneshot with `Type = "oneshot"`,
   `RemainAfterExit = true`, an explicit `wantedBy` target, and any
   required `after`/`requires` wiring on services it depends on.
3. The oneshot unit SHOULD set appropriate hardening options (`ProtectSystem`,
   `PrivateTmp`, `NoNewPrivileges`, `DynamicUser` where applicable) rather
   than running fully privileged just because activation scripts do.

## When an activation script is still appropriate

4. `system.activationScripts` MAY be used for work that meets ALL of the
   following:
   - Runs entirely against the local filesystem under `/nix`, `/etc`, or a
     path guaranteed to exist before systemd (`/var/lib`, `/root`).
   - Has no dependency on any systemd unit, pool, mount, or network state.
   - Is idempotent and cheap enough to run on every `nixos-rebuild switch`.
   - Would not benefit from a failure state visible in `systemctl`.
5. Typical good fits are: creating a directory under `/var/lib/<service>`
   that a service will own at runtime, writing a static marker file,
   regenerating a config template that is consumed by a service unit
   (which is then restarted by the module's normal wiring).
6. When in doubt, choose a systemd unit. The reverse refactor
   (systemd → activation script) is almost never required; the forward
   refactor (activation script → systemd oneshot) is common and disruptive.

## Home-Manager activation

7. `home.activation` is a separate mechanism and is NOT covered by this
   convention. See `tool.nix` rules 17-21 for home-manager activation
   script requirements.
8. Rule 1 still applies in spirit for home-manager: if a home-manager
   activation step must wait for a user systemd unit or an agenix secret
   file, express the dependency via `systemd.user.services` instead.

## Observability requirements

9. Any module that provides a long-running or failure-prone systemd oneshot
   SHOULD expose the unit's state to Prometheus via the node exporter
   `systemd` collector (for example, the `node_systemd_unit_*` metrics,
   already enabled fleet-wide) rather than inventing a custom metric for
   success/failure. See `process.grafana-dashboard-development` for how to
   surface it.

## Golden example

The ZFS backup receiver initialization was originally written as a
`system.activationScripts` entry that ran `zfs create` and `zfs allow`
against backup datasets. On hosts with non-boot ZFS pools (ocean's `ocean`
pool, maia's `lake` pool), the script raced the systemd pool-import units
and silently failed when the pool was not yet available. The fix converted
the work into a systemd oneshot so ordering is enforceable:

```nix
# WRONG — activation script cannot express "after import-ocean.service"
system.activationScripts.zfs-backup-receiver-init = {
  text = ''
    ${zfs} create -p ocean/backups/workstation/rpool || true
    ${zfs} allow workstation-sync receive,create,mount,rollback,destroy \
      ocean/backups/workstation/rpool
  '';
};

# RIGHT — systemd oneshot with explicit ordering on the pool-import unit
systemd.services.zfs-backup-receiver-init = {
  description = "Initialize ZFS backup receiver datasets and delegations";
  wantedBy = [ "multi-user.target" ];
  after = [ "import-ocean.service" ];
  requires = [ "import-ocean.service" ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
  };
  script = ''
    ${zfs} create -p ocean/backups/workstation/rpool || true
    ${zfs} allow workstation-sync receive,create,mount,rollback,destroy \
      ocean/backups/workstation/rpool
  '';
};
```

The systemd form makes the failure visible in `systemctl status
zfs-backup-receiver-init`, keeps the work out of the `nixos-rebuild`
output stream, and — critically — guarantees it does not run until the
pool is imported. See `os.zfs-backup` rules 17d–17h for the domain-specific
application of this convention.

## Cross-references

- `os.zfs-backup` — domain application of rule 1, especially for receiver
  pool-import ordering.
- `tool.nix` rules 17-21 — home-manager activation script rules (different
  mechanism, overlapping spirit).
- `process.grafana-dashboard-development` — surfacing oneshot unit state.
