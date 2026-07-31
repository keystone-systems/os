{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.keystone.os.services.airplay;
in
{
  options.keystone.os.services.airplay = {
    enable = mkEnableOption "AirPlay receiver service (Shairport Sync)";

    name = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "The name displayed to AirPlay clients.";
      example = "Living Room Speakers";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to automatically open required TCP/UDP ports in the firewall.";
    };
  };

  config = mkIf cfg.enable {
    # System packages
    environment.systemPackages = with pkgs; [
      nqptp
      shairport-sync-airplay2
    ];

    # User and group
    users.users.shairport-sync = {
      description = "Shairport user";
      isSystemUser = true;
      createHome = true;
      home = "/var/lib/shairport-sync";
      group = "shairport-sync";
      extraGroups = [ "pulse-access" ];
    };
    users.groups.shairport-sync = { };

    # Firewall configuration
    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [
        3689
        5353
        5000
      ];
      allowedUDPPorts = [ 5353 ];
      allowedTCPPortRanges = [
        {
          from = 7000;
          to = 7001;
        }
        {
          from = 32768;
          to = 60999;
        }
      ];
      allowedUDPPortRanges = [
        {
          from = 319;
          to = 320;
        }
        {
          from = 6000;
          to = 6009;
        }
        {
          from = 32768;
          to = 60999;
        }
      ];
    };

    # Systemd services
    systemd.services = {
      nqptp = {
        description = "Network Precision Time Protocol for Shairport Sync";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.nqptp}/bin/nqptp";
          Restart = "always";
          RestartSec = "5s";
        };
      };

      shairport-sync = {
        description = "Shairport Sync AirPlay Receiver";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network.target"
          "avahi-daemon.service"
        ];
        serviceConfig = {
          ExecStart = "${pkgs.shairport-sync-airplay2}/bin/shairport-sync pa --name '${cfg.name}'";
          Restart = "on-failure";
          RuntimeDirectory = "shairport-sync";
          User = "shairport-sync";
          Group = "shairport-sync";
        };
      };
    };

    # Ensure Avahi is enabled (Keystone OS module also manages this, but we enforce it here just in case)
    services.avahi = {
      enable = true;
      publish = {
        enable = true;
        userServices = true;
      };
    };
  };
}
