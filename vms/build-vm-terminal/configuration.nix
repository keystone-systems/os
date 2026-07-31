{
  config,
  pkgs,
  lib,
  keystone,
  ...
}:
{
  # Minimal Keystone configuration for terminal dev environment testing
  # Uses nixos-rebuild build-vm for fast iteration without encryption/secure boot
  #
  # Build with: nixos-rebuild build-vm --flake .#build-vm-terminal
  # Run with: ./result/bin/run-build-vm-terminal-vm
  #
  # The VM:
  # - Mounts host Nix store via 9P (read-only)
  # - Creates persistent qcow2 disk at ./build-vm-terminal.qcow2
  # - Much faster than full deployment for testing configs

  # NixOS state version
  system.stateVersion = "25.05";

  # System identity
  networking.hostName = "keystone-buildvm-terminal";

  # Simple boot configuration for VM
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Root filesystem (required for NixOS)
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # Enable SSH for remote access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Basic networking with DHCP
  networking.useDHCP = lib.mkDefault true;

  # VM-specific configuration for build-vm
  # These options only apply when building with nixos-rebuild build-vm
  virtualisation.vmVariant = {
    # Forward SSH port for easy host access: ssh -p 2222 testuser@localhost
    virtualisation.forwardPorts = [
      {
        from = "host";
        host.port = 2222;
        guest.port = 22;
      }
    ];
  };

  # Enable serial console for VM
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];

  # Enable mutable users for easy testing
  users.mutableUsers = true;

  # Test user with terminal dev environment
  users.users.testuser = {
    isNormalUser = true;
    description = "Terminal Dev Test User";
    initialPassword = "testpass"; # Test only - insecure
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOyrDBVcGK+pUZOTUA7MLoD5vYK/kaPF6TNNyoDmwNl2 ncrmro@ncrmro-laptop-fw7k"
    ];
  };

  # Root password for easy access
  users.users.root.initialPassword = "root";

  # Basic system packages
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
  ];

  # Allow sudo without password (testing only)
  security.sudo.wheelNeedsPassword = false;

  # Nix settings
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "testuser"
    ];
  };

  # Configure home-manager
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    # Import home-manager modules
    sharedModules = [
      ../../modules/keystone/terminal
    ];
  };

  # Configure home-manager for test user
  home-manager.users.testuser = {
    home.stateVersion = "25.05";

    # Enable terminal dev environment
    keystone.terminal = {
      enable = true;
      git = {
        userName = "Terminal Test User";
        userEmail = "testuser@keystone-buildvm-terminal";
      };
    };
  };
}
