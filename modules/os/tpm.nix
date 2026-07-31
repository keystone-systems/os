# Keystone OS TPM Module
#
# Handles TPM-based disk encryption enrollment and automatic unlock.
# Provides enrollment commands and status checking.
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  cfg = osCfg.tpm;

  # Convert PCR list to comma-separated string for systemd-cryptenroll
  tpmPCRString = lib.concatStringsSep "," (map toString cfg.pcrs);

  # Credstore device path (always ZFS zvol when using ZFS storage)
  credstoreDevice =
    if osCfg.storage.type == "zfs" then
      "/dev/zvol/rpool/credstore"
    else
      "/dev/disk/by-partlabel/disk-root-root";

  # Helper to create executable substituted scripts
  makeExecutableScript =
    name: src: substitutions:
    pkgs.runCommand name { } ''
      cp ${pkgs.replaceVars src substitutions} $out
      chmod +x $out
    '';

  # Recovery key enrollment script
  enrollRecoveryScript = makeExecutableScript "enroll-recovery.sh" ./scripts/enroll-recovery.sh {
    systemd_cryptenroll = "${pkgs.systemd}/bin/systemd-cryptenroll";
    bootctl = "${pkgs.systemd}/bin/bootctl";
    credstoreDevice = credstoreDevice;
    tpmPCRs = tpmPCRString;
  };

  # Password enrollment script
  enrollPasswordScript = makeExecutableScript "enroll-password.sh" ./scripts/enroll-password.sh {
    cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
    systemd_cryptenroll = "${pkgs.systemd}/bin/systemd-cryptenroll";
    bootctl = "${pkgs.systemd}/bin/bootctl";
    credstoreDevice = credstoreDevice;
    tpmPCRs = tpmPCRString;
  };

  # TPM enrollment script
  enrollTpmScript = makeExecutableScript "enroll-tpm.sh" ./scripts/enroll-tpm.sh {
    cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
    systemd_cryptenroll = "${pkgs.systemd}/bin/systemd-cryptenroll";
    bootctl = "${pkgs.systemd}/bin/bootctl";
    credstoreDevice = credstoreDevice;
    tpmPCRs = tpmPCRString;
  };

  # FIDO2 enrollment script
  enrollFido2Script = makeExecutableScript "enroll-fido2.sh" ./scripts/enroll-fido2.sh {
    cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
    systemd_cryptenroll = "${pkgs.systemd}/bin/systemd-cryptenroll";
    bootctl = "${pkgs.systemd}/bin/bootctl";
    credstoreDevice = credstoreDevice;
  };

  refreshDiskUnlockStatusScript = pkgs.writeShellScript "refresh-disk-unlock-status.sh" ''
        set -euo pipefail

        STATUS_FILE="/var/lib/keystone/disk-unlock-status.json"
        MARKER_FILE="/var/lib/keystone/tpm-enrollment-complete"
        DEVICE="${credstoreDevice}"
        TOKENS="$(${pkgs.cryptsetup}/bin/cryptsetup luksDump "$DEVICE" 2>/dev/null || true)"
        TPM_ENROLLED=false
        FIDO2_ENROLLED=false

        if printf "%s\n" "$TOKENS" | grep -q "systemd-tpm2"; then
          TPM_ENROLLED=true
        fi

        if printf "%s\n" "$TOKENS" | grep -q "systemd-fido2"; then
          FIDO2_ENROLLED=true
        fi

        mkdir -p /var/lib/keystone

        if [ "$TPM_ENROLLED" = true ]; then
          cat > "$MARKER_FILE" <<MARKER
    TPM enrollment verified: $(date -Iseconds)
    Device: ${credstoreDevice}
    MARKER
        else
          rm -f "$MARKER_FILE"
        fi

        cat > "$STATUS_FILE" <<EOF
    {
      "checked_at": "$(date -Iseconds)",
      "device": "${credstoreDevice}",
      "tpm_enrolled": $TPM_ENROLLED,
      "fido2_enrolled": $FIDO2_ENROLLED
    }
    EOF
        chmod 0644 "$STATUS_FILE"
  '';
