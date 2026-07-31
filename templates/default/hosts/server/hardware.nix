let
  system = "x86_64-linux"; # TODO: Change if this server uses a different architecture
in
{
  inherit system;

  module =
    {
      config,
      lib,
      modulesPath,
      ...
    }:
    {
      # ============================================================================
      # SERVER HARDWARE CONFIGURATION
      # ============================================================================
      #
      # This host can represent either a VPS or a baremetal server.
      #
      # For VPS deployments, keep only the modules and settings that match your
      # provider's virtual hardware.
      #
      # For baremetal deployments:
      # 1. Boot from the Keystone installer on the target host
      # 2. Run: nixos-generate-config --show-hardware-config
      # 3. Replace this file with the generated output and then reapply the storage
      #    facts below

      imports = [
        # QEMU/KVM guest support is a reasonable default for many VPS environments.
        (modulesPath + "/profiles/qemu-guest.nix")
      ];

      # Required for ZFS - unique 8-character hex string.
      # `ks install` replaces this placeholder automatically during the first
      # install commit if you leave it unchanged.
      networking.hostId = "00000000";

      # Root disk(s) for the server host. `ks install` replaces this placeholder
      # automatically with the disk you confirm in the installer flow.
      keystone.os.storage.devices = [
        "__KEYSTONE_DISK__"
        # Add your own stable /dev/disk/by-id/... paths here if you are not
        # using the installer flow:
        # "/dev/disk/by-id/YOUR-SERVER-DISK-ID-HERE"
      ];

      # Set to "stripe", "mirror", or a raidz mode for multi-disk server roots.
      keystone.os.storage.mode = "single";

      # Remote unlock is commonly needed on headless servers. Set the NIC driver
      # here if you enable keystone.os.remoteUnlock in the host config.
      # keystone.os.remoteUnlock.networkModule = "virtio_net";

      boot.initrd.availableKernelModules = [
        "ahci"
        "nvme"
        "sd_mod"
        "virtio_pci"
        "virtio_blk"
        "virtio_scsi"
        "virtio_net"
      ];

      boot.kernelModules = [
        "kvm-intel"
        # "kvm-amd"
      ];

      hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      # hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      hardware.enableRedistributableFirmware = true;
    };
}
