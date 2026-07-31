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
      assertion = config.age.secrets ? "agent-${name}-tailscale-auth-key";
      message = ''
        Agent '${name}' requires agenix secret "agent-${name}-tailscale-auth-key".

        1. Create a headscale pre-auth key (run on mercury):
           headscale preauthkeys create --user ${name} --reusable --expiration 87600h
           # Copy the generated key

        2. Add to agenix-secrets/secrets.nix:
           "secrets/agent-${name}-tailscale-auth-key.age".publicKeys = adminKeys ++ [ systems.workstation ];

        3. Create the secret (paste the pre-auth key from step 1):
           cd agenix-secrets && agenix -e secrets/agent-${name}-tailscale-auth-key.age

        4. Declare in host config:
           age.secrets.agent-${name}-tailscale-auth-key = {
             file = "${"$"}{inputs.agenix-secrets}/secrets/agent-${name}-tailscale-auth-key.age";
             owner = "agent-${name}";
             mode = "0400";
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
          authKeyPath = "/run/agenix/agent-${name}-tailscale-auth-key";
        in
        {
          "agent-${name}-tailscaled" = {
            description = "Tailscale daemon for agent-${name}";

            wantedBy = [ "agent-tailscale.target" ];
            after = [
              "network-online.target"
              "agenix.service"
            ];
            wants = [ "network-online.target" ];
            requires = [ "agenix.service" ];

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
