# Keystone OS Secure Boot Module
#
# Configures Lanzaboote for UEFI Secure Boot with custom key enrollment.
# Keys are generated and managed via sbctl.
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
  cfg = osCfg.secureBoot;
in
{
  config = mkIf (osCfg.enable && cfg.enable) {
    assertions = [
      {
        assertion = config.boot.loader.efi.canTouchEfiVariables;
        message = "Secure Boot requires EFI variables access (boot.loader.efi.canTouchEfiVariables)";
      }
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "Secure Boot module currently only supports x86_64-linux";
      }
    ];

    # Ensure sbctl is available for key management
    environment.systemPackages = [ pkgs.sbctl ];

    # Configure lanzaboote for Secure Boot
    boot.lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };

    # Disable systemd-boot when using lanzaboote
    # (lanzaboote provides its own bootloader)
    boot.loader.systemd-boot.enable = mkForce false;

    # Minimal fallback: generate keys if missing.
    # Detection and enrollment logic lives in ks (provision-secure-boot command
    # and first-boot TUI). This activation script only ensures keys exist so
    # lanzaboote can sign boot entries.
    system.activationScripts.secureBootProvisioning = {
      text = ''
        if [ ! -f /var/lib/sbctl/keys/db/db.pem ]; then
          echo "[secure-boot] Generating Secure Boot keys..."
          ${pkgs.sbctl}/bin/sbctl create-keys || true
        fi
      '';
      deps = [ ];
    };
  };
}
