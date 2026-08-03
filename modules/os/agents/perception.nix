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

  perceptionAgents = filterAttrs (_: agentCfg: agentCfg.perception.enable) localAgents;

  # The processor is the only consumer left, so filter once here rather than
  # traversing every perception agent twice and guarding each unit with mkIf.
  # Screenshot sync used to need a second, differently-filtered set.
  processorAgents = filterAttrs (_: agentCfg: agentCfg.perception.processor.enable) perceptionAgents;

  unitName = name: "agent-${name}-perception-processor";
in
{
  config = mkIf (osCfg.enable && perceptionAgents != { }) {
    systemd.user.services = mapAttrs' (
      name: _:
      let
        username = "agent-${name}";
      in
      nameValuePair (unitName name) {
        description = "Perception processor for ${username}";
        unitConfig.ConditionUser = username;
        environment = {
          PATH = lib.mkForce "/etc/profiles/per-user/${username}/bin:/run/wrappers/bin:/run/current-system/sw/bin:${lib.makeBinPath [ pkgs.nix ]}";
        };
        serviceConfig = {
          Type = "oneshot";
          TimeoutStartSec = "30m";
          SyslogIdentifier = unitName name;
        };
        # Placeholder — actual script added in Phase 3 (feat/perception-processor)
        script = ''
          echo "perception-processor: not yet implemented for ${username}"
        '';
      }
    ) processorAgents;

    systemd.user.timers = mapAttrs' (
      name: agentCfg:
      nameValuePair (unitName name) {
        wantedBy = [ "default.target" ];
        unitConfig.ConditionUser = "agent-${name}";
        timerConfig = {
          OnCalendar = agentCfg.perception.processor.onCalendar;
          Persistent = true;
        };
      }
    ) processorAgents;
  };
}
