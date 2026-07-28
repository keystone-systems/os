{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    attrNames
    concatLists
    concatMap
    concatStringsSep
    filter
    foldl'
    genAttrs
    hasInfix
    mapAttrs
    mapAttrsToList
    mkAfter
    mkIf
    mkMerge
    mkOption
    optional
    types
    unique
    ;

  enabled = config.keystone.hardwareKeys;
  registrations = config.keystone.hardwareKeyRegistrations;
  installedState = config.keystone.hardwareKeyState;
  strict = config.keystone.hardwareKeyPolicy.strict;

  enabledNames = attrNames enabled;
  resolved = mapAttrs (
    name: serial:
    if registrations ? ${name} then
      registrations.${name}
      // {
        inherit name serial;
      }
    else
      null
  ) enabled;
  resolvedEntries = filter (entry: entry != null) (lib.attrValues resolved);
  localEntries = filter (
    entry: entry.owner != null && config.users.users ? ${entry.owner}
  ) resolvedEntries;

  rootSshKeys = unique (concatMap (entry: entry.sshPublicKeys) resolvedEntries);

  pamEntries = filter (entry: entry.pamU2f != [ ]) localEntries;
  pamByUser = foldl' (
    result: entry:
    result
    // {
      ${entry.owner} = (result.${entry.owner} or [ ]) ++ entry.pamU2f;
    }
  ) { } pamEntries;
  pamMappings = concatStringsSep "\n" (
    mapAttrsToList (username: credentials: "${username}:${concatStringsSep ":" credentials}") pamByUser
  );
  pamAuthFile = pkgs.writeText "keystone-u2f-mappings" ''
    ${pamMappings}
  '';
  auditPackage = pkgs.callPackage ../packages/hardware-key-audit.nix { };

  managedLuksNames = config.keystone.hardwareKeyLuksTargets;
  luksNames = unique managedLuksNames;

  luksProjection = genAttrs luksNames (
    name:
    let
      state = installedState.luks.${name} or null;
    in
    {
      device = lib.attrByPath [ name "device" ] null config.boot.initrd.luks.devices;
      installed = state;
      enabledKeys = enabledNames;
    }
  );

  keyProjection = mapAttrs (
    name: serial:
    let
      registration = resolved.${name};
    in
    {
      inherit serial;
      owner = if registration == null then null else registration.owner;
      consumers = {
        rootSsh = if registration == null then [ ] else registration.sshPublicKeys;
        pamU2f =
          if registration == null || !(config.users.users ? ${registration.owner}) then
            [ ]
          else
            registration.pamU2f;
        luks = luksNames;
        sops = if registration == null then [ ] else registration.ageRecipients;
        webauthn = if registration == null then [ ] else registration.webAuthn;
      };
    }
  ) enabled;

  projection = {
    contractVersion = 1;
    host = config.networking.hostName;
    keys = keyProjection;
    luks = luksProjection;
    inherit findings;
  };

  finding = code: message: {
    severity = "warning";
    inherit code message;
  };

  registrationFindings = concatLists (
    mapAttrsToList (
      name: _:
      let
        registration = resolved.${name};
        localOwner =
          registration != null && registration.owner != null && config.users.users ? ${registration.owner};
      in
      if registration == null then
        [
          (finding "KSC-001.4/missing-registration" "hardware key '${name}' is enabled but has no public registration")
        ]
      else
        optional (registration.sshPublicKeys == [ ]) (
          finding "KSC-001.4/missing-root-ssh" "hardware key '${name}' is enabled but has no root SSH public key"
        )
        ++ optional (localOwner && registration.pamU2f == [ ]) (
          finding "KSC-001.4/missing-pam-u2f" "hardware key '${name}' is enabled for local user '${registration.owner}' but has no PAM/U2F registration"
        )
        ++ optional (registration.ageRecipients == [ ]) (
          finding "KSC-001.4/missing-sops-recipient" "hardware key '${name}' is enabled but has no public SOPS age recipient"
        )
    ) enabled
  );

  missingLuksFindings = concatMap (
    luksName:
    let
      targetState = installedState.luks.${luksName} or null;
    in
    map (
      name:
      finding "KSC-001.4/missing-luks-enrollment" "hardware key '${name}' is enabled but is not recorded as enrolled in LUKS target '${luksName}'"
    ) (filter (name: targetState == null || !(targetState.enrollments ? ${name})) enabledNames)
  ) luksNames;

  staleLuksFindings = concatLists (
    mapAttrsToList (
      luksName: state:
      optional (!(config.boot.initrd.luks.devices ? ${luksName})) (
        finding "KSC-001.4/stale-luks-target" "installed hardware-key state references LUKS target '${luksName}', but that target is no longer configured"
      )
      ++ map (
        name:
        finding "KSC-001.4/stale-luks-enrollment" "hardware key '${name}' is disabled but remains recorded in LUKS target '${luksName}'; explicit revocation is pending"
      ) (filter (name: !(enabled ? ${name})) (attrNames state.enrollments))
    ) installedState.luks
  );

  findings = registrationFindings ++ missingLuksFindings ++ staleLuksFindings;

  collectStrings =
    value:
    if builtins.isString value then
      [ value ]
    else if builtins.isList value then
      concatMap collectStrings value
    else if builtins.isAttrs value then
      concatMap collectStrings (lib.attrValues value)
    else
      [ ];
  publicStrings = collectStrings registrations;
  unsafePublicStrings = filter (
    value:
    hasInfix "AGE-PLUGIN-YUBIKEY-" value
    || hasInfix "AGE-SECRET-KEY-" value
    || hasInfix "PRIVATE KEY-----" value
  ) publicStrings;

  webAuthnType = types.submodule {
    options = {
      relyingParty = mkOption {
        type = types.str;
        description = "WebAuthn relying-party identifier.";
      };
      credentialId = mkOption {
        type = types.str;
        description = "Public WebAuthn credential identifier.";
      };
    };
  };

  registrationType = types.submodule {
    options = {
      owner = mkOption {
        type = types.str;
        description = "Local principal that owns this physical authenticator.";
      };
      sshPublicKeys = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Public SSH credentials resident on this authenticator.";
      };
      pamU2f = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Public PAM/U2F registration fragments for the owner.";
      };
      ageRecipients = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Public age recipients backed by this authenticator.";
      };
      webAuthn = mkOption {
        type = types.listOf webAuthnType;
        default = [ ];
        description = "Public WebAuthn registrations grouped by relying party.";
      };
    };
  };
