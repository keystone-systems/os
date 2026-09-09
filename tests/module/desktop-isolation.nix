# Desktop isolation test
#
# Tests that the desktop environment (Hyprland, greetd, audio) works
# without the full OS module. This validates desktop functionality
# in isolation for faster feedback.
#
# Build: nix build .#test-desktop-isolation
# Interactive: nix build .#test-desktop-isolation.driverInteractive
#
{
  pkgs,
  lib,
  self,
  desktop,
  home-manager,
}:
pkgs.testers.nixosTest {
  name = "desktop-isolation";

  nodes.machine =
    {
      config,
      pkgs,
      ...
    }:
    {
      imports = [
        home-manager.nixosModules.home-manager
        desktop.nixosModules.default
      ];

      # Exercise the canonical desktop module instead of constructing a
      # second, independently sourced Hyprland stack in this OS test.
      keystone.desktop = {
        enable = true;
        user = "testuser";
        environment = "hyprland";
      };

      # Test user
      users.users.testuser = {
        isNormalUser = true;
        initialPassword = "testpass";
        extraGroups = [
          "wheel"
          "networkmanager"
          "video"
          "audio"
        ];
      };
      home-manager.users.testuser.home.stateVersion = "25.05";

      assertions = [
        {
          assertion =
            config.programs.hyprland.package
            == desktop.inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
          message = "OS desktop isolation must use Desktop's canonical Hyprland package";
        }
      ];

      # VM settings with graphics
      virtualisation = {
        memorySize = 4096;
        cores = 2;
        graphics = true;
      };
    };

  testScript = ''
    print("Starting desktop isolation test...")

    # Wait for boot
    machine.wait_for_unit("multi-user.target")
    print("System booted successfully")

    # Verify greetd is running
    machine.wait_for_unit("greetd.service")
    print("Greetd service is active")

    # Verify PipeWire is configured (runs as user service, not system)
    # Check that the PipeWire user service unit exists
    machine.succeed("test -e /etc/systemd/user/pipewire.service || test -e /run/current-system/etc/systemd/user/pipewire.service")
    print("PipeWire user service is configured")

    # Verify Hyprland is available
    machine.succeed("which Hyprland")
    print("Hyprland binary is available")

    # Verify UWSM is available
    machine.succeed("which uwsm")
    print("UWSM binary is available")

    # Verify test user exists with correct groups
    machine.succeed("id testuser | grep -q video")
    machine.succeed("id testuser | grep -q audio")
    print("Test user has correct groups")

    # Verify NetworkManager is running (wait for it)
    machine.wait_for_unit("NetworkManager.service")
    print("NetworkManager is active")

    # Verify polkit service unit exists (it's socket-activated/on-demand)
    machine.succeed("systemctl cat polkit.service")
    print("Polkit service is configured")

    print("All desktop isolation tests passed!")
  '';
}
