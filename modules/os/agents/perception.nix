# Agent perception layer: activity processor as a systemd user service.
#
# Services created per agent (when perception.enable = true):
# - agent-{name}-perception-processor: collects PDFs, transcripts, photos → notes
#
# Screenshot sync to Immich lived here until 2026-08-02. Its only
# implementation was `ks screenshots sync` in the Rust CLI, which was deleted;
# no agent enabled it.
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

  # Filter to agents with perception enabled
  perceptionAgents = filterAttrs (_: agentCfg: agentCfg.perception.enable) localAgents;
in
{
  config = mkIf (osCfg.enable && perceptionAgents != { }) {
    systemd.user.services = mkMerge (
      mapAttrsToList (
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
      ) perceptionAgents
    );

    systemd.user.timers = mkMerge (
      mapAttrsToList (
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
      ) perceptionAgents
    );
  };
}
