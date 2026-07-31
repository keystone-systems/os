# Keystone OS Users Module
#
# Creates users with:
# - NixOS user accounts with proper groups and authentication
# - ZFS home directories with delegated permissions and quotas
# - Optional home-manager integration for terminal/desktop config
#
# SSH keys are read from keystone.keys.<username> — all host keys
# plus all hardware keys are added to authorized_keys.
#
{
  lib,
  config,
  pkgs,
  options,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  cfg = osCfg.users;
  adminUsername = osCfg.adminUsername;

  # CRITICAL: admin identity is a single fact. Exactly one user has admin =
  # true; that user owns adminUsername, which downstream derivations
  # (systemFlake.path, admin home directory) depend on. Authorization is
  # separate — add extraGroups = [ "wheel" ] to any other user that needs
  # sudo.
  adminUsersNames = filter (n: cfg.${n}.admin or false) (attrNames cfg);

  keysCfg = config.keystone.keys;
  hostname = config.networking.hostName;
  immichServiceCfg = config.keystone.services.immich;

  # Whether the keystone desktop NixOS module is imported (gates home-manager desktop config)
  hasDesktopModule = options.keystone ? desktop;
  desktopUsers = filterAttrs (_: userCfg: userCfg.desktop.enable) cfg;
  desktopUsernames = attrNames desktopUsers;
  inferredDesktopUser = if desktopUsernames == [ ] then null else head desktopUsernames;

  # Check if ZFS is being used
  # TODO: Re-evaluate ZFS home folder management. Current implementation can interfere with legacy setups.
  useZfs = osCfg.storage.type == "zfs" && osCfg.storage.enable;

  # Read from the _autoUserGroups sink (declared in the options block).
  # Capability modules (containers, hypervisor, etc.) append to this sink
  # with `mkIf cfg.enable`, and users.nix consumes it when building each
  # user's final extraGroups. Follows the "many producers, one consumer"
  # pattern that assertions/warnings use.
  #
  # NOTE: lives at keystone.os._autoUserGroups (not keystone.os.users._autoGroups
  # as the originating issue sketched) because keystone.os.users is typed
  # `attrsOf userSubmodule` and cannot host a non-user attribute without
  # breaking that type discipline. See conventions/process.user-groups.md.
  autoGroups = osCfg._autoUserGroups;

  # Public keys valid on a specific host for a user
  # (that host's software key + all hardware keys)
  keysForUserOnHost =
    username: hn:
    let
      u = keysCfg.${username};
      hostKey = optional (u.hosts ? ${hn}) u.hosts.${hn}.publicKey;
    in
    hostKey ++ u.hwKeys;

  screenshotUsers = filterAttrs (
    _: userCfg: userCfg.desktop.enable && userCfg.desktop.screenshotSync.enable
  ) cfg;

  immichServerUrl =
    let
      immichHostName = immichServiceCfg.host;
      hostEntry = findFirst (h: h.hostname == immichHostName) null (attrValues config.keystone.hosts);
      hostTarget =
        if hostEntry == null then
          immichHostName
        else if hostEntry.tailscaleIP != null then
          hostEntry.tailscaleIP
        else if hostEntry.sshTarget != null then
          hostEntry.sshTarget
        else if hostEntry.fallbackIP != null then
          hostEntry.fallbackIP
        else
          immichHostName;
    in
    if config.keystone.domain != null then
      "https://photos.${config.keystone.domain}"
    else
      "http://${hostTarget}:2283";
in
{
  options.keystone.os._autoUserGroups = mkOption {
    internal = true;
    description = ''
      Private sink for module-owned supplementary groups. Capability
      modules (containers, hypervisor, hardware/media) append to the
      appropriate scope with `mkIf cfg.enable`; users.nix consumes the
      sink when building each user's final extraGroups.

      Scopes:
      - allUsers:     appended to every keystone.os.users entry
      - adminOnly:    appended only to the user flagged admin = true
      - desktopUsers: appended to every user with desktop.enable = true

      Lives at keystone.os._autoUserGroups rather than
      keystone.os.users._autoGroups because keystone.os.users is typed
      `attrsOf userSubmodule` and cannot host a non-user attribute.

      See conventions/process.user-groups.md.
    '';
    default = { };
    type = types.submodule {
      options = {
        allUsers = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Groups appended to every keystone-managed user.";
        };
        adminOnly = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Groups appended only to the user flagged admin = true.";
        };
        desktopUsers = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Groups appended to users with desktop.enable = true.";
        };
      };
    };
  };

  config = mkMerge [
    # Seed the auto-groups sink with the groups this module owns directly.
    # Capability modules (containers, hypervisor, etc.) append to the same
    # sink from their own config blocks — see conventions/process.user-groups.md.
    #
    # Desktop access groups (networkmanager, video, audio) land in
    # `desktopUsers`: every user with desktop.enable gets them. `zfs`
    # lands in `allUsers` whenever ZFS storage is in use — everyone needs
    # /dev/zfs access for their home dataset operations.
    #
    # `dialout` and `media` land in `adminOnly` unconditionally. The
    # admin-on-every-host pattern makes a separate enable gate redundant:
    # every keystone admin needs serial console access (Pi UART debug,
    # ESP32/RP2040/Arduino flashing, Zigbee/Z-Wave USB coordinators,
    # router/switch consoles) and media-pool ownership. See the
    # "Why admins get dialout" section of process.user-groups.md.
    (mkIf osCfg.enable {
      keystone.os._autoUserGroups = {
        allUsers = optionals useZfs [ "zfs" ];
        adminOnly = [
          "dialout"
          "media"
        ];
        desktopUsers = [
          "networkmanager"
          "video"
          "audio"
        ];
      };

      # `media` is NOT a standard nixpkgs group, unlike `dialout` (gid 27,
      # created by users-groups.nix). Declare it here so admin membership
      # references a real group. Consumer flakes that provision media
      # pools should chown/chmod against `media`; no module currently
      # pins the gid.
      users.groups.media = { };
    })

    (mkIf (osCfg.enable && cfg != { }) {
      # Enable ZFS delegation for non-root users (only if using ZFS)
      boot.extraModprobeConfig = mkIf useZfs ''
        options zfs zfs_admin_snapshot=1
      '';

      # Create zfs group for /dev/zfs access
      users.groups.zfs = mkIf useZfs { };

      # Set /dev/zfs permissions
      services.udev.extraRules = mkIf useZfs ''
        KERNEL=="zfs", MODE="0660", GROUP="zfs"
      '';

      # Assertions
      assertions = [
        {
          assertion = length adminUsersNames == 1;
          message =
            if adminUsersNames == [ ] then
              ''
                Keystone OS requires an administrator. Set admin = true on
                exactly one entry in keystone.os.users.
              ''
            else
              ''
                Multiple users are flagged keystone.os.users.<name>.admin = true:
                ${concatStringsSep ", " adminUsersNames}.

                Exactly one user must be the admin — it owns adminUsername and
                downstream path derivations. Give the others
                extraGroups = [ "wheel" ] if they need sudo.
              '';
        }
        {
          # adminUsername must name the admin-flagged user. Explicit assignments
          # still win (via mkDefault in default.nix) but cannot drift from the
          # flag — silent mismatch would break systemFlake.path.
          assertion = adminUsersNames == [ ] || elem adminUsername adminUsersNames;
          message = ''
            keystone.os.adminUsername = "${adminUsername}" but that user is
            not flagged admin = true. Set admin = true on
            keystone.os.users.${adminUsername} or remove the explicit
            adminUsername assignment.
          '';
        }
        {
          assertion =
            !useZfs
            || (
              config.boot.supportedFilesystems ? "zfs" || elem "zfs" (attrNames config.boot.supportedFilesystems)
            );
          message = "ZFS must be enabled when using ZFS storage";
        }
        {
          assertion =
            let
              uids = filter (u: u != null) (mapAttrsToList (_: u: u.uid) cfg);
              uniqueUids = unique uids;
            in
            length uids == length uniqueUids;
          message = "All user UIDs must be unique";
        }
      ]
      ++ concatLists (
        mapAttrsToList (
          username: userCfg:
          optional userCfg.desktop.screenshotSync.enable {
            assertion = userCfg.desktop.enable;
            message = "User '${username}' enables desktop.screenshotSync but desktop.enable is false.";
          }
        ) cfg
      )
      ++ optionals (screenshotUsers != { }) [
        {
          assertion = immichServiceCfg.host != null;
          message = "Desktop screenshot sync requires keystone.services.immich.host to be set.";
        }
      ]
      # Validate agenix secret exists when sshAutoLoad is enabled
      # (auto-declared below when secrets.repo is set, so this only fires
      # when secrets.repo is null and no manual declaration exists)
      ++ concatLists (
        mapAttrsToList (
          username: userCfg:
          optional userCfg.sshAutoLoad.enable {
            assertion = config.age.secrets ? "${hostname}-ssh-passphrase";
            message = ''
              User '${username}' has sshAutoLoad enabled but the secret file "${hostname}-ssh-passphrase.age" is missing.

              1. Add to agenix-secrets/secrets.nix:
                 "secrets/${hostname}-ssh-passphrase.age".publicKeys = adminKeys ++ [ systems.${hostname} ];

              2. Create the secret (enter the SSH key passphrase):
                 cd agenix-secrets && agenix -e secrets/${hostname}-ssh-passphrase.age

              3. Commit, push, and update flake:
                 git add -A && git commit -m "Add ${hostname} SSH passphrase" && git push
                 cd .. && nix flake update agenix-secrets

              If keystone.secrets.repo is set, the age.secrets declaration is automatic.
              Otherwise, add manually to host config:
                age.secrets.${hostname}-ssh-passphrase = {
                  file = "${"$"}{inputs.agenix-secrets}/secrets/${hostname}-ssh-passphrase.age";
                  owner = "${username}";
                  mode = "0400";
                };
            '';
          }
        ) cfg
      );

      warnings =
        concatLists (
          mapAttrsToList (
            username: userCfg:
            optional
              (userCfg.desktop.screenshotSync.enable && !(config.age.secrets ? "${username}-immich-api-key"))
              ''
                Screenshot sync is enabled for user '${username}', but agenix secret "${username}-immich-api-key" is not declared yet.

                To finish setup:
                1. Add to agenix-secrets/secrets.nix:
                   "secrets/${username}-immich-api-key.age".publicKeys = adminKeys ++ [ systems.${hostname} ];
                2. Create the secret with the user's Immich API key:
                   cd agenix-secrets && agenix -e secrets/${username}-immich-api-key.age
                3. If keystone.secrets.repo is null, declare it in host config:
                   age.secrets.${username}-immich-api-key = {
                     file = "${"$"}{inputs.agenix-secrets}/secrets/${username}-immich-api-key.age";
                     owner = "${username}";
                     mode = "0400";
                   };

                TODO: automate Immich API key provisioning and secret enrollment from Keystone tooling.
              ''
          ) screenshotUsers
        )
        ++ optional (hasDesktopModule && length desktopUsernames > 1) ''
          Multiple users have keystone.os.users.<name>.desktop.enable = true. Keystone defaulted keystone.desktop.user to "${inferredDesktopUser}".

          Set keystone.desktop.user explicitly if a different desktop login user should own the session.
        ''
        # Shadow warning: a user's explicit extraGroups entry is
        # already auto-granted by keystone. Surface it so consumers
        # can shrink their lists.
        ++ concatLists (
          mapAttrsToList (
            username: userCfg:
            let
              # Mirror the grant layering in users.users.<name>.extraGroups
              # below: wheel comes from `admin = true` (separate from the
              # sink), the other three come from the _autoUserGroups sink.
              autoForUser =
                optionals userCfg.admin [ "wheel" ]
                ++ autoGroups.allUsers
                ++ optionals userCfg.admin autoGroups.adminOnly
                ++ optionals (hasDesktopModule && userCfg.desktop.enable) autoGroups.desktopUsers;
              shadowed = filter (g: elem g autoForUser) userCfg.extraGroups;
            in
            optional (shadowed != [ ]) ''
              User '${username}' has extraGroups entries already auto-granted by keystone: ${concatStringsSep ", " shadowed}.

              Remove them from keystone.os.users.${username}.extraGroups — they come from module wiring (see conventions/process.user-groups.md).
            ''
          ) cfg
        );

      # Auto-declare age.secrets for sshAutoLoad when secrets.repo is set
      age.secrets = mkIf (config.keystone.secrets.repo != null) (
        listToAttrs (
          concatLists (
            mapAttrsToList (
              username: userCfg:
              (optional userCfg.sshAutoLoad.enable (
                nameValuePair "${hostname}-ssh-passphrase" {
                  file = "${config.keystone.secrets.repo}/secrets/${hostname}-ssh-passphrase.age";
                  owner = username;
                  mode = "0400";
                }
              ))
              ++ (optional userCfg.desktop.screenshotSync.enable (
                nameValuePair "${username}-immich-api-key" {
                  file = "${config.keystone.secrets.repo}/secrets/${username}-immich-api-key.age";
                  owner = username;
                  mode = "0400";
                }
              ))
            ) cfg
          )
        )
      );

      # Enable zsh system-wide if any user has terminal enabled
      programs.zsh.enable = mkIf (any (u: u.terminal.enable) (attrValues cfg)) true;

      # Generate NixOS users.
      #
      # extraGroups layers in this order:
      #   1. user's explicit extraGroups (consumer override)
      #   2. "wheel" when admin = true (sudo authorization)
      #   3. autoGroups.allUsers      (applied to every user)
      #   4. autoGroups.adminOnly     (applied only when admin = true)
      #   5. autoGroups.desktopUsers  (applied when desktop.enable)
      #
      # Capability modules append to the autoGroups sink with `mkIf cfg.enable`.
      # See conventions/process.user-groups.md for the capability → group map.
      users.users = mapAttrs (username: userCfg: {
        isNormalUser = true;
        uid = userCfg.uid;
        description = userCfg.fullName;
        home = "/home/${username}";
        createHome = !useZfs; # Let ZFS dataset provide home when using ZFS
        extraGroups = unique (
          userCfg.extraGroups
          ++ optionals userCfg.admin [ "wheel" ]
          ++ autoGroups.allUsers
          ++ optionals userCfg.admin autoGroups.adminOnly
          ++ optionals (hasDesktopModule && userCfg.desktop.enable) autoGroups.desktopUsers
        );
        initialPassword = userCfg.initialPassword;
        hashedPassword = userCfg.hashedPassword;
        # Read all keys from keystone.keys registry
        openssh.authorizedKeys.keys = if keysCfg ? ${username} then keysCfg.${username}.allKeys else [ ];
        shell = mkIf userCfg.terminal.enable pkgs.zsh;
      }) cfg;

      # Home directory ownership for ext4 (ZFS handles this in its service)
      systemd.services.create-user-homes = mkIf (!useZfs) {
        description = "Create and configure user home directories";

        wantedBy = [ "multi-user.target" ];
        before = [
          "display-manager.service"
          "systemd-user-sessions.service"
        ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          ${concatStringsSep "\n" (
            mapAttrsToList (username: userCfg: ''
              if [ ! -d /home/${username} ]; then
                mkdir -p /home/${username}
              fi
              chown ${username}:users /home/${username}
              chmod 700 /home/${username}
            '') cfg
          )}
        '';
      };

      systemd.user.services = mkMerge (
        mapAttrsToList (
          username: userCfg:
          mkIf userCfg.desktop.screenshotSync.enable {
            "keystone-${username}-screenshot-sync" = {
              description = "Sync screenshots to Immich for ${username}";
              unitConfig.ConditionUser = username;
              serviceConfig = {
                Type = "oneshot";
                SyslogIdentifier = "keystone-screenshot-sync";
              };
              script = ''
                export HOME=/home/${username}
                export XDG_STATE_HOME="''${XDG_STATE_HOME:-$HOME/.local/state}"
                exec ${pkgs.keystone.ks}/bin/ks screenshots sync \
                  --url ${lib.escapeShellArg immichServerUrl} \
                  --api-key-file /run/agenix/${username}-immich-api-key \
                  --album-name ${lib.escapeShellArg "Screenshots - ${username}"} \
                  --host-name ${lib.escapeShellArg hostname} \
                  --account-name ${lib.escapeShellArg username} \
                  --state-file "''${XDG_STATE_HOME}/keystone-photos/screenshot-sync.tsv"
              '';
            };
          }
        ) screenshotUsers
      );

      systemd.user.timers = mkMerge (
        mapAttrsToList (
          username: userCfg:
          mkIf userCfg.desktop.screenshotSync.enable {
            "keystone-${username}-screenshot-sync" = {
              wantedBy = [ "default.target" ];
              unitConfig.ConditionUser = username;
              timerConfig = {
                OnCalendar = userCfg.desktop.screenshotSync.syncOnCalendar;
                Persistent = true;
              };
            };
          }
        ) screenshotUsers
      );
    })

    # Configure home-manager for users with terminal/desktop enabled
    # This requires home-manager to be imported in the system configuration
    # NOTE: This must be a separate mkMerge entry, not merged with // into the
    # mkIf block above. Using // on a mkIf value silently drops the merged keys
    # because the module system only reads the mkIf's `content` attribute.
    (optionalAttrs (options ? home-manager) {
      home-manager =
        mkIf (osCfg.enable && cfg != { } && any (u: u.terminal.enable || u.desktop.enable) (attrValues cfg))
          {
            useGlobalPkgs = mkDefault true;
            useUserPackages = mkDefault true;

            users = mapAttrs (
              username: userCfg:
              { pkgs, ... }:
              # NOTE: use lib.recursiveUpdate (not //) to merge terminal and
              # desktop configs. Both live under `keystone.*`, so a shallow //
              # merge causes `keystone.desktop` to replace `keystone.terminal`.
              lib.recursiveUpdate
                {
                  home.username = username;
                  home.homeDirectory = "/home/${username}";
                  home.stateVersion = config.system.stateVersion;

                  # Terminal development environment
                  # NOTE: Do NOT wrap this in mkIf — mkIf inside function-type
                  # home-manager.users definitions silently fails to merge when
                  # another module also defines the same user. Use mkDefault on
                  # enable instead; the terminal module's own config = mkIf cfg.enable
                  # handles gating.
                  keystone.terminal = {
                    enable = mkDefault userCfg.terminal.enable;
                    aiExtensions.enable = mkDefault (userCfg.capabilities != [ ]);
                    aiExtensions.capabilities = mkDefault userCfg.capabilities;

                    # development and repos are no longer bridged here;
                    # they are inherited globally from keystone.development
                    # and keystone.repos which are now shared options.

                    git = {
                      enable = mkDefault (userCfg.terminal.enable && userCfg.email != null);
                      userName = mkDefault userCfg.fullName;
                      userEmail = mkDefault userCfg.email;
                      # Bridge SSH public keys from keystone.keys for allowed_signers
                      sshPublicKeys = mkDefault (if keysCfg ? ${username} then keysCfg.${username}.allKeys else [ ]);
                      forgejo.enable = mkDefault (config.keystone.services.git.host != null);
                    };

                    # rbw (Bitwarden CLI) auto-enables when the fleet declares
                    # a Vaultwarden host AND a domain (otherwise rbw would
                    # silently fall back to the official Bitwarden service).
                    secrets = {
                      enable = mkDefault (
                        userCfg.terminal.enable
                        && userCfg.email != null
                        && config.keystone.services.vaultwarden.host != null
                        && config.keystone.services.vaultwarden.domain != null
                      );
                      email = mkDefault (if userCfg.email != null then userCfg.email else "");
                      baseUrl = mkDefault (
                        if config.keystone.services.vaultwarden.domain != null then
                          "https://${config.keystone.services.vaultwarden.domain}"
                        else
                          ""
                      );
                    };

                    sshAutoLoad.enable = mkDefault userCfg.sshAutoLoad.enable;
                  };
                }
                (
                  optionalAttrs hasDesktopModule {
                    # Desktop configuration (Hyprland) — only set when desktop NixOS module is imported
                    keystone.desktop = mkIf userCfg.desktop.enable {
                      enable = mkDefault true;
                      uhk.enable = mkDefault config.keystone.hardware.uhk.enable;
                      hyprland = {
                        modifierKey = mkDefault userCfg.desktop.hyprland.modifierKey;
                        capslockAsControl = mkDefault userCfg.desktop.hyprland.capslockAsControl;
                      };
                    };
                  }
                )
            ) (filterAttrs (_: u: u.terminal.enable || u.desktop.enable) cfg);
          };
    })

    # Bridge per-user desktop intent into the top-level desktop module when it is imported.
    (optionalAttrs hasDesktopModule {
      keystone.desktop = mkIf (osCfg.enable && desktopUsernames != [ ]) {
        enable = mkDefault true;
        user = mkDefault inferredDesktopUser;
      };
    })
  ];
}
