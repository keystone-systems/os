# Example: TPM Enrollment Configuration
#
# This example shows how to enable TPM enrollment for automatic disk unlock
# on a Keystone system.
#
# Usage:
#   1. Deploy this configuration with nixos-anywhere
#   2. Boot the system and log in
#   3. Run: sudo keystone-enroll-recovery
#   4. Save the recovery key securely
#   5. Reboot to test automatic TPM unlock
{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Import required Keystone modules
  imports = [
    # These would be imported from the Keystone flake in a real deployment:
    # keystone.nixosModules.operating-system
  ];

  # Basic system configuration
  networking.hostName = "keystone-example";
  networking.hostId = "12345678"; # Required for ZFS

  # Enable Keystone OS with disk encryption, Secure Boot, and TPM
  keystone.os = {
    enable = true;

    # Storage configuration
    storage = {
      type = "zfs";
      devices = [ "/dev/vda" ]; # Or /dev/disk/by-id/... for bare metal
      swap.size = "8G";
    };

    # Enable Secure Boot (prerequisite for TPM enrollment)
    secureBoot.enable = true;

    # Enable TPM enrollment with default settings
    tpm = {
      enable = true;
      # Optional: Customize PCR list
      # Default [1 7] is recommended for most users
      pcrs = [
        1
        7
      ]; # Default: Firmware config + Secure Boot
      # pcrs = [ 7 ];    # More update-resilient: Secure Boot only
      # pcrs = [ 0 1 7 ]; # More restrictive: Firmware code + config + Secure Boot
    };
  };

  # User account configuration
  users.users.root = {
    # Allow SSH with password for initial setup (disable after enrollment)
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAA... your-key-here"
    ];
  };

  # Enable SSH for remote management
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes"; # Change to "prohibit-password" after setup
      PasswordAuthentication = true; # Disable after SSH key setup
    };
  };

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    htop
    tmux
  ];

  # This value determines the NixOS release
  system.stateVersion = "25.05";
}
