# Mail client configuration: himalaya CLI + secret assertions.
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
    topDomain
    mailAgents
    hasMailAgents
    ;
in
{
  config = mkIf (osCfg.enable && cfg != { } && hasMailAgents) {
    assertions = [
      {
        assertion = topDomain != null;
        message = "keystone.domain must be set when agents are defined (mail derives from it)";
      }
    ]
    ++ (mapAttrsToList (
      name: agentCfg:
      let
        mailAddr =
          if agentCfg.mail.address != null then agentCfg.mail.address else "agent-${name}@${topDomain}";
      in
      {
        assertion = config.keystone.secrets.provided ? "agent-${name}-mail-password";
        message = ''
          Agent '${name}' requires sops secret "agent-${name}-mail-password".

          1. Create the Stalwart mail account (run on the mail host):
             curl -s -u admin:"$(cat /run/secrets/stalwart-admin-password)" \
               http://127.0.0.1:8082/api/principal \
               -H "Content-Type: application/json" \
               -d '{"type":"individual","name":"agent-${name}","secrets":["PASSWORD"],"emails":["${mailAddr}"]}'
             curl -s -u admin:"$(cat /run/secrets/stalwart-admin-password)" \
               http://127.0.0.1:8082/api/principal/agent-${name} -X PATCH \
               -H "Content-Type: application/json" \
               -d '[{"action":"set","field":"roles","value":["user"]}]'

          2. Add the SAME password to the agent host's sops file:
             ks secrets edit secrets/<hostname>.yaml
             # add: agent-${name}-mail-password: <the password>

          3. Declare in host config:
             keystone.secrets.provided."agent-${name}-mail-password" = {
               owner = "agent-${name}";
               scope = "host";
             };
        '';
      }
    ) mailAgents);

    # Install himalaya CLI system-wide for mail-enabled agents
    environment.systemPackages = [
      pkgs.keystone.himalaya
    ];
  };
}
