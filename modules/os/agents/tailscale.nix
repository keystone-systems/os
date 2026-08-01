# Per-agent Tailscale instances (currently disabled).
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
  inherit (agentsLib) tailscaleAgents hasTailscaleAgents agentFwmark;
in
{
  config = mkIf (osCfg.enable && cfg != { } && hasTailscaleAgents) {
    assertions = mapAttrsToList (name: _: {
      assertion = config.keystone.secrets.provided ? "agent-${name}-tailscale-auth-key";
      message = ''
        Agent '${name}' requires sops secret "agent-${name}-tailscale-auth-key".

        Pre-auth keys are issued credentials — prefer a short TTL and re-issue
        rather than storing a long-lived key (see docs/SECRETS.md).

        1. Create a headscale pre-auth key (run on the headscale host):
           headscale preauthkeys create --user ${name} --reusable --expiration 720h
           # Copy the generated key

        2. Add it to the agent host's sops file:
           ks secrets edit secrets/<hostname>.yaml
           # add: agent-${name}-tailscale-auth-key: <the pre-auth key>

        3. Declare in host config:
           keystone.secrets.provided."agent-${name}-tailscale-auth-key" = {
             owner = "agent-${name}";
             scope = "host";
           };
      '';
    }) tailscaleAgents;

    # Systemd target grouping all agent tailscale services
    systemd.targets.agent-tailscale = {
      description = "All per-agent tailscaled services";
      wantedBy = [ "multi-user.target" ];
    };

    # Per-agent tailscaled services + wrapper installer
    systemd.services = mkMerge (
      (mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
          resolved = agentsWithUids.${name};
          uid = resolved.uid;
          fwmark = agentFwmark name;
          stateDir = "/var/lib/tailscale/agent-${name}-tailscaled.state";
          socketPath = "/run/tailscale/agent-${name}-tailscaled.socket";
          tunName = "tailscale-agent-${name}";
          authKeyPath = config.keystone.secrets.provided."agent-${name}-tailscale-auth-key".path;
        in
        {
          "agent-${name}-tailscaled" = {
            description = "Tailscale daemon for agent-${name}";

            wantedBy = [ "agent-tailscale.target" ];
            # Secrets are installed during system activation (sops-nix), so no
            # explicit unit ordering on secret installation is needed.
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];

            serviceConfig = {
              Type = "notify";
              RuntimeDirectory = "tailscale";
              RuntimeDirectoryPreserve = "yes";
              StateDirectory = "tailscale";
              ExecStart = "${pkgs.tailscale}/bin/tailscaled --state=${stateDir} --socket=${socketPath} --tun=${tunName}";
              ExecStartPost = "${pkgs.tailscale}/bin/tailscale --socket=${socketPath} up --auth-key=file:${authKeyPath} --hostname=agent-${name}";
              Restart = "on-failure";
              RestartSec = 5;
            };
          };

          # nftables fwmark rule: route agent UID traffic through its TUN
          "agent-${name}-nftables" = {
            description = "nftables fwmark routing for agent-${name} via ${tunName}";

            wantedBy = [ "agent-tailscale.target" ];
            after = [ "agent-${name}-tailscaled.service" ];
            requires = [ "agent-${name}-tailscaled.service" ];

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = pkgs.writeShellScript "agent-${name}-nftables-up" ''
                set -euo pipefail
                # Create nftables table and chain for agent UID routing
                ${pkgs.nftables}/bin/nft add table inet agent-${name} 2>/dev/null || true
                ${pkgs.nftables}/bin/nft add chain inet agent-${name} output "{ type route hook output priority mangle; }" 2>/dev/null || true
                ${pkgs.nftables}/bin/nft add rule inet agent-${name} output meta skuid ${toString uid} meta mark set ${toString fwmark}

                # Add ip rule to route fwmarked traffic through the agent's TUN
                ${pkgs.iproute2}/bin/ip rule add fwmark ${toString fwmark} table ${toString fwmark} priority ${toString fwmark} 2>/dev/null || true
                ${pkgs.iproute2}/bin/ip route add default dev ${tunName} table ${toString fwmark} 2>/dev/null || true
              '';
              ExecStop = pkgs.writeShellScript "agent-${name}-nftables-down" ''
                ${pkgs.nftables}/bin/nft delete table inet agent-${name} 2>/dev/null || true
                ${pkgs.iproute2}/bin/ip rule del fwmark ${toString fwmark} table ${toString fwmark} 2>/dev/null || true
                ${pkgs.iproute2}/bin/ip route del default dev ${tunName} table ${toString fwmark} 2>/dev/null || true
              '';
            };
          };
        }
      ) tailscaleAgents)
      ++ [
        {
          # Install the wrapper into each agent's PATH via /home/agent-{name}/bin
          agent-tailscale-wrappers = {
            description = "Install tailscale CLI wrappers into agent home directories";

            wantedBy = [ "agent-tailscale.target" ];
            after = [
              (if useZfs then "zfs-agent-datasets.service" else "agent-homes.service")
            ];
            requires = [
              (if useZfs then "zfs-agent-datasets.service" else "agent-homes.service")
            ];

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };

            script = ''
              ${concatStringsSep "\n" (
                mapAttrsToList (
                  name: agentCfg:
                  let
                    username = "agent-${name}";
                    socketPath = "/run/tailscale/agent-${name}-tailscaled.socket";
                  in
                  ''
                    mkdir -p /home/${username}/bin
                    cat > /home/${username}/bin/tailscale <<'WRAPPER'
                    #!/bin/sh
                    exec ${pkgs.tailscale}/bin/tailscale --socket=${socketPath} "$@"
                    WRAPPER
                    chmod +x /home/${username}/bin/tailscale
                    chown -R ${username}:agents /home/${username}/bin
                  ''
                ) tailscaleAgents
              )}
            '';
          };
        }
      ]
    );
  };
}
