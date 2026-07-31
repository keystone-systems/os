# Keystone OS - Unified Operating System Module
#
# Implements REQ-001 (Keystone OS)
#
# This module consolidates all OS-level configuration for Keystone:
# - Storage (ZFS/ext4 with encryption)
# - Secure Boot (Lanzaboote)
# - TPM enrollment
# - Remote unlock (initrd SSH)
# - User management (NixOS users + home-manager + ZFS homes)
#
# Usage:
#   keystone.os = {
#     enable = true;
#     storage.devices = [ "/dev/disk/by-id/..." ];
#     users.alice = {
#       fullName = "Alice";
#       email = "alice@example.com";
#       admin = true;  # Exactly one user MUST be flagged admin.
#     };
#   };
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.os;

  # Look up the current host in the registry to access per-host metadata (e.g. baremetal).
  currentHost = findFirst (h: h.hostname == config.networking.hostName) null (
    attrValues config.keystone.hosts
  );
  isBaremetal = currentHost != null && currentHost.baremetal;

  # Users explicitly flagged as the fleet administrator.
  #
  # CRITICAL: adminUsername and downstream path derivations (systemFlake.path,
  # admin home directory) need a single unambiguous admin. The users.nix
  # assertions enforce that exactly one user has admin = true; the derivation
  # below reads this list without touching adminUsername so there is no cycle
  # between the option and its consumers.
  adminFlaggedUserNames = filter (n: cfg.users.${n}.admin or false) (attrNames cfg.users);

  fullNameFor = name: config.keystone.os.users.${name}.fullName;

  # User submodule type definition
  userSubmodule = types.submodule (
    { name, ... }:
    {
      options = {
        uid = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = "User ID. If null, NixOS will auto-assign.";
        };

        fullName = mkOption {
          type = types.str;
          description = "Full name of the user (used for GECOS and git config)";
          example = "Alice Smith";
        };

        email = mkOption {
          type = types.nullOr types.str;
          default =
            let
              domain = config.keystone.domain;
              # "Alice Smith" → "alice.smith"
              localPart = builtins.replaceStrings [ " " ] [ "." ] (lib.toLower (fullNameFor name));
            in
            if domain != null then "${localPart}@${domain}" else null;
          defaultText = literalExpression ''"''${toLower fullName}@''${keystone.domain}"'';
          description = "Email address (used for git config and mail). Auto-derived from fullName + keystone.domain.";
          example = "alice.smith@example.com";
        };

        extraGroups = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Additional groups the user should be a member of";
          example = [
            "wheel"
            "networkmanager"
          ];
        };

        admin = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Designate this user as the fleet administrator.

            Exactly one user across keystone.os.users MUST have admin = true.
            Admin users are automatically added to the wheel group, and their
            username becomes the default for keystone.os.adminUsername.

            Give additional users that need sudo but are not the canonical
            admin their own extraGroups = [ "wheel" ] — admin-ness is an
            identity fact (path derivations, home directory), not an
            authorization fact.
          '';
        };

        initialPassword = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Initial plaintext password. WARNING: Stored in Nix store. Use hashedPassword for production.";
        };

        hashedPassword = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Hashed password (generate with mkpasswd -m sha-512)";
        };

        terminal = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable terminal development environment (zsh, helix, zellij, starship, git)";
          };
        };

        capabilities = mkOption {
          type = types.listOf (
            types.enum [
              "ks"
              "ks-dev"
              "assistant"
              "notes"
              "project"
              "engineer"
              "product"
              "project-manager"
              "executive-assistant"
            ]
          );
          default = [ ];
          description = ''
            Extra Keystone AI workflow capabilities for this user. These
            capabilities are merged with default terminal capabilities and
            determine what the generated `/ks` and `/ks-dev` commands may do.
          '';
          example = [
            "notes"
            "executive-assistant"
          ];
        };

        sshAutoLoad = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Auto-load SSH key into ssh-agent at login using agenix passphrase";
          };
        };

        desktop = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable desktop environment (Hyprland, waybar, etc.)";
          };

          screenshotSync = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = "Enable screenshot syncing to Immich for this desktop user.";
            };

            syncOnCalendar = mkOption {
              type = types.str;
              default = "*:0/5";
              description = "Systemd calendar expression for screenshot sync interval.";
            };
          };

          hyprland = {
            modifierKey = mkOption {
              type = types.enum [
                "SUPER"
                "ALT"
              ];
              default = "SUPER";
              description = "Primary modifier key for Hyprland keybindings";
            };

            capslockAsControl = mkOption {
              type = types.bool;
              default = true;
              description = "Remap Caps Lock to Control";
            };
          };
        };

        zfs = {
          quota = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "ZFS quota for user's home dataset (e.g., '100G', '1T')";
            example = "100G";
          };

          compression = mkOption {
            type = types.enum [
              "off"
              "on"
              "lz4"
              "gzip"
              "zstd"
              "zstd-fast"
              "lzjb"
            ];
            default = "lz4";
            description = "Compression algorithm for user's home dataset";
          };

          recordsize = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Block size for the dataset (128K default, 1M for large files, 16K for databases)";
          };

          atime = mkOption {
            type = types.enum [
              "on"
              "off"
            ];
            default = "off";
            description = "Whether to update access time on file reads";
          };
        };
      };
    }
  );
