# Agent perception layer: screenshot sync and activity processor as systemd user services.
#
# Services created per agent (when perception.enable = true):
# - agent-{name}-screenshot-sync: uploads screenshots to Immich on a timer
# - agent-{name}-perception-processor: collects PDFs, transcripts, photos → notes
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  agentsLib = import ./lib.nix { inherit lib config pkgs; };
  inherit (agentsLib) osCfg localAgents;
  immichServiceCfg = config.keystone.services.immich;

  # Filter to agents with perception enabled
  perceptionAgents = filterAttrs (_: agentCfg: agentCfg.perception.enable) localAgents;

  # Filter to agents with perception + desktop (needed for screenshot sync)
  screenshotAgents = filterAttrs (
    _: agentCfg: agentCfg.desktop.enable && agentCfg.perception.screenshots.enable
  ) perceptionAgents;

  immichServerUrl =
    let
      immichHostName = immichServiceCfg.host;
      hostEntry = findFirst (h: h.hostname == immichHostName) null (attrValues config.keystone.hosts);
      hostTarget =
        if hostEntry == null then
          immichHostName
        else if hostEntry.tailscaleIP != null then
          hostEntry.tailscaleIP
        else if hostEntry.sshTarget != null then
          hostEntry.sshTarget
        else if hostEntry.fallbackIP != null then
          hostEntry.fallbackIP
        else
          immichHostName;
    in
    if config.keystone.domain != null then
      "https://photos.${config.keystone.domain}"
    else
      "http://${hostTarget}:2283";
in
{
  config = mkIf (osCfg.enable && perceptionAgents != { }) {
    assertions = optionals (screenshotAgents != { }) [
      {
        assertion = immichServiceCfg.host != null;
        message = "Agent screenshot sync requires keystone.services.immich.host to be set.";
      }
    ];

    warnings = concatLists (
      mapAttrsToList (
        name: _:
        optional (!(config.age.secrets ? "agent-${name}-immich-api-key")) ''
          Screenshot sync is enabled for agent '${name}', but agenix secret "agent-${name}-immich-api-key" is not declared yet.

          To finish setup:
          1. Add to agenix-secrets/secrets.nix:
             "secrets/agent-${name}-immich-api-key.age".publicKeys = adminKeys ++ [ systems.${config.networking.hostName} ];
          2. Create the secret with the agent Immich API key:
             cd agenix-secrets && agenix -e secrets/agent-${name}-immich-api-key.age
          3. If keystone.secrets.repo is null, declare it in host config:
             age.secrets.agent-${name}-immich-api-key = {
               file = "${"$"}{inputs.agenix-secrets}/secrets/agent-${name}-immich-api-key.age";
               owner = "agent-${name}";
               mode = "0400";
             };

          TODO: automate Immich API key provisioning and secret enrollment from Keystone tooling.
        ''
      ) screenshotAgents
    );

    age.secrets = mkIf (config.keystone.secrets.repo != null) (
      listToAttrs (
        concatLists (
          mapAttrsToList (name: _: [
            (nameValuePair "agent-${name}-immich-api-key" {
              file = "${config.keystone.secrets.repo}/secrets/agent-${name}-immich-api-key.age";
              owner = "agent-${name}";
              mode = "0400";
            })
          ]) screenshotAgents
        )
      )
    );

    systemd.user.services = mkMerge (
      # Screenshot sync services (only for agents with desktop enabled)
      (mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
        in
        mkIf agentCfg.perception.screenshots.enable {
          "agent-${name}-screenshot-sync" = {
            description = "Sync screenshots to Immich for ${username}";
            unitConfig.ConditionUser = username;
            serviceConfig = {
              Type = "oneshot";
              SyslogIdentifier = "agent-${name}-screenshot-sync";
            };
            script = ''
              export HOME=/home/${username}
              export XDG_STATE_HOME="''${XDG_STATE_HOME:-$HOME/.local/state}"
              exec ${pkgs.keystone.ks}/bin/ks screenshots sync \
                --url ${lib.escapeShellArg immichServerUrl} \
                --api-key-file /run/agenix/agent-${name}-immich-api-key \
                --album-name ${lib.escapeShellArg "Screenshots - ${username}"} \
                --host-name ${lib.escapeShellArg config.networking.hostName} \
                --account-name ${lib.escapeShellArg username} \
                --state-file "''${XDG_STATE_HOME}/keystone-photos/screenshot-sync.tsv"
            '';
          };
        }
      ) screenshotAgents)
      ++
        # Perception processor services (for all perception agents)
        (mapAttrsToList (
          name: agentCfg:
          let
            username = "agent-${name}";
          in
          mkIf agentCfg.perception.processor.enable {
            "agent-${name}-perception-processor" = {
              description = "Perception processor for ${username}";
              unitConfig.ConditionUser = username;
              environment = {
                PATH = lib.mkForce "/etc/profiles/per-user/${username}/bin:/run/wrappers/bin:/run/current-system/sw/bin:${lib.makeBinPath [ pkgs.nix ]}";
              };
              serviceConfig = {
                Type = "oneshot";
                TimeoutStartSec = "30m";
                SyslogIdentifier = "agent-${name}-perception-processor";
              };
              # Placeholder — actual script added in Phase 3 (feat/perception-processor)
              script = ''
                echo "perception-processor: not yet implemented for ${username}"
              '';
            };
          }
        ) perceptionAgents)
    );

    systemd.user.timers = mkMerge (
      # Screenshot sync timers
      (mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
        in
        mkIf (agentCfg.perception.screenshots.enable && agentCfg.desktop.enable) {
          "agent-${name}-screenshot-sync" = {
            wantedBy = [ "default.target" ];
            unitConfig.ConditionUser = username;
            timerConfig = {
              OnCalendar = agentCfg.perception.screenshots.syncOnCalendar;
              Persistent = true;
            };
          };
        }
      ) screenshotAgents)
      ++
        # Perception processor timers
        (mapAttrsToList (
          name: agentCfg:
          let
            username = "agent-${name}";
          in
          mkIf agentCfg.perception.processor.enable {
            "agent-${name}-perception-processor" = {
              wantedBy = [ "default.target" ];
              unitConfig.ConditionUser = username;
              timerConfig = {
                OnCalendar = agentCfg.perception.processor.onCalendar;
                Persistent = true;
              };
            };
          }
        ) perceptionAgents)
    );
  };
}
