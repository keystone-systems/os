# Server isolation test
#
# Tests that server-like services work correctly without the full OS module.
# This validates SSH, mDNS, and basic server functionality.
#
# Build: nix build .#test-server-isolation
# Interactive: nix build .#test-server-isolation.driverInteractive
#
{
  pkgs,
  lib,
  self,
}:
pkgs.testers.nixosTest {
  name = "server-isolation";

  nodes.machine =
    {
      config,
      pkgs,
      ...
    }:
    {
      # Minimal server configuration without full OS module
      # This tests the server role in isolation

      # SSH server (core server requirement)
      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "prohibit-password";
          PasswordAuthentication = false;
        };
      };

      # mDNS for service discovery
      services.avahi = {
        enable = true;
        nssmdns4 = true;
        publish = {
          enable = true;
          addresses = true;
          domain = true;
        };
      };

      # DNS resolution
      services.resolved.enable = true;

      # Test user
      users.users.testuser = {
        isNormalUser = true;
        initialPassword = "testpass";
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keys = [
          # Test key for SSH verification
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest123 test@localhost"
        ];
      };

      # Nix settings
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      # VM settings
      virtualisation = {
        memorySize = 2048;
        cores = 2;
      };
    };

  testScript = ''
    print("Starting server isolation test...")

    # Wait for boot
    machine.wait_for_unit("multi-user.target")
    print("System booted successfully")

    # Verify SSH is running (wait for it)
    machine.wait_for_unit("sshd.service")
    print("SSH service is active")

    # Verify Avahi/mDNS is running (wait for it)
    machine.wait_for_unit("avahi-daemon.service")
    print("Avahi service is active")

    # Verify resolved is running (wait for it)
    machine.wait_for_unit("systemd-resolved.service")
    print("Resolved service is active")

    # Verify test user exists
    machine.succeed("id testuser")
    print("Test user exists")

    # Verify SSH is listening
    machine.wait_for_open_port(22)
    print("SSH is listening on port 22")

    # Verify Nix works
    machine.succeed("nix --version")
    print("Nix is functional")

    print("All server isolation tests passed!")
  '';
}
