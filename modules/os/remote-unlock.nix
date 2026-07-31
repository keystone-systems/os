# Keystone OS Remote Unlock Module
#
# Enables SSH access in initrd for remote disk unlocking.
# Useful for headless servers that need to be unlocked after reboot.
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
  cfg = osCfg.remoteUnlock;
in
{
  config = mkIf (osCfg.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.authorizedKeys != [ ];
        message = "keystone.os.remoteUnlock.authorizedKeys must not be empty when remote unlock is enabled";
      }
    ];

    boot.initrd = {
      # Enable network and SSH in initrd
      network = {
        enable = true;
        ssh = {
          enable = true;
          port = cfg.port;
          authorizedKeys = cfg.authorizedKeys;
          hostKeys = [ "/etc/ssh/initrd_ssh_host_ed25519_key" ];
        };
      };

      # Use systemd password agent for unlocking
      systemd.users.root.shell = "/bin/systemd-tty-ask-password-agent";

      # Network card kernel module
      availableKernelModules = [ cfg.networkModule ];
    };

    # Kernel parameters for network configuration
    boot.kernelParams = lib.optionals cfg.dhcp [ "ip=dhcp" ];

    # Ensure host key exists for initrd SSH
    # This key should be pre-generated during deployment
    system.activationScripts.initrdSshHostKey = {
      text = ''
        if [ ! -f /etc/ssh/initrd_ssh_host_ed25519_key ]; then
          echo "WARNING: initrd SSH host key not found at /etc/ssh/initrd_ssh_host_ed25519_key"
          echo "Generate with: ssh-keygen -t ed25519 -N '''' -f /etc/ssh/initrd_ssh_host_ed25519_key"
        fi
      '';
      deps = [ ];
    };
  };
}