in
{
  imports = [
    ../keys.nix
    ../secrets.nix
    ../shared/system-flake.nix
    ./notifications.nix
    ./storage.nix
    ./secure-boot.nix
    ./tpm.nix
    ./zram.nix
    ./github-token-nix.nix
    ./hardware-key.nix
    ./privileged-approval.nix
    ./uhk.nix
    ./remote-unlock.nix
    ./users.nix
    ./ssh.nix
    ./eternal-terminal.nix
    ./airplay.nix
    ./mail.nix
    ./git-server
    ./agents
    ./hypervisor.nix
    ./iphone-tether.nix
    ./ollama.nix
    ./immich.nix
    ./tailscale.nix
    ./containers.nix
    ./journal-remote.nix
    ./alloy.nix
    ./observability.nix
    ./zfs-backup.nix
  ];

  options.keystone.os = {
    enable = mkEnableOption "Keystone OS - secure storage, boot, and user management";

    # Storage configuration
    storage = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable storage/disk management. Disable for testing environments with external storage.";
      };

      type = mkOption {
        type = types.enum [
          "zfs"
          "ext4"
        ];
        default = "zfs";
        description = ''
          Filesystem type for the root pool.
          - zfs: Full features (snapshots, compression, checksums, native encryption)
          - ext4: Simple/legacy (LUKS encryption only, no advanced features)
        '';
      };

      devices = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB" ];
        description = ''
          Disk devices for the storage pool. Use by-id paths for stability.
          For multi-disk configurations, specify multiple devices and set mode.
        '';
      };

      mode = mkOption {
        type = types.enum [
          "single"
          "mirror"
          "stripe"
          "raidz1"
          "raidz2"
          "raidz3"
        ];
        default = "single";
        description = ''
          Redundancy mode for multi-disk ZFS configurations:
          - single: No redundancy (single disk or concatenated)
          - mirror: All disks mirror each other (RAID1)
          - stripe: Data striped across disks (RAID0, no redundancy)
          - raidz1: Single parity (RAID5 equivalent, min 3 disks)
          - raidz2: Double parity (RAID6 equivalent, min 4 disks)
          - raidz3: Triple parity (min 5 disks)
        '';
      };

      esp = {
        size = mkOption {
          type = types.str;
          default = "1G";
          description = "EFI System Partition size";
        };
      };

      swap = {
        size = mkOption {
          type = types.str;
          default = "8G";
          description = "Swap partition size. Set to '0' to disable swap.";
        };
      };

      hibernate = {
        enable = mkEnableOption "hibernation support (ext4 only)";
      };

      credstore = {
        size = mkOption {
          type = types.str;
          default = "100M";
          description = "LUKS credstore volume size (only for ZFS). Stores encryption keys.";
        };
      };

      zfs = {
        compression = mkOption {
          type = types.enum [
            "off"
            "lz4"
            "zstd"
            "gzip"
            "gzip-1"
            "gzip-9"
          ];
          default = "zstd";
          description = "Default compression algorithm for ZFS datasets";
        };

        atime = mkOption {
          type = types.enum [
            "on"
            "off"
          ];
          default = "off";
          description = "Whether to update access time on file reads";
        };

        arcMax = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Maximum ARC cache size (e.g., '4G'). Null for automatic.";
          example = "4G";
        };

        autoScrub = mkOption {
          type = types.bool;
          default = true;
          description = "Enable weekly ZFS integrity scrub";
        };

        kernel = mkOption {
          type = types.either (types.enum [
            "default"
            "latest"
          ]) types.raw;
          default = "latest";
          description = ''
            Kernel package selection for ZFS hosts:
            - "default": NixOS default kernel (linuxPackages)
            - "latest": Latest stable kernel (linuxPackages_latest)
            - Or a kernel packages set (e.g., pkgs.linuxPackages_6_12)
          '';
        };
      };
    };

    # Secure Boot configuration
    secureBoot = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Secure Boot with Lanzaboote";
      };
    };

    # TPM configuration
    tpm = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable TPM-based automatic disk unlock";
      };

      pcrs = mkOption {
        type = types.listOf types.int;
        default = [
          1
          7
        ];
        description = ''
          TPM PCRs to bind disk unlock to:
          - PCR 1: Firmware configuration
          - PCR 7: Secure Boot state
          Common alternatives: [7] for Secure Boot only (more update-resilient)
        '';
      };
    };

    # Remote unlock (initrd SSH)
    remoteUnlock = {
      enable = mkEnableOption "SSH remote disk unlock in initrd";

      authorizedKeys = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          SSH public keys for remote unlock.
          If empty, keys are collected from all configured users.
        '';
      };

      port = mkOption {
        type = types.port;
        default = 22;
        description = "SSH port for initrd remote unlock";
      };

      networkModule = mkOption {
        type = types.str;
        default = "virtio_net";
        description = "Network driver module to load in initrd";
        example = "e1000e";
      };

      dhcp = mkOption {
        type = types.bool;
        default = true;
        description = "Use DHCP for network configuration in initrd";
      };
    };

    # SSH server configuration
    ssh = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable SSH server for remote administration";
      };
    };

    # System services (moved from server module)
    services = {
      avahi = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable Avahi/mDNS for network discovery (.local hostnames)";
        };
      };

      firewall = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable basic firewall (SSH port is opened automatically)";
        };
      };

      eternalTerminal = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable Eternal Terminal (et) for persistent remote shell sessions that survive network changes";
        };

        port = mkOption {
          type = types.port;
          default = 2022;
          description = "Port for the Eternal Terminal daemon";
        };
      };

      # Previously defaulted to true for both server and desktop, but this conflicts
      # with AdGuard Home (and other DNS servers) binding to port 53. The desktop
      # module enables this automatically when needed for Tailscale MagicDNS.
      resolved = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable systemd-resolved for DNS resolution (enabled automatically by desktop module for Tailscale MagicDNS)";
        };
      };
    };

    # iPhone USB tethering
    iphoneTether = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable iOS USB tethering/hotspot support via libimobiledevice and usbmuxd";
      };
    };

    # Shared binary caches
    binaryCaches = {
      ksSystems = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable the shared Keystone Cachix cache on all Keystone systems by default.";
        };

        url = mkOption {
          type = types.str;
          default = "https://ks-systems.cachix.org";
          example = "https://my-team.cachix.org";
          description = "Cachix substituter URL for the shared Keystone systems cache.";
        };

        publicKey = mkOption {
          type = types.str;
          default = "ks-systems.cachix.org-1:Abbd38auzcLIfJUtX7kSD6zdGUU4v831Sb2KfajR5Mo=";
          description = "Public key used to verify binaries from the shared Keystone systems cache.";
        };
      };
    };

    # Nix configuration
    nix = {
      optimiseStore = mkOption {
        type = types.bool;
        default = true;
        description = "Enable automatic Nix store optimisation (deduplication)";
      };

      nh = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable nh for intelligent generation pruning";
        };
        clean = {
          keepSince = mkOption {
            type = types.str;
            default = "30d";
            description = "Keep generations newer than this duration";
          };
          keepGenerations = mkOption {
            type = types.int;
            default = 10;
            description = "Always keep at least this many generations";
          };
        };
      };

      flakes = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Nix flakes and nix-command";
      };
    };

    # User configuration
    adminUsername = mkOption {
      type = types.str;
      default = "admin";
      defaultText = literalExpression ''
        The name of the keystone.os.users.<name> entry with admin = true.
        Falls back to the literal "admin" only when no user is flagged —
        which is itself a configuration error caught by assertion.
      '';
      description = ''
        Unix username for the administrator account.

        By default this derives from the user flagged
        keystone.os.users.<name>.admin = true. An explicit assignment still
        wins (via mkDefault), but MUST name the admin-flagged user —
        otherwise evaluation fails with an assertion pointing at the drift.

        Set via admin.username in mkSystemFlake.
      '';
      example = "noah";
    };

    users = mkOption {
      type = types.attrsOf userSubmodule;
      default = { };
      description = ''
        Users with automatic NixOS user creation, home-manager integration,
        and ZFS home directories with delegated permissions.
      '';
      example = literalExpression ''
        {
          alice = {
            fullName = "Alice Smith";
            email = "alice@example.com";
            extraGroups = [ "networkmanager" ];
            terminal.enable = true;
            desktop.enable = true;
            zfs.quota = "100G";
          };
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    keystone.security.privilegedApproval.enable = mkDefault true;

    # Default home-manager to back up clobbered files instead of
    # aborting activation. Keystone manages a lot of dotfiles
    # (hyprland.conf, waybar.css, ghostty config, mako, etc.) so the
    # very first activation on a host that was provisioned
    # out-of-band — or migrated from another config — reliably hits
    # file conflicts under ~/.config that the operator hasn't
    # cleaned. Without a backup extension, the entire activation
    # fails (exit 4 on switch-to-configuration) instead of the
    # conflicts being moved aside. mkDefault leaves operators free
    # to override to a different suffix or to `force = true` per
    # file.
    home-manager.backupFileExtension = mkDefault "hm-backup";

    # Derive adminUsername from the user flagged admin = true.
    # mkDefault keeps explicit assignments winning; consistency with the
    # admin flag is validated by assertions in modules/os/users.nix.
    keystone.os.adminUsername = mkIf (adminFlaggedUserNames != [ ]) (
      mkDefault (head adminFlaggedUserNames)
    );

    nix.settings.substituters = mkIf cfg.binaryCaches.ksSystems.enable (mkBefore [
      cfg.binaryCaches.ksSystems.url
    ]);
    nix.settings.trusted-public-keys = mkIf cfg.binaryCaches.ksSystems.enable (mkBefore [
      cfg.binaryCaches.ksSystems.publicKey
    ]);

    # Assertions for configuration validation
    assertions = [
      # Storage assertions (only when storage is enabled)
      {
        assertion = !cfg.storage.enable || cfg.storage.devices != [ ];
        message = "keystone.os.storage.devices must contain at least one disk device";
      }
      {
        assertion =
          !cfg.storage.enable
          || cfg.storage.type == "ext4"
          || cfg.storage.mode == "single"
          || length cfg.storage.devices >= 2;
        message = "Multi-disk modes (mirror, stripe, raidz*) require at least 2 devices";
      }
      {
        assertion = !cfg.storage.enable || cfg.storage.mode != "raidz1" || length cfg.storage.devices >= 3;
        message = "raidz1 requires at least 3 devices";
      }
      {
        assertion = !cfg.storage.enable || cfg.storage.mode != "raidz2" || length cfg.storage.devices >= 4;
        message = "raidz2 requires at least 4 devices";
      }
      {
        assertion = !cfg.storage.enable || cfg.storage.mode != "raidz3" || length cfg.storage.devices >= 5;
        message = "raidz3 requires at least 5 devices";
      }
      {
        assertion = !cfg.storage.enable || cfg.storage.type == "ext4" -> cfg.storage.mode == "single";
        message = "ext4 only supports single-disk mode";
      }
      # Non-storage assertions
      {
        assertion = cfg.remoteUnlock.enable -> (cfg.remoteUnlock.authorizedKeys != [ ] || cfg.users != { });
        message = "Remote unlock requires authorizedKeys or at least one configured user with keys in keystone.keys";
      }
      {
        assertion = cfg.tpm.enable -> cfg.secureBoot.enable;
        message = "TPM enrollment requires Secure Boot to be enabled";
      }
      {
        assertion = all (pcr: pcr >= 0 && pcr <= 23) cfg.tpm.pcrs;
        message = "TPM PCR values must be in the range 0-23";
      }
      # Hibernation assertions
      {
        assertion = !cfg.storage.hibernate.enable || cfg.storage.type == "ext4";
        message = "Hibernation requires ext4 storage backend. ZFS cannot support hibernation because dirty writes after freeze corrupt pools.";
      }
      {
        assertion =
          !cfg.storage.hibernate.enable || cfg.storage.swap.size != "0" && cfg.storage.swap.size != "";
        message = "Hibernation requires swap to be enabled (storage.swap.size must not be '0' or empty)";
      }
    ];

    # Avahi/mDNS configuration
    services.avahi = mkIf cfg.services.avahi.enable {
      enable = true;
      nssmdns4 = true;
      nssmdns6 = true;
      publish = {
        enable = true;
        addresses = true;
        domain = true;
        hinfo = true;
        userServices = true;
        workstation = true;
      };
    };

    # Firewall configuration
    networking.firewall.enable = cfg.services.firewall.enable;

    # DNS resolution
    services.resolved.enable = cfg.services.resolved.enable;

    # Nix configuration
    nix.settings.experimental-features = mkIf cfg.nix.flakes [
      "nix-command"
      "flakes"
    ];
    nix.settings.auto-optimise-store = cfg.nix.optimiseStore;

    # nh clean replaces nix.gc with generation-count awareness:
    # nix.gc only prunes by age, so a burst of rebuilds can leave zero rollback
    # generations. nh always retains keepGenerations regardless of age.
    programs.nh = mkIf cfg.nix.nh.enable {
      enable = true;
      clean = {
        enable = true;
        extraArgs = "--keep-since ${cfg.nix.nh.clean.keepSince} --keep ${toString cfg.nix.nh.clean.keepGenerations}";
      };
    };

    # Locale defaults
    time.timeZone = lib.mkDefault "UTC";
    i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

    environment.systemPackages = [
      pkgs.keystone.agenix
    ]
    ++ lib.optionals isBaremetal [ pkgs.lm_sensors ];
  };
}
