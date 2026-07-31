# Chromium remote debugging services for agents.
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  agentsLib = import ./lib.nix { inherit lib config pkgs; };
  inherit (agentsLib) osCfg cfg agentsWithUids;
  inherit (agentsLib) chromeAgents hasChromeAgents agentChromeDebugPort;
in
{
  config = mkIf (osCfg.enable && cfg != { } && hasChromeAgents) {
    assertions = [
      # All Chrome debug ports must be unique
      {
        assertion =
          let
            ports = mapAttrsToList (name: a: agentChromeDebugPort name a) chromeAgents;
            uniquePorts = unique ports;
          in
          length ports == length uniquePorts;
        message = "All agent Chrome debug ports must be unique";
      }
    ];

    # Chromium and Node.js available system-wide for chrome agents.
    # Node.js is required for the chrome-devtools-mcp server (stdio transport via npx/node).
    environment.systemPackages = [
      pkgs.chromium
      pkgs.nodejs
    ];

    # Chromium as system services per chrome agent
    #
    # Why system services and not systemd.user.services:
    # 1. NixOS switch-to-configuration does not manage user services — it only
    #    reloads the user daemon (daemon-reload) but won't start/restart units
    #    added to default.target.wants after the target is already reached.
    # 2. system.activationScripts with `systemctl --user -M user@` fails with
    #    "Transport endpoint is not connected" — machinectl can't reach the
    #    user's D-Bus from PID 1 context during activation.
    # 3. A system-level helper using `runuser` can connect to the user bus, but
    #    the chromium user service's ExecStartPre (Wayland socket poll) times
    #    out because the environment isn't fully forwarded through runuser.
    #
    # System services with User=/Group= work reliably: switch-to-configuration
    # manages restarts, and After=/Requires= on labwc ensures proper ordering.
    systemd.services = mkMerge (
      mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
          resolved = agentsWithUids.${name};
          uid = resolved.uid;
          debugPort = agentChromeDebugPort name agentCfg;
          xdgRuntimeDir = "/run/user/${toString uid}";
          profileDir = "/home/${username}/.config/chromium-agent";
        in
        {
          "agent-${name}-chromium" = {
            description = "Chromium browser for ${username}";
            after = [ "agent-${name}-labwc.service" ];
            requires = [ "agent-${name}-labwc.service" ];
            wantedBy = [ "agent-desktops.target" ];
            environment = {
              WAYLAND_DISPLAY = "wayland-0";
              XDG_RUNTIME_DIR = xdgRuntimeDir;
              XDG_CONFIG_HOME = "/home/${username}/.config";
            };
            serviceConfig = {
              Type = "simple";
              User = username;
              Group = "agents";
              # Poll for Wayland socket before starting Chromium
              ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 100); do [ -S \"${xdgRuntimeDir}/wayland-0\" ] && exit 0; sleep 0.1; done; echo \"Timed out waiting for Wayland socket\" >&2; exit 1'";
              ExecStart = builtins.concatStringsSep " " [
                "${pkgs.chromium}/bin/chromium"
                "--user-data-dir=${profileDir}"
                "--remote-debugging-port=${toString debugPort}"
                "--remote-debugging-address=127.0.0.1"
                "--no-first-run"
                "--no-default-browser-check"
                "--disable-gpu"
                "--enable-features=UseOzonePlatform"
                "--ozone-platform=wayland"
              ];
              Restart = "always";
              RestartSec = 5;
            };
          };
        }
      ) chromeAgents
    );
  };
}