in
{
  config = mkIf (osCfg.enable && cfg.enable) {
    assertions = [
      {
        assertion = length cfg.pcrs > 0;
        message = "TPM enrollment requires at least one PCR to bind to";
      }
      {
        assertion = all (pcr: pcr >= 0 && pcr <= 23) cfg.pcrs;
        message = "TPM PCR values must be in the range 0-23";
      }
    ];

    # Create state directory for tracking
    systemd.tmpfiles.rules = [
      "d /var/lib/keystone 0755 root root -"
    ];

    # Boot-time check: inspect LUKS header as root and maintain marker file.
    # Regular users cannot read block devices, so this must run as a systemd
    # service rather than in interactiveShellInit.
    systemd.services.keystone-tpm-check = {
      description = "Check disk unlock enrollment status and update marker files";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.cryptsetup ];
      script = ''
        exec ${refreshDiskUnlockStatusScript}
      '';
    };

    # Register TPM enrollment notification via the keystone notification system.
    # The keystone-tpm-check service writes the marker file when TPM is enrolled;
    # the notification is suppressed automatically once enrollment is complete.
    keystone.os.notifications.items = [
      {
        id = "tpm-enrollment";
        title = "TPM Enrollment Required";
        body = ''
          +--------------------------------------------------------------------------+
          | [!] WARNING: TPM ENROLLMENT NOT CONFIGURED                              |
          +--------------------------------------------------------------------------+
          |                                                                          |
          | Your system is using the default LUKS password "keystone" which is      |
          | publicly known and provides NO security.                                |
          |                                                                          |
          | To secure your encrypted disk, you MUST complete TPM enrollment:        |
          |                                                                          |
          |   Option 1: Generate recovery key (recommended)                         |
          |      $ sudo keystone-enroll-recovery                                    |
          |                                                                          |
          |   Option 2: Set custom password                                         |
          |      $ sudo keystone-enroll-password                                    |
          |                                                                          |
          | After enrollment:                                                        |
          |   * Default "keystone" password will be removed                         |
          |   * Disk will unlock automatically via TPM on boot                      |
          |   * Recovery credential available if TPM fails                          |
          |                                                                          |
          | Documentation: /usr/share/doc/keystone/tpm-enrollment.md                |
          |                                                                          |
          +--------------------------------------------------------------------------+
        '';
        markerFile = "/var/lib/keystone/tpm-enrollment-complete";
      }
    ];

    # SECURITY: TPM auto-unlock is not active until explicit enrollment via one of
    # the commands below. The tpm2-device=auto crypttab hint in storage.nix tells
    # systemd-cryptsetup to attempt TPM unlock, but when no TPM token is enrolled
    # in the LUKS header, it falls back to password (fallbackToPassword = true).
    environment.systemPackages = [
      # Recovery key enrollment
      (pkgs.writeShellScriptBin "keystone-enroll-recovery" ''
        exec ${enrollRecoveryScript} "$@"
      '')

      # Custom password enrollment
      (pkgs.writeShellScriptBin "keystone-enroll-password" ''
        exec ${enrollPasswordScript} "$@"
      '')

      # TPM enrollment (standalone)
      (pkgs.writeShellScriptBin "keystone-enroll-tpm" ''
        exec ${enrollTpmScript} "$@"
      '')

      # FIDO2 hardware-key enrollment for disk unlock
      (pkgs.writeShellScriptBin "keystone-enroll-fido2" ''
        exec ${enrollFido2Script} "$@"
      '')

      # Root helper to refresh the world-readable disk unlock status file
      (pkgs.writeShellScriptBin "keystone-refresh-disk-unlock-status" ''
        exec ${refreshDiskUnlockStatusScript}
      '')
    ];
  };
}
