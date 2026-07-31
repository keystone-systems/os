# Convention: Module-owned user groups (process.user-groups)

Standards for how keystone assigns Unix supplementary groups to the admin user,
desktop users, and other keystone-managed accounts. Consumer flakes MUST NOT
hand-maintain `extraGroups` lists that duplicate capabilities keystone already
owns.

If keystone enables the capability, keystone grants the group.

## Capability to group mapping

| Group | Who | Gating |
|---|---|---|
| `wheel` | admin only | `admin = true` |
| `zfs` | all keystone-managed users | `storage.type == "zfs"` |
| `networkmanager`, `video`, `audio` | desktop users | `users.<name>.desktop.enable` |
| `podman` | admin | `keystone.os.containers.enable` |
| `libvirtd` | admin | `keystone.os.hypervisor.enable` |
| `dialout` | admin | auto (admin-on-every-host) |
| `media` | admin | auto (admin-on-every-host) |

1. Every entry above MUST be granted by the owning keystone module through
   the `keystone.os._autoUserGroups` sink, not by consumer-flake
   `extraGroups` lists.
2. The sink has three scopes — `allUsers`, `adminOnly`, `desktopUsers` —
   and capability modules MUST append to the scope that matches the
   intended grant shape.
3. Consumer flakes SHOULD leave `keystone.os.users.<name>.extraGroups`
   empty unless they need a group keystone does not own.

## Admin vs non-admin wheel

4. Hardware and privileged-service groups (`podman`, `libvirtd`,
   `dialout`, `media`) MUST follow `admin = true`, not membership in the
   `wheel` group.
5. Non-admin users who hold `wheel` for break-glass or secondary-operator
   sudo MUST NOT inherit these groups automatically. If such a user
   needs hardware access, they add it to their own `extraGroups`
   explicitly.
6. The rationale: the admin is the single user who owns the host. A
   secondary sudo user is an authorization role, not an ownership
   transfer. Silent access to USB serial adapters, the virt socket, or
   the container socket SHOULD NOT come along with a sudo grant.
7. When a capability has a non-admin polkit path (libvirtd's
   `org.libvirt.unix.manage` rule, for example), non-admin wheel users
   retain prompt-based access via polkit. This is intentional —
   authorization without silent access.

## Why admins get dialout

8. Every keystone admin SHOULD have `dialout` on every host because
   physical serial access is a core admin capability, not a feature
   toggle. Concrete cases we support:
   - Raspberry Pi UART console debugging during installs (USB-to-UART
     adapters like FT232, CH340, PL2303).
   - ESP32, RP2040, Arduino-family flashing and monitoring over USB
     CDC-ACM.
   - Zigbee and Z-Wave USB coordinators (Sonoff Dongle-E, ConBee II,
     Aeotec Z-Stick, Home Assistant SkyConnect).
   - USB console cables to network gear (Cisco RJ45-to-USB, Mikrotik,
     switches and routers).
   - Modem AT-command access for cellular hats or LTE dongles.
9. Because `dialout` has a fixed gid in upstream nixpkgs
   (`users-groups.nix` → gid 27), the grant is portable across hosts
   without additional declarations.

## Why admins get media

10. `media` is granted unconditionally so that admin-owned data pools
    (family photos, home video, shared downloads, NAS scratch) do not
    require per-host membership changes when a new pool is introduced.
11. `media` is NOT a standard nixpkgs group. The users module declares
    `users.groups.media = {}` so admin membership resolves to a real
    group. Consumer flakes that provision media pools (NAS directories,
    ZFS datasets) chown/chmod against `media`.
12. No module currently pins the gid. If cross-host NFS or SMB sharing
    of media data is introduced, a fixed gid SHOULD be assigned at that
    point.

## Retired groups

13. `input` MUST NOT be automatically granted. Raw `/dev/input/*` access
    is a security smell; scope it with udev rules for the specific
    device when needed.
14. `sound` MUST NOT be automatically granted. It is a legacy ALSA admin
    group and is effectively dead under PipeWire. Audio device access
    is handled by desktop session integration.
15. `docker` MUST NOT be automatically granted. Keystone force-disables
    Docker (`modules/os/containers.nix` sets
    `virtualisation.docker.enable = lib.mkForce false`). The supported
    path is `podman` with the docker-compat socket.

## The `_autoUserGroups` sink

16. Capability modules MUST append their groups via
    `keystone.os._autoUserGroups.<scope> = [ ... ]` inside a
    `mkIf cfg.enable` block. Many producers, one consumer.
17. The `users.nix` module is the sole consumer of the sink. The sink
    lives at `keystone.os._autoUserGroups` (not
    `keystone.os.users._autoGroups`) because `keystone.os.users` is
    typed `attrsOf userSubmodule` and cannot host a non-user attribute.
18. New groups SHOULD NOT be added directly to the admin's
    `extraGroups` list in consumer flakes or host modules. Route the
    grant through the sink instead, with a gating expression
    (`mkIf something.enable`) on the new capability.
19. Groups that do not exist in upstream nixpkgs (e.g. `media`) MUST be
    declared via `users.groups.<name> = {}` in the owning module. The
    sink grants membership; it does not create groups.

## Cross-references

- `modules/os/users.nix` — declares `_autoUserGroups`, consumes it when
  building `users.users.<name>.extraGroups`, and owns the admin-auto
  grants for `dialout` and `media`.
- `modules/os/containers.nix` — appends `podman` to `adminOnly` when
  `keystone.os.containers.enable` is true.
- `modules/os/hypervisor.nix` — appends `libvirtd` to `adminOnly` when
  `keystone.os.hypervisor.enable` is true; non-admin wheel users retain
  polkit-prompt access via the existing rule.
- `process.enable-by-default` — the admin-on-every-host pattern that
  justifies unconditional `dialout` and `media`.
