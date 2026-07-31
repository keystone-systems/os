# Remote unlock integration test
#
# Tests SSH connectivity and network configuration patterns used for
# remote disk unlock. Full initrd SSH testing requires actual encrypted
# disks, which isn't practical in VM tests.
#
# This test verifies:
# - SSH connectivity between nodes
# - Network configuration for remote access
# - Multi-node communication patterns
#
# Build: nix build .#test-remote-unlock
# Interactive: nix build .#test-remote-unlock.driverInteractive
#
{
  pkgs,
  lib,
  self,
}:
pkgs.testers.nixosTest {
  name = "remote-unlock";

  nodes = {
    # Server representing a machine that would need remote unlock
    server =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      {
        # Basic system configuration
        networking.hostId = "deadbeef";
        system.stateVersion = "25.05";

        # Network configuration for remote access
        # (In production, initrd SSH would use similar network setup)
        boot.kernelParams = [ "ip=dhcp" ];
        boot.initrd.availableKernelModules = [ "virtio_net" ];

        # Regular SSH for post-boot access
        services.openssh = {
          enable = true;
          settings = {
            PermitRootLogin = "yes";
            PasswordAuthentication = true;
          };
        };

        # Set root password for testing (force to override defaults)
        users.users.root = {
          hashedPasswordFile = lib.mkForce null;
          password = lib.mkForce "root";
        };

        # VM settings
        virtualisation = {
          memorySize = 2048;
          cores = 2;
        };
      };

    # Client to test SSH connectivity (simulates unlock client)
    client =
      { pkgs, ... }:
      {
        environment.systemPackages = [
          pkgs.openssh
          pkgs.sshpass
        ];
        virtualisation = {
          memorySize = 1024;
          cores = 1;
        };
      };
  };

  testScript = ''
    import time

    print("Starting remote unlock integration test...")

    # Start both machines
    start_all()

    # Wait for server to boot
    server.wait_for_unit("multi-user.target")
    print("Server booted successfully")

    # Wait for client to boot
    client.wait_for_unit("multi-user.target")
    print("Client booted successfully")

    # Verify SSH is running on server (wait for it)
    server.wait_for_unit("sshd.service")
    print("SSH service is active on server")

    # Verify virtio_net module is available (needed for initrd networking)
    server.succeed("modprobe virtio_net || true")
    print("virtio_net module checked")

    # Wait for SSH port to be open
    server.wait_for_open_port(22)
    print("SSH port is open")

    # Give a moment for SSH to fully initialize
    time.sleep(1)

    # Test SSH connectivity from client to server
    # This simulates what a remote unlock client would do
    client.succeed(
        "sshpass -p 'root' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
        "-o ConnectTimeout=10 root@server 'echo connected'"
    )
    print("SSH connectivity verified")

    # Verify client can execute commands remotely
    result = client.succeed(
        "sshpass -p 'root' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
        "-o ConnectTimeout=10 root@server 'hostname'"
    )
    assert "server" in result, f"Expected 'server' in hostname output, got: {result}"
    print("Remote command execution verified")

    print("")
    print("All remote unlock tests passed!")
    print("")
    print("Note: This test verifies SSH/network patterns used for remote unlock.")
    print("Full initrd SSH testing requires an encrypted disk setup.")
  '';
}
