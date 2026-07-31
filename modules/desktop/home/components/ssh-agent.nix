{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop;
in
{
  config = mkIf cfg.enable {
    # SSH agent as a systemd user service
    # Runs ssh-agent -D -a $SSH_AUTH_SOCK, sets SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/ssh-agent
    services.ssh-agent.enable = true;
  };
}
