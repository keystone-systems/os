{
  pkgs,
  config,
  lib,
  ...
}:
{
  microvm = {
    hypervisor = "qemu";

    # Use q35 machine type for proper TPM ACPI table support
    # The default "microvm" machine type doesn't generate TPM2 ACPI tables
    qemu.machine = "q35";

    # Add the TPM device via extra QEMU args
    qemu.extraArgs = [
      "-chardev"
      "socket,id=chrtpm,path=./swtpm-sock"
      "-tpmdev"
      "emulator,id=tpm0,chardev=chrtpm"
      "-device"
      "tpm-tis,tpmdev=tpm0"
    ];
  };

  # Don't use keystone.os module - it requires EFI/SecureBoot assertions
  # that don't apply to microvm testing. Configure TPM directly instead.
  keystone.os.enable = false;

  # Enable TPM2 support in the guest
  security.tpm2 = {
    enable = true;
    pkcs11.enable = true;
    tctiEnvironment.enable = true;
  };

  environment.systemPackages = with pkgs; [
    tpm2-tools
    cryptsetup
  ];

  system.stateVersion = "25.05";

  # Minimal user config
  users.users.root.initialPassword = "root";

  # Networking (optional but good for debugging)
  networking.hostName = "tpm-microvm";

  systemd.services.verify-tpm = {
    description = "Verify TPM presence and test enrollment on loopback";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal+console";
    };
    script = ''
      set -e
      echo "--- TPM Test: Start ---"

      echo "Checking for TPM device..."
      if [ -c /dev/tpm0 ]; then
        echo "SUCCESS: TPM device found at /dev/tpm0"
      else
        echo "FAILURE: TPM device not found"
        exit 1
      fi

      echo "Creating test disk image..."
      TEST_IMG="/var/lib/test-luks.img"
      dd if=/dev/zero of=$TEST_IMG bs=1M count=64

      echo "Formatting as LUKS2..."
      echo -n "secret" > /tmp/pass
      ${pkgs.cryptsetup}/bin/cryptsetup luksFormat --type luks2 $TEST_IMG /tmp/pass

      echo "Enrolling TPM..."
      # PCR 7 (Secure Boot) might be tricky if not in a proper state, let's use PCR 0 (Core) for test
      ${pkgs.systemd}/bin/systemd-cryptenroll $TEST_IMG \
        --tpm2-device=auto \
        --tpm2-pcrs=0 \
        --unlock-key-file=/tmp/pass

      echo "SUCCESS: TPM enrolled."

      echo "Verifying unlock..."
      # Open with TPM (no password file)
      # systemd-cryptsetup attach name device [password] [options]
      # We use systemd-cryptsetup directly or cryptsetup open?
      # systemd-cryptsetup is the one that handles TPM.

      # We need to detach first if it was attached? luksFormat doesn't attach.

      echo "Attaching with systemd-cryptsetup (TPM)..."
      ${pkgs.systemd}/lib/systemd/systemd-cryptsetup attach "test-tpm" "$TEST_IMG" "none" "tpm2-device=auto"

      if [ -b /dev/mapper/test-tpm ]; then
        echo "SUCCESS: Device unlocked and attached via TPM!"
        ${pkgs.systemd}/lib/systemd/systemd-cryptsetup detach "test-tpm"
      else
        echo "FAILURE: Failed to attach device via TPM."
        exit 1
      fi

      echo "--- TPM Test: PASSED ---"
      poweroff
    '';
  };
}
