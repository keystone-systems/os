{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Minimal Keystone client configuration for Hyprland desktop testing
  # This configuration enables testing of the Hyprland desktop environment

  # NixOS state version - do not change after initial deployment
  system.stateVersion = "25.05";

  # System identity
  # NOTE: Must match test-server config for VM testing (same disk/pool)
  networking.hostName = "keystone-test-vm";
  # Required for ZFS - unique 8-character hex string
  # NOTE: Must match test-server config - ZFS pool was created with this hostId
  networking.hostId = "deadbeef";

  # Enable Keystone OS configuration
  keystone.os = {
    enable = true;

    # Storage configuration with ZFS and encryption
    storage = {
      type = "zfs";
      devices = [ "/dev/vda" ];
    };

    # Enable Secure Boot with lanzaboote
    secureBoot.enable = true;

    # Enable TPM-based automatic unlock
    tpm = {
      enable = true;
      pcrs = [
        1
        7
      ];
    };

    # SSH-based remote disk unlocking for VMs
    remoteUnlock = {
      enable = true;
      authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOyrDBVcGK+pUZOTUA7MLoD5vYK/kaPF6TNNyoDmwNl2 ncrmro@ncrmro-laptop-fw7k"
      ];
      networkModule = "virtio_net";
    };

    # Test user with desktop environment
    users.testuser = {
      uid = 1001;
      fullName = "Hyprland Test User";
      email = "testuser@keystone-test-vm";
      initialPassword = "testpass";
      terminal.enable = true;
      desktop = {
        enable = true;
        hyprland.modifierKey = "SUPER";
      };
      zfs = {
        quota = "50G";
        compression = "lz4";
      };
    };
  };

  # Enable desktop environment (Hyprland)
  keystone.desktop = {
    enable = true;
    user = "testuser";

    # Desktop components (all enabled by default)
    hyprland.enable = true;
    greetd.enable = true;
    audio.enable = true;
    bluetooth.enable = true;
    networking.enable = true;
  };

  # Serial console support for VM testing
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];

  # Enable serial console in systemd
  boot.initrd.systemd.emergencyAccess = true;

  # Ensure virtio modules are available in initrd
  boot.initrd.availableKernelModules = [
    "virtio_blk"
    "virtio_pci"
    "virtio_net"
  ];

  # Allow testuser to receive nix store paths over SSH
  nix.settings.trusted-users = [
    "root"
    "testuser"
  ];

  # SSH access for testing
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOyrDBVcGK+pUZOTUA7MLoD5vYK/kaPF6TNNyoDmwNl2 ncrmro@ncrmro-laptop-fw7k"
  ];
}
