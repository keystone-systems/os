let
  system = "x86_64-linux"; # TODO: Change if this laptop uses a different architecture
in
{
  inherit system;

  module =
    {
      config,
      lib,
      pkgs,
      modulesPath,
      ...
    }:
    {
      # ============================================================================
      # HARDWARE CONFIGURATION
      # ============================================================================
      #
      # This file contains hardware-specific settings. For real deployments:
      #
      # 1. Boot from the Keystone installer on your target machine
      # 2. Run: nixos-generate-config --show-hardware-config
      # 3. Replace this file's contents with the generated output
      #
      # The configuration below works for QEMU/KVM virtual machines and provides
      # sensible defaults for testing.
      #

      imports = [
        # QEMU/KVM guest support (remove for physical hardware)
        (modulesPath + "/profiles/qemu-guest.nix")
      ];

      # ──────────────────────────────────────────────────────────────────────────
      # Machine identity and storage facts
      # ──────────────────────────────────────────────────────────────────────────

      # Required for ZFS - unique 8-character hex string.
      # `ks install` replaces this placeholder automatically during the first
      # install commit if you leave it unchanged.
      networking.hostId = "00000000";

      # Root disk(s) - `ks install` replaces this placeholder automatically
      # with the disk you confirm in the installer flow.
      keystone.os.storage.devices = [
        "__KEYSTONE_DISK__"
        # Add your own stable /dev/disk/by-id/... paths here if you are not
        # using the installer flow:
        # "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S6B0NL0W127373V"
        # Add more disks for multi-disk configurations:
        # "/dev/disk/by-id/YOUR-SECOND-DISK-ID"
      ];

      # Multi-disk mode (ZFS only - ext4 always uses single-disk mode)
      # Options: "single", "stripe", "mirror", "raidz1", "raidz2", "raidz3"
      #   - single: One disk (default)
      #   - stripe: RAID0 - data striped, no redundancy (2+ disks)
      #   - mirror: RAID1 - all disks mirror each other (2+ disks)
      #   - raidz1: RAID5 equivalent - single parity (3+ disks)
      #   - raidz2: RAID6 equivalent - double parity (4+ disks)
      #   - raidz3: Triple parity (5+ disks)
      keystone.os.storage.mode = "single";

      # Set the NIC driver here if you enable keystone.os.remoteUnlock.
      # Common modules: "e1000e", "igb", "r8169", "virtio_net"
      # keystone.os.remoteUnlock.networkModule = "virtio_net";

      # ──────────────────────────────────────────────────────────────────────────
      # Boot Configuration
      # ──────────────────────────────────────────────────────────────────────────

      # Kernel modules available in initrd
      boot.initrd.availableKernelModules = [
        # Storage controllers
        "ahci" # SATA
        "nvme" # NVMe SSDs
        "sd_mod" # SCSI disks
        "sr_mod" # CD/DVD drives
        "usb_storage" # USB storage

        # USB controllers
        "xhci_pci" # USB 3.0
        "ehci_pci" # USB 2.0
        "usbhid" # USB HID devices

        # Virtualization (QEMU/KVM)
        "virtio_pci"
        "virtio_blk"
        "virtio_scsi"
        "virtio_net"
      ];

      # Kernel modules to load at boot
      boot.kernelModules = [
        # Virtualization support
        # Uncomment ONE based on your CPU:
        "kvm-intel" # For Intel CPUs
        # "kvm-amd"   # For AMD CPUs
      ];

      # ──────────────────────────────────────────────────────────────────────────
      # CPU Microcode
      # ──────────────────────────────────────────────────────────────────────────
      #
      # Enable microcode updates for security patches.
      # Uncomment the appropriate line for your CPU:

      hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      # hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

      # Enable redistributable firmware (required for most hardware)
      hardware.enableRedistributableFirmware = true;

      # ──────────────────────────────────────────────────────────────────────────
      # Graphics (Optional - uncomment for desktop systems)
      # ──────────────────────────────────────────────────────────────────────────

      # Intel integrated graphics
      # hardware.graphics.enable = true;

      # NVIDIA (proprietary drivers)
      # hardware.nvidia = {
      #   modesetting.enable = true;
      #   open = false;  # Use proprietary driver
      #   nvidiaSettings = true;
      # };
      # services.xserver.videoDrivers = [ "nvidia" ];

      # AMD graphics
      # hardware.graphics.enable = true;
      # services.xserver.videoDrivers = [ "amdgpu" ];

      # ──────────────────────────────────────────────────────────────────────────
      # Laptop Power Management (Optional)
      # ──────────────────────────────────────────────────────────────────────────

      # Enable power management for laptops
      # services.tlp.enable = true;

      # Enable thermald for Intel CPUs
      # services.thermald.enable = true;

      # ──────────────────────────────────────────────────────────────────────────
      # Serial Console (Optional - for headless servers)
      # ──────────────────────────────────────────────────────────────────────────

      # Enable serial console output (useful for VMs and headless servers)
      # boot.kernelParams = [
      #   "console=ttyS0,115200n8"  # Serial console
      #   "console=tty0"            # VGA console as fallback
      # ];
    };
}
