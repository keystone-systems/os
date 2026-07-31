# NixOS VM test for the Keystone installer TUI
#
# This test boots a VM with the installer TUI, interacts with it via
# keystrokes, runs through a complete unencrypted installation, and verifies
# the installation succeeded.
#
# Usage:
#   # Build and run the test headlessly
#   nix build .#installer-test
#
#   # Run interactively (watch the VM)
#   nix build .#installer-test.driverInteractive
#   ./result/bin/nixos-test-driver --interactive
#
#   # Or use the helper script
#   ./bin/test-installer --interactive
#
#   # In the Python REPL
#   >>> start_all()
#   >>> test_script()  # Run full test
#   # Or step through manually:
#   >>> installer.wait_for_text("Network Connected")
#   >>> installer.send_key("ret")
#   # etc.
#
{
  pkgs,
  lib,
}:
let
  ks = pkgs.callPackage ../../packages/ks { };
in
pkgs.testers.runNixOSTest {
  name = "keystone-installer";

  # Enable OCR for wait_for_text to work with graphical screens
  enableOCR = true;

  # Test machine configuration - simplified for VM testing
  nodes.installer =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      # Use default kernel (NixOS 25.05 uses 6.12 LTS which is ZFS-compatible)

      # Enable ZFS support
      boot.supportedFilesystems = [ "zfs" ];
      boot.zfs.forceImportRoot = false;
      boot.kernelModules = [ "zfs" ];
      boot.extraModulePackages = [ config.boot.kernelPackages.zfs_2_3 ];
      networking.hostId = "8425e349";

      # Enable flakes
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      # Include tools needed for installation
      environment.systemPackages = with pkgs; [
        ks
        networkmanager
        iproute2
        util-linux
        jq
        tpm2-tools
        parted
        cryptsetup
        config.boot.kernelPackages.zfs_2_3
        dosfstools
        e2fsprogs
        nix
        nixos-install-tools
        disko
        git
        shadow
      ];

      # NetworkManager for network detection
      networking.networkmanager.enable = true;

      # Disable getty on tty1 for installer
      systemd.services."getty@tty1".enable = false;
      systemd.services."autovt@tty1".enable = false;

      # Keystone installer service
      systemd.services.keystone-installer = {
        description = "Keystone Installer TUI";
        after = [
          "network.target"
          "NetworkManager.service"
        ];
        wants = [ "NetworkManager.service" ];
        conflicts = [
          "getty@tty1.service"
          "autovt@tty1.service"
        ];

        path = with pkgs; [
          networkmanager
          iproute2
          util-linux
          jq
          tpm2-tools
          parted
          cryptsetup
          config.boot.kernelPackages.zfs_2_3
          dosfstools
          e2fsprogs
          nix
          nixos-install-tools
          disko
          git
          shadow
        ];

        serviceConfig = {
          Type = "simple";
          User = "root";
          ExecStart = "${ks}/bin/ks";
          Restart = "on-failure";
          RestartSec = "5s";
          StandardInput = "tty";
          StandardOutput = "tty";
          TTYPath = "/dev/tty1";
          TTYReset = "yes";
          TTYVHangup = "yes";
        };
      };

      # VM-specific configuration
      virtualisation = {
        memorySize = 8192;
        diskSize = 30000;
        cores = 4;
        emptyDiskImages = [ 20000 ]; # Target disk for installation
        # Don't use useBootLoader - it causes UEFI boot issues in test VMs
        # The test framework boots directly via kernel+initrd
        graphics = true;
      };

      boot.kernelParams = [
        "console=ttyS0,115200"
        "console=tty1"
      ];

      # Don't start installer automatically
      systemd.services.keystone-installer.wantedBy = lib.mkForce [ ];
    };

  # Python test script
  testScript = ''
    import time
    TARGET_DISK = "vdb"

    def wait_for_installer_log(timeout=30):
        """Wait for installer log to be created"""
        installer.wait_until_succeeds("test -f /tmp/keystone-install.log", timeout=timeout)
        print("Installer log created")

    def type_text(text):
        """Type text character by character"""
        for char in text:
            installer.send_chars(char)
            time.sleep(0.05)

    # Start the VM
    print("Starting installer VM...")
    installer.start()

    # Wait for system to boot
    print("Waiting for boot...")
    installer.wait_for_unit("multi-user.target")

    # Ensure an ethernet interface has an IP address before starting installer
    print("Verifying network connectivity...")
    installer.wait_until_succeeds("ip -4 addr show | grep -E 'eth[01]' | grep -q 'inet '", timeout=30)
    installer.succeed("ip -4 addr show")

    # Start the installer service
    print("Starting keystone-installer service...")
    installer.succeed("systemctl start keystone-installer")

    # Wait for process to be running
    print("Waiting for installer process...")
    installer.wait_until_succeeds("pgrep -f 'ks'", timeout=10)

    # Allow TUI to initialize
    time.sleep(5)

    # Screen 1: Network check
    # We know network is good, so TUI should show "Continue to Installation"
    print("Step: Network Check -> Continue")
    installer.send_key("ret")

    # Screen 2: Install Method
    # Default: "Install from GitHub"
    # We want: "Local installation" (Down -> Enter)
    print("Step: Install Method -> Local")
    time.sleep(1)
    installer.send_key("down")
    time.sleep(0.5)
    installer.send_key("ret")

    # Screen 3: Disk Selection
    # Use lsblk order to choose the target data disk (vdb)
    print("Step: Disk Selection -> vdb")
    time.sleep(1)
    disks_output = installer.succeed("lsblk -dn -o NAME,TYPE | awk '$2==\"disk\"{print $1}'")
    disks = [line.strip() for line in disks_output.splitlines() if line.strip()]
    if TARGET_DISK not in disks:
        raise Exception(f"Target disk {TARGET_DISK} not found. Disks: {disks}")
    for _ in range(disks.index(TARGET_DISK)):
        installer.send_key("down")
        time.sleep(0.5)
    installer.send_key("ret")

    # Screen 4: Confirm Disk
    # Warning dialog needs confirmation
    print("Step: Confirm Disk")
    time.sleep(1)
    installer.send_key("ret")

    # Screen 5: Encryption Choice
    # Default: Encrypt
    # We want: No encryption (Down -> Enter)
    print("Step: Encryption -> None")
    time.sleep(2) # Wait for partition scan/transition
    installer.send_key("down")
    time.sleep(0.5)
    installer.send_key("ret")

    # Screen 6: Hostname
    print("Step: Hostname -> test-machine")
    time.sleep(1)
    type_text("test-machine")
    time.sleep(0.5)
    installer.send_key("ret")

    # Screen 7: Username
    print("Step: Username -> testuser")
    time.sleep(1)
    type_text("testuser")
    time.sleep(0.5)
    installer.send_key("ret")

    # Screen 8: Password
    print("Step: Password")
    time.sleep(1)
    type_text("testpass123")
    time.sleep(0.5)
    installer.send_key("ret")

    # Screen 9: Confirm Password
    print("Step: Confirm Password")
    time.sleep(1)
    type_text("testpass123")
    time.sleep(0.5)
    installer.send_key("ret")

    # Screen 10: System Type
    # Default: Server (first option) -> Enter
    print("Step: System Type -> Server")
    time.sleep(1)
    installer.send_key("ret")

    # Screen 11: Summary
    # We are at the end, press Enter to install
    print("Step: Summary -> Install")
    time.sleep(2)
    installer.send_key("ret")

    # Monitor Installation
    print("Installation started! Monitoring progress...")

    # Wait for log file to appear (proof installation script started)
    wait_for_installer_log()

    # Wait for installation artifacts to appear (signals completion)
    print("Waiting for installation completion (timeout: 10m)...")
    installer.wait_until_succeeds("test -f /mnt/etc/nixos/hardware-configuration.nix", timeout=600)

    print("Installer log tail (latest 50 lines):")
    print(installer.succeed("tail -n 50 /tmp/keystone-install.log"))

    print("Installation artifacts detected, verifying...")

    # Debug: Show disk layout and mounts
    print(installer.succeed("lsblk"))
    print(installer.succeed("findmnt -rn -o TARGET,SOURCE,FSTYPE"))

    # Verify artifacts directly on the existing mounts
    installer.succeed("test -f /mnt/etc/nixos/hardware-configuration.nix")
    # Basic presence check (hardware config)
    installer.succeed("test -f /mnt/etc/nixos/hardware-configuration.nix")

    print("All tests passed!")
  '';

  # Interactive mode
  interactive.nodes.installer =
    { ... }:
    {
      systemd.services.keystone-installer.wantedBy = [ "multi-user.target" ];
    };
}
