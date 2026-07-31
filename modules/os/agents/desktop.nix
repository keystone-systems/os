# Desktop agent configuration: labwc + wayvnc services.
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  agentsLib = import ./lib.nix { inherit lib config pkgs; };
  inherit (agentsLib)
    osCfg
    cfg
    agentsWithUids
    useZfs
    ;
  inherit (agentsLib) desktopAgents hasDesktopAgents agentVncPort;
in
{
  config = mkIf (osCfg.enable && cfg != { } && hasDesktopAgents) {
    assertions = [
      # All VNC ports must be unique
      {
        assertion =
          let
            ports = mapAttrsToList (name: a: agentVncPort name a) desktopAgents;
            uniquePorts = unique ports;
          in
          length ports == length uniquePorts;
        message = "All agent VNC ports must be unique";
      }
    ];

    # Enable labwc system-wide
    programs.labwc.enable = true;

    # System packages for desktop agents
    environment.systemPackages = [
      pkgs.wayvnc
      pkgs.wlr-randr
    ];

    # Systemd target grouping all agent desktop services
    systemd.targets.agent-desktops = {
      description = "All agent headless desktop services";
      wantedBy = [ "multi-user.target" ];
    };

    # labwc + wayvnc services per desktop agent
    systemd.services = mkMerge (
      mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
          resolved = agentsWithUids.${name};
          uid = resolved.uid;
          port = agentVncPort name agentCfg;
          xdgRuntimeDir = "/run/user/${toString uid}";
        in
        {
          # labwc headless compositor
          "agent-${name}-labwc" = {
            description = "Headless Wayland desktop for agent-${name}";

            wantedBy = [ "agent-desktops.target" ];
            after = [
              (if useZfs then "zfs-agent-datasets.service" else "agent-homes.service")
            ];
            requires = [
              (if useZfs then "zfs-agent-datasets.service" else "agent-homes.service")
            ];

            environment = {
              WLR_BACKENDS = "headless";
              WLR_RENDERER = "pixman";
              WLR_HEADLESS_OUTPUTS = "1";
              WLR_LIBINPUT_NO_DEVICES = "1";
              XDG_RUNTIME_DIR = xdgRuntimeDir;
              XDG_CONFIG_HOME = "/home/${username}/.config";
            };

            serviceConfig = {
              Type = "simple";
              User = username;
              Group = "agents";
              RuntimeDirectory = "user/${toString uid}";
              RuntimeDirectoryMode = "0700";
              ExecStart = "${pkgs.labwc}/bin/labwc";
              Restart = "always";
              RestartSec = 5;
            };
          };

          # wayvnc remote viewing (binds to agentCfg.desktop.vncBind, default 0.0.0.0)
          "agent-${name}-wayvnc" = {
            description = "VNC server for agent-${name} desktop";

            wantedBy = [ "agent-desktops.target" ];
            after = [ "agent-${name}-labwc.service" ];
            requires = [ "agent-${name}-labwc.service" ];

            environment = {
              WAYLAND_DISPLAY = "wayland-0";
              XDG_RUNTIME_DIR = xdgRuntimeDir;
            };

            serviceConfig = {
              Type = "simple";
              User = username;
              Group = "agents";
              # Poll for Wayland socket instead of fixed sleep — labwc startup
              # time varies; this waits up to 10s with 100ms intervals
              ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 100); do [ -S \"${xdgRuntimeDir}/wayland-0\" ] && exit 0; sleep 0.1; done; echo \"Timed out waiting for Wayland socket\" >&2; exit 1'";
              ExecStart = "${pkgs.wayvnc}/bin/wayvnc ${agentCfg.desktop.vncBind} ${toString port}";
              Restart = "always";
              RestartSec = 5;
            };
          };
        }
      ) desktopAgents
    );
  };
}
