# Keystone OS SSH Module
#
# Provides secure SSH access for remote administration.
# Part of the consolidated OS module - used by both server and client.
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  bootstrapCfg = osCfg.releaseBootstrap;
in
{
  config = mkIf (osCfg.enable && osCfg.ssh.enable) {
    # Enable SSH server with secure defaults
    services.openssh = {
      enable = true;
      settings = {
        # Security hardening
        PermitRootLogin = if bootstrapCfg.enable then "yes" else "prohibit-password";
        PasswordAuthentication = bootstrapCfg.enable;
        PubkeyAuthentication = true;

        # Additional security settings
        KbdInteractiveAuthentication = false;
        X11Forwarding = false;
      };
    };

    users.users.root = mkIf bootstrapCfg.enable {
      initialPassword = bootstrapCfg.password;
    };

    # Open SSH port in firewall
    networking.firewall.allowedTCPPorts = [ 22 ];

    # Add SSH to system packages for client utilities
    environment.systemPackages = with pkgs; [
      openssh
    ];
  };
}
