# Keystone OS Hardware Key Module
#
# Enables FIDO2/YubiKey integration for system authentication.
# Provides support for:
# - GPG/SSH agent with hardware key support
# - age-plugin-yubikey for agenix secrets
#
# Hardware key SSH public keys and age identities are declared in
# keystone.keys.<user>.hardwareKeys — this module only handles
# hardware enablement (pcscd, udev, GPG agent) and rootKeys wiring.
#
# TODO: Physical touch for sudo authentication (PAM U2F)
# TODO: LUKS disk encryption enrollment (slot configuration)
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.hardwareKey;
  keysCfg = config.keystone.keys;

  # Resolve "username/keyname" references to SSH public keys
  resolveRootKey =
    ref:
    let
      parts = splitString "/" ref;
      username = elemAt parts 0;
      keyname = elemAt parts 1;
    in
    keysCfg.${username}.hardwareKeys.${keyname}.publicKey;
in
{
  options.keystone.hardwareKey = {
    enable = mkEnableOption "Hardware key (FIDO2/YubiKey) system integration";

    rootKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        References to hardware keys (format: "username/keyname") whose SSH
        public keys should be added to root's authorized_keys. Keys are
        looked up from keystone.keys.<username>.hardwareKeys.<keyname>.
      '';
      example = [
        "ncrmro/yubi-black"
        "ncrmro/yubi-green"
      ];
    };

    # TODO: LUKS support
    # luksSlot = mkOption {
    #   type = types.int;
    #   default = 2;
    #   description = "LUKS keyslot to use for hardware key enrollment";
    # };

    # TODO: Sudo touch authentication
    # sudoTouchAuth = mkEnableOption "Require physical touch on hardware key for sudo";

    gpgAgent = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable GPG agent with SSH support for hardware key authentication";
      };

      enableSSHSupport = mkOption {
        type = types.bool;
        default = true;
        description = "Enable SSH support through GPG agent (use hardware key for SSH)";
      };
    };
  };

  config = mkIf cfg.enable {
    # Validate rootKeys references resolve in keystone.keys
    assertions = map (
      ref:
      let
        parts = splitString "/" ref;
        username = elemAt parts 0;
        keyname = elemAt parts 1;
      in
      {
        assertion =
          length parts == 2 && keysCfg ? ${username} && keysCfg.${username}.hardwareKeys ? ${keyname};
        message = "keystone.hardwareKey.rootKeys references '${ref}' but no such key exists in keystone.keys.${username}.hardwareKeys.${keyname}";
      }
    ) cfg.rootKeys;

    # Wire hardware key SSH keys into root's authorized_keys
    users.users.root.openssh.authorizedKeys.keys = map resolveRootKey cfg.rootKeys;

    # Enable smart card daemon for hardware key communication
    services.pcscd.enable = true;

    # Enable udev rules for YubiKey
    hardware.gpgSmartcards.enable = true;

    # TODO: PAM U2F authentication for sudo
    # security.pam.services.sudo.u2fAuth = cfg.sudoTouchAuth;

    # Required packages for hardware key management
    environment.systemPackages = with pkgs; [
      yubikey-manager # ykman CLI for YubiKey configuration
      age-plugin-yubikey # age encryption with YubiKey (for agenix)
      pam_u2f # PAM module for FIDO2 authentication
      yubico-piv-tool # PIV operations
      yubikey-personalization # Personalization tools
    ];

    # GPG agent with optional SSH support
    programs.gnupg.agent = mkIf cfg.gpgAgent.enable {
      enable = true;
      enableSSHSupport = cfg.gpgAgent.enableSSHSupport;
    };
  };
}
