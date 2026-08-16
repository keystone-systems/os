# Verify Alloy's effective service ordering for each supported Tailscale path.
{
  pkgs,
  lib,
  self,
}:
let
  nixosSystem = import "${pkgs.path}/nixos/lib/eval-config.nix";

  evalAlloy =
    {
      keystoneTailscaleEnabled,
      directTailscaleEnabled ? null,
    }:
    nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.operating-system
        {
          system.stateVersion = "25.05";
          boot.loader.systemd-boot.enable = true;
          networking.hostName = "alloy-test";

          keystone.hosts.alloy-test = {
            hostname = "alloy-test";
            role = "client";
          };

          keystone.os = {
            enable = true;
            tailscale.enable = keystoneTailscaleEnabled;
            alloy.enable = true;
            storage = {
              type = "lvm";
              devices = [ "/dev/vda" ];
            };
            users.testuser = {
              fullName = "Test User";
              initialPassword = "testpass";
              admin = true;
            };
          };

          fileSystems."/" = {
            device = lib.mkForce "/dev/vda2";
            fsType = lib.mkForce "ext4";
          };
        }
      ]
      ++ lib.optional (directTailscaleEnabled != null) {
        services.tailscale.enable = directTailscaleEnabled;
      };
    };

  withKeystoneTailscale =
    (evalAlloy { keystoneTailscaleEnabled = true; }).config.systemd.services.alloy;
  withDirectTailscale =
    (evalAlloy {
      keystoneTailscaleEnabled = false;
      directTailscaleEnabled = true;
    }).config.systemd.services.alloy;
  withoutTailscale =
    (evalAlloy {
      keystoneTailscaleEnabled = false;
      directTailscaleEnabled = false;
    }).config.systemd.services.alloy;
  alloyServices = [
    withKeystoneTailscale
    withDirectTailscale
    withoutTailscale
  ];
  hasDependency =
    service: dependency:
    builtins.elem dependency service.after && builtins.elem dependency service.wants;
  lacksDependency =
    service: dependency:
    !(builtins.elem dependency service.after) && !(builtins.elem dependency service.wants);
in
assert lib.assertMsg (lib.all (
  service:
  builtins.elem "network.target" service.after && lacksDependency service "network-online.target"
) alloyServices) "Alloy must declare network.target and no direct network-online dependency";
assert lib.assertMsg (
  hasDependency withKeystoneTailscale "tailscaled.service"
  && hasDependency withDirectTailscale "tailscaled.service"
  && lacksDependency withoutTailscale "tailscaled.service"
) "Alloy must stop before Tailscale only when Tailscale is enabled";
assert lib.assertMsg (lib.all (
  service: !(service.serviceConfig ? TimeoutStopSec)
) alloyServices) "Alloy must not set a stop-time override";
pkgs.runCommand "alloy-graceful-shutdown" { } ''
  touch "$out"
''
