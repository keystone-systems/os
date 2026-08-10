{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    any
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
    removeSuffix
    splitString
    take
    types
    unique
    ;

  enabled = config.keystone.hardwareKeys;
  registrations = config.keystone.hardwareKeyRegistrations;
  installedState = config.keystone.hardwareKeyState;
  keys = config.keystone.keys;
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

  sshPublicIdentity =
    value:
    concatStringsSep " " (
      take 2 (filter (part: part != "") (splitString " " (removeSuffix "\n" value)))
    );
  declaredSshHandles = concatLists (
    mapAttrsToList (
      username: userKeys:
      mapAttrsToList (
        name: key:
        let
          localUser = if config.users.users ? ${username} then config.users.users.${username} else null;
          registration = registrations.${name} or null;
        in
        {
          inherit
            key
            localUser
            name
            registration
            username
            ;
          serial = enabled.${name} or null;
          destination = if localUser == null then null else "${localUser.home}/.ssh/id_ed25519_sk_${name}";
        }
      ) userKeys.hardwareKeys
    ) keys
  );
  enabledSshHandles = filter (entry: entry.serial != null) declaredSshHandles;
  localSshHandles = filter (
    entry:
    entry.localUser != null
    && entry.registration != null
    && entry.registration.owner == entry.username
    && entry.key.handleSource != null
  ) enabledSshHandles;
  localSshOwners = unique (map (entry: entry.owner) localEntries);
  localSshHandlesFor = username: filter (entry: entry.username == username) localSshHandles;
  sshHandleAssertions = concatMap (
    entry:
    optional (entry.key.handleSource != null && entry.serial != null) {
      assertion = entry.registration != null && entry.registration.owner == entry.username;
      message = "enabled hardware key '${entry.name}' must register '${entry.username}' as its owner before Keystone installs its SSH handle";
    }
    ++
      optional
        (
          entry.key.handleSource != null
          && entry.serial != null
          && entry.registration != null
          && entry.registration.owner == entry.username
        )
        {
          assertion = any (
            publicKey: sshPublicIdentity publicKey == sshPublicIdentity entry.key.publicKey
          ) entry.registration.sshPublicKeys;
          message = "hardware key '${entry.name}' SSH public key does not match its public registration";
        }
  ) declaredSshHandles;
  sshHandleRules = concatMap (
    entry:
    let
      group = if entry.localUser.group == null then "users" else entry.localUser.group;
    in
    [
      "L+ ${entry.destination} - ${entry.username} ${group} - ${entry.key.handleSource}"
      "L+ ${entry.destination}.pub - ${entry.username} ${group} - ${pkgs.writeText "keystone-${entry.username}-${entry.name}.pub" "${entry.key.publicKey}\n"}"
    ]
  ) localSshHandles;
  sshDirectoryRules = map (
    username:
    let
      user = config.users.users.${username};
      group = if user.group == null then "users" else user.group;
    in
    "d ${user.home}/.ssh 0700 ${username} ${group} -"
  ) localSshOwners;
  rootSshClientConfig = concatStringsSep "\n" (
    map (
      username:
      concatStringsSep "\n" (
        [
          ''
            Match localuser ${username} user root
              IdentitiesOnly yes
              IdentityAgent none
              IdentityFile none
          ''
        ]
        ++ map (entry: ''
          Match localuser ${username} user root exec "${pkgs.bash}/bin/bash -o pipefail -c '${pkgs.yubikey-manager}/bin/ykman list --serials 2>/dev/null | ${pkgs.gnugrep}/bin/grep -Fxq -- ${entry.serial}'"
            IdentityFile ${entry.destination}
        '') (localSshHandlesFor username)
      )
    ) localSshOwners
  );

  managedLuksNames = config.keystone.hardwareKeyLuksTargets;
  luksNames = unique managedLuksNames;

  # A declared LUKS target states intent. It does not prove that a token is
  # enrolled in that header. Keep the two apart: `enrolledLuksNames` holds only
  # the targets whose recorded state proves an enrollment for an enabled key.
  luksEnrollments = name: installedState.luks.${name}.enrollments or { };
  targetAssumesEnrolled = name: installedState.luks.${name}.assumeEnrolled or false;
  hasEnabledEnrollment =
    name:
    targetAssumesEnrolled name
    || any (keyName: enabled ? ${keyName}) (attrNames (luksEnrollments name));
  enrolledLuksNames = filter hasEnabledEnrollment luksNames;

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

  sshHandleFindings = concatMap (
    entry:
    optional
      (
        entry.sshPublicKeys != [ ]
        && !(any (handle: handle.name == entry.name && handle.username == entry.owner) localSshHandles)
      )
      (
        finding "KSC-001.4/missing-ssh-handle" ''
          hardware key '${entry.name}' can authenticate root, but local user '${entry.owner}' has no matching OpenSSH security-key handle.
          Set keystone.keys.${entry.owner}.hardwareKeys.${entry.name}.handleSource.
        ''
      )
  ) localEntries;

  missingLuksFindings = concatMap (
    luksName:
    let
      targetState = installedState.luks.${luksName} or null;
    in
    map (
      name:
      finding "KSC-001.4/missing-luks-enrollment" ''
        hardware key '${name}' is enabled, but Keystone has no enrollment record for LUKS target '${luksName}'.
        Keystone does not add fido2-device=auto to this target, so the host unlocks with the passphrase.
        To use FIDO2 unlock, do these steps:
          1. Enroll the key: systemd-cryptenroll <device> --fido2-device=auto
          2. Record the token and credential in keystone.hardwareKeyState.luks.${luksName}.enrollments.${name}
      ''
    ) (filter (name: targetState == null || !(targetState.enrollments ? ${name})) enabledNames)
  ) luksNames;

  staleLuksFindings = concatLists (
    mapAttrsToList (
      luksName: state:
      optional (!(config.boot.initrd.luks.devices ? ${luksName})) (
        finding "KSC-001.4/stale-luks-target" ''
          hardware-key state records LUKS target '${luksName}', but no configuration defines that target.
          Delete the record, or add the target back.
        ''
      )
      ++ map (
        name:
        finding "KSC-001.4/stale-luks-enrollment" ''
          hardware key '${name}' is disabled, but LUKS target '${luksName}' still records an enrollment for it.
          The key can still unlock this volume.
          To remove access, wipe the LUKS token on the host. Then delete the enrollment record.
        ''
      ) (filter (name: !(enabled ? ${name})) (attrNames state.enrollments))
    ) installedState.luks
  );

  findings = registrationFindings ++ sshHandleFindings ++ missingLuksFindings ++ staleLuksFindings;

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
                assumeEnrolled = mkOption {
                  type = types.bool;
                  default = false;
                  description = ''
                    Set this option to true when a FIDO2 token is enrolled but no
                    credential appears in "enrollments". Use it only for volumes
                    that an installer enrolls. The installer creates the credential
                    after Nix evaluation, so Nix cannot record it.

                    This option turns off the enrollment check. If no token is
                    enrolled, the host does not boot. Record the credential in
                    "enrollments" when you can.
                  '';
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

      # FIDO2/U2F device access: libfido2 ships the 70-u2f uaccess rule that
      # grants the active seat access to CTAP hidraw nodes. Without it only
      # root can open the device and every ssh-sk / systemd-cryptenroll
      # operation fails with "agent refused operation" — the smartcard
      # (scdaemon) path works while the FIDO path silently does not.
      services.udev.packages = [ pkgs.libfido2 ];

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
      ++ sshHandleAssertions
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

      systemd.tmpfiles.rules = sshDirectoryRules ++ sshHandleRules;

      programs.ssh.extraConfig = mkAfter rootSshClientConfig;

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

      # `fido2-device=auto` tells the initrd that a FIDO2 token is enrolled in
      # this LUKS header. Do not add the option only because a target is
      # declared. If no token is enrolled, systemd does not fall back to the
      # passphrase. The initrd fails and the host does not boot. See systemd
      # issue 19872. This stopped ncrmro-workstation generations 637 to 641.
      # Add the option only when recorded state shows an enrollment.
      boot.initrd.luks.devices = genAttrs enrolledLuksNames (_: {
        crypttabExtraOpts = mkAfter [ "fido2-device=auto" ];
      });
    })
  ];
}
