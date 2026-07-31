# CRITICAL: docs/agents.md documents the mail templates and agentctl mail
# command for this module. Keep it in sync with any changes here.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.agentMail;
  mailCfg = config.keystone.terminal.mail;
in
{
  options.keystone.terminal.agentMail = {
    enable = mkOption {
      type = types.bool;
      default = mailCfg.enable;
      description = "Enable agent-mail CLI for sending structured emails to OS agents";
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    home.packages = [
      pkgs.keystone.agent-mail
    ];
  };
}