in
{
  options.keystone = {
    hardwareKeys = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        yubi-5-green = "12356";
      };
      description = ''
        Enabled hardware keys keyed by fleet-stable name. Presence enables the
        key; the value is its numeric manufacturer serial.
      '';
    };

    hardwareKeyRegistrations = mkOption {
      internal = true;
      type = types.attrsOf registrationType;
      default = { };
      description = "Setup-managed public credentials grouped by hardware-key name.";
    };

    hardwareKeyState = mkOption {
      internal = true;
      default = { };
      description = "Setup-managed public installed state for hardware-key consumers.";
      type = types.submodule {
        options.luks = mkOption {
          default = { };
          type = types.attrsOf (
            types.submodule {
              options = {
                uuid = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                };
                enrollments = mkOption {
                  default = { };
                  type = types.attrsOf (
                    types.submodule {
                      options = {
                        token = mkOption {
                          type = types.int;
                        };
                        credential = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                        };
                      };
                    }
                  );
                };
              };
            }
          );
        };
      };
    };

    hardwareKeyLuksTargets = mkOption {
      internal = true;
      type = types.listOf types.str;
      default = [ ];
      description = "Conventional LUKS mappings published by the root-storage module.";
    };

    hardwareKeyPolicy.strict = mkOption {
      internal = true;
      type = types.bool;
      default = false;
      description = "Reject unresolved hardware-key findings during guarded workflows.";
    };

    hardwareKeyFindings = mkOption {
      internal = true;
      readOnly = true;
      type = types.listOf types.attrs;
      description = "Derived public hardware-key registration and enrollment drift.";
    };

    hardwareKeyProjection = mkOption {
      internal = true;
      readOnly = true;
      type = types.attrs;
      description = "Versioned public hardware-key projection for read-only tooling.";
    };
  };

  config = mkMerge [
    {
      keystone.hardwareKeyFindings = findings;
      keystone.hardwareKeyProjection = projection;

      assertions = [
        {
          assertion = builtins.length (unique (lib.attrValues enabled)) == builtins.length enabledNames;
          message = "KSC-001.3: enabled hardware-key serials must be unique";
        }
        {
          assertion = lib.all (serial: builtins.match "^[0-9]+$" serial != null) (lib.attrValues enabled);
          message = "KSC-001.4: enabled hardware-key serials must contain only decimal digits";
        }
        {
          assertion = unsafePublicStrings == [ ];
          message = "KSC-001.4: public hardware-key registrations contain a private identity or private-key format";
        }
      ]
      ++ optional strict {
        assertion = findings == [ ];
        message = "KSC-001.4: strict hardware-key validation failed: ${
          concatStringsSep "; " (map (item: item.message) findings)
        }";
      };

      warnings = map (item: item.message) findings;
    }

    (mkIf (enabled != { }) {
      services.pcscd.enable = true;
      hardware.gpgSmartcards.enable = true;

      environment.systemPackages = with pkgs; [
        age-plugin-yubikey
        auditPackage
        cryptsetup
        pam_u2f
        yubico-piv-tool
        yubikey-manager
      ];

      users.users.root.openssh.authorizedKeys.keys = rootSshKeys;

      security.pam.u2f = mkIf (pamEntries != [ ]) {
        enable = true;
        control = "sufficient";
        settings = {
          authfile = pamAuthFile;
          cue = true;
          userpresence = 1;
          pinverification = 1;
        };
      };

      boot.initrd.luks.devices = genAttrs managedLuksNames (_: {
        crypttabExtraOpts = mkAfter [ "fido2-device=auto" ];
      });
    })
  ];
}
