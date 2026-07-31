# template-update-channel — verify fleet/host composition of
# `defaults.updateChannel` and per-host `updateChannel` overrides through
# `mkSystemFlake`.
#
# Covers three scenarios:
#
#   1. `defaults.updateChannel = "unstable"` propagates to every Linux host's
#      `config.keystone.update.channel` when the host does not override.
#   2. A per-host `updateChannel = "stable"` overrides the fleet default for
#      that host only, leaving siblings on the fleet value.
#   3. With neither `defaults.updateChannel` nor a per-host override, the
#      option's own default (`"stable"` — declared in
#      `modules/shared/update.nix`) still wins.
#
# These assertions lock the `lib/templates.nix` ergonomics layer so a future
# refactor cannot silently drop the plumbing that makes
# `defaults.updateChannel` reach `keystone.update.channel`.
{
  pkgs,
  lib ? pkgs.lib,
  self,
}:
let
  mkFleet =
    { defaults, hosts }:
    self.lib.mkSystemFlake {
      admin = {
        username = "admin";
        fullName = "Fleet Owner";
        email = "fleet@example.com";
        initialPassword = "changeme";
      };
      inherit defaults hosts;
    };

  channelOf = system: system.config.keystone.update.channel;

  # Home-manager has its own option tree, so the fleet default must be
  # bridged into `home-manager.sharedModules` in addition to the NixOS
  # config. Without this, the terminal and desktop HM modules (which read
  # `config.keystone.update.channel` in HM scope) silently fall back to
  # the module default "stable" regardless of the fleet declaration.
  hmChannelOf = system: user: system.config.home-manager.users.${user}.keystone.update.channel;

  # Minimal host config that is accepted by mkLaptop / mkServer without a
  # hardware.nix file. networking.hostId satisfies the ZFS server check.
  minimalLaptop = {
    kind = "laptop";
    hardware = null;
    configuration = null;
    storage.devices = [ "/dev/disk/by-id/nvme-laptop-root-001" ];
    modules = [
      {
        networking.hostId = "11111111";
      }
    ];
  };

  minimalServer =
    extra:
    {
      kind = "server";
      hardware = null;
      configuration = null;
      storage.devices = [ "/dev/disk/by-id/nvme-server-root-001" ];
      modules = [
        {
          networking.hostId = "22222222";
        }
      ];
    }
    // extra;

  # Scenario 1: fleet default "unstable" propagates to every host.
  fleetUnstable = mkFleet {
    defaults = {
      timeZone = "UTC";
      updateChannel = "unstable";
    };
    hosts = {
      laptop = minimalLaptop;
      server = minimalServer { };
    };
  };

  # Scenario 2: fleet "unstable" with per-host server override "stable".
  fleetMixed = mkFleet {
    defaults = {
      timeZone = "UTC";
      updateChannel = "unstable";
    };
    hosts = {
      laptop = minimalLaptop;
      server = minimalServer { updateChannel = "stable"; };
    };
  };

  # Scenario 3: no fleet default, no per-host override — option default wins.
  fleetNoDefault = mkFleet {
    defaults = {
      timeZone = "UTC";
    };
    hosts = {
      laptop = minimalLaptop;
    };
  };

  expect =
    label: actual: expected:
    if actual == expected then
      "ok: ${label} = ${actual}"
    else
      throw "FAIL: ${label} expected '${expected}', got '${actual}'";

  assertions = [
    # Scenario 1 — fleet "unstable" propagates.
    (expect "fleetUnstable.laptop.channel" (channelOf fleetUnstable.nixosConfigurations.laptop)
      "unstable"
    )
    (expect "fleetUnstable.server.channel" (channelOf fleetUnstable.nixosConfigurations.server)
      "unstable"
    )

    # Scenario 1 — home-manager side sees the same fleet value. This is
    # the regression guard for the NixOS↔home-manager channel bridge: the
    # terminal and desktop HM modules emit KS_UPDATE_CHANNEL from HM's
    # config tree, so the fleet declaration must reach it.
    (expect "fleetUnstable.laptop.admin.hmChannel"
      (hmChannelOf fleetUnstable.nixosConfigurations.laptop "admin")
      "unstable"
    )
    (expect "fleetUnstable.server.admin.hmChannel"
      (hmChannelOf fleetUnstable.nixosConfigurations.server "admin")
      "unstable"
    )

    # Scenario 2 — per-host override wins for that host only.
    (expect "fleetMixed.laptop.channel" (channelOf fleetMixed.nixosConfigurations.laptop) "unstable")
    (expect "fleetMixed.server.channel" (channelOf fleetMixed.nixosConfigurations.server) "stable")
    (expect "fleetMixed.laptop.admin.hmChannel"
      (hmChannelOf fleetMixed.nixosConfigurations.laptop "admin")
      "unstable"
    )
    (expect "fleetMixed.server.admin.hmChannel"
      (hmChannelOf fleetMixed.nixosConfigurations.server "admin")
      "stable"
    )

    # Scenario 3 — option default (from modules/shared/update.nix) wins.
    (expect "fleetNoDefault.laptop.channel" (channelOf fleetNoDefault.nixosConfigurations.laptop)
      "stable"
    )
    (expect "fleetNoDefault.laptop.admin.hmChannel"
      (hmChannelOf fleetNoDefault.nixosConfigurations.laptop "admin")
      "stable"
    )
  ];
in
pkgs.runCommand "test-template-update-channel" { } ''
  mkdir -p "$out"
  cat > "$out/report.txt" <<'REPORT'
  ${lib.concatStringsSep "\n" assertions}
  REPORT
''
