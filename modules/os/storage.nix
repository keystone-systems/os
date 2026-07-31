# Keystone OS Storage Module
#
# Handles disk partitioning and encryption via disko:
# - ZFS pools (single disk, mirror, stripe, raidz1/2/3)
# - ext4 with LUKS encryption
# - Credstore pattern for key management
# - SystemD initrd services for secure boot unlock
#
# See conventions/os.zfs-backup.md
# Implements REQ-001 FR-005 (Copy-on-Write Storage), FR-006 (Storage Backend Selection)
#
{
  lib,
  config,
  pkgs,
  utils,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  cfg = osCfg.storage;

  # Helper to check if swap is enabled
  enableSwap = cfg.swap.size != "0" && cfg.swap.size != "";

  # Helper to get first device (for single disk or lead device in multi-disk)
  firstDevice = if cfg.devices != [ ] then elemAt cfg.devices 0 else "/dev/null";

  # Compute device directory for ZFS import (matches devNodes)
  importDir = builtins.dirOf firstDevice;

  # Convert arcMax to bytes for kernel param
  arcMaxBytes =
    let
      # Parse size string like "4G" or "8G"
      parseSize =
        s:
        if hasSuffix "G" s then
          (toInt (removeSuffix "G" s)) * 1024 * 1024 * 1024
        else if hasSuffix "M" s then
          (toInt (removeSuffix "M" s)) * 1024 * 1024
        else
          toInt s;
    in
    if cfg.zfs.arcMax != null then parseSize cfg.zfs.arcMax else 4 * 1024 * 1024 * 1024; # Default 4GB

  # Build ZFS vdev type based on mode and device count
  zfsVdevType =
    if cfg.mode == "single" then
      ""
    else if cfg.mode == "mirror" then
      "mirror"
    else if cfg.mode == "stripe" then
      ""
    else
      cfg.mode; # raidz1, raidz2, raidz3

  # Generate device list for systemd dependencies
  deviceUnits = map (p: utils.escapeSystemdPath p + ".device") cfg.devices;
in
{
  config = mkMerge [
    # ZFS configuration
    (mkIf (osCfg.enable && cfg.enable && cfg.type == "zfs") {
      # Ensure ZFS support is enabled
      boot.supportedFilesystems = [ "zfs" ];

      # Kernel selection — latest by default for hardware support
      boot.kernelPackages =
        if cfg.zfs.kernel == "latest" then
          pkgs.linuxPackages_latest
        else if cfg.zfs.kernel == "default" then
          pkgs.linuxPackages
        else
          cfg.zfs.kernel;

      # Build-time ZFS compatibility assertion
      assertions = [
        {
          assertion =
            let
              zfsAttr = config.boot.zfs.package.kernelModuleAttribute;
              zfsModule = config.boot.kernelPackages.${zfsAttr};
            in
            !(zfsModule.meta.broken or false);
          message = ''
            Kernel ${config.boot.kernelPackages.kernel.version} is incompatible with
            ZFS (${config.boot.zfs.package.version}).
            Pin a compatible kernel via keystone.os.storage.zfs.kernel, e.g.:
              keystone.os.storage.zfs.kernel = pkgs.linuxPackages_6_12;
          '';
        }
      ];

      # Boot loader configuration
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      # Complex initrd configuration for ZFS with encrypted credstore
      boot.initrd = {
        # SystemD initrd is required for complex service orchestration
        systemd.enable = true;
        systemd.emergencyAccess = lib.mkDefault false;

        # Disable NixOS's default zfs-import service
        systemd.services.zfs-import-rpool.enable = false;

        # Import the ZFS pool without mounting
        systemd.services.import-rpool-bare = {
          after = [ "modprobe@zfs.service" ] ++ deviceUnits;
          requires = [ "modprobe@zfs.service" ];

          # Devices in 'wants' allows degraded import if one times out
          # 'cryptsetup-pre.target' ensures this finishes before cryptsetup
          wants = [ "cryptsetup-pre.target" ] ++ deviceUnits;
          before = [ "cryptsetup-pre.target" ];

          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [ config.boot.zfs.package ];
          enableStrictShellChecks = true;
          script =
            let
              # Validate encryption root to prevent mounting fraudulent filesystems
              shouldCheckFS = fs: fs.fsType == "zfs" && utils.fsNeededForBoot fs;
              checkFS = fs: ''
                encroot="$(zfs get -H -o value encryptionroot ${fs.device})"
                if [ "$encroot" != rpool/crypt ]; then
                  echo ${fs.device} has invalid encryptionroot "$encroot" >&2
                  exit 1
                else
                  echo ${fs.device} has valid encryptionroot "$encroot" >&2
                fi
              '';
            in
            ''
              function cleanup() {
                exit_code=$?
                if [ "$exit_code" != 0 ]; then
                  zpool export rpool
                fi
              }
              trap cleanup EXIT
              zpool import -N -d ${importDir} rpool

              # Check that file systems have correct encryptionroot
              ${lib.concatStringsSep "\n" (
                lib.map checkFS (lib.filter shouldCheckFS config.system.build.fileSystems)
              )}
            '';
        };

        # LUKS credstore configuration
        luks.devices.credstore = {
          device = "/dev/zvol/rpool/credstore";
          crypttabExtraOpts = lib.optionals osCfg.tpm.enable [
            "tpm2-measure-pcr=yes"
            "tpm2-device=auto"
          ];
        };

        # Mount credstore in initrd via fstab
        supportedFilesystems.ext4 = true;
        systemd.contents."/etc/fstab".text = ''
          /dev/mapper/credstore /etc/credstore ext4 defaults,x-systemd.after=systemd-cryptsetup@credstore.service 0 2
        '';

        # Ensure credstore closes before leaving initrd
        systemd.targets.initrd-switch-root = {
          conflicts = [
            "etc-credstore.mount"
            "systemd-cryptsetup@credstore.service"
          ];
          after = [
            "etc-credstore.mount"
            "systemd-cryptsetup@credstore.service"
          ];
        };

        # Load ZFS encryption key from credstore
        systemd.services.rpool-load-key = {
          requiredBy = [ "initrd.target" ];
          before = [
            "sysroot.mount"
            "initrd.target"
          ];
          requires = [ "import-rpool-bare.service" ];
          after = [ "import-rpool-bare.service" ];
          unitConfig.RequiresMountsFor = "/etc/credstore";
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            ImportCredential = "zfs-sysroot.mount";
            RemainAfterExit = true;
            ExecStart = "${config.boot.zfs.package}/bin/zfs load-key -L file://\"\${CREDENTIALS_DIRECTORY}\"/zfs-sysroot.mount rpool/crypt";
          };
        };

        # Fix udev/cryptsetup race condition during initrd transition
        systemd.services.systemd-udevd.before = [ "systemd-cryptsetup@credstore.service" ];
      };

      # Disko configuration
      disko.devices = {
        disk =
          let
            # For single disk, ESP and swap on same disk
            # For multi-disk, ESP only on first disk, swap on last (or separate)
            mkDisk = idx: device: {
              name = "disk${toString idx}";
              value = {
                type = "disk";
                inherit device;
                content = {
                  type = "gpt";
                  partitions = {
                    # ESP only on first disk
                    esp = mkIf (idx == 0) {
                      name = "ESP";
                      size = cfg.esp.size;
                      type = "EF00";
                      content = {
                        type = "filesystem";
                        format = "vfat";
                        mountpoint = "/boot";
                      };
                    };
                    # ZFS partition - leave room for swap on last disk
                    zfs = {
                      end = if idx == (length cfg.devices - 1) && enableSwap then "-${cfg.swap.size}" else "-0";
                      content = {
                        type = "zfs";
                        pool = "rpool";
                      };
                    };
                    # Swap only on last disk (if enabled)
                    encryptedSwap = mkIf (idx == (length cfg.devices - 1) && enableSwap) {
                      size = "100%";
                      content = {
                        type = "swap";
                        randomEncryption = true;
                      };
                    };
                  };
                };
              };
            };
          in
          builtins.listToAttrs (imap0 mkDisk cfg.devices);

        zpool.rpool = {
          type = "zpool";
          mode = zfsVdevType;
          rootFsOptions = {
            mountpoint = "none";
            compression = cfg.zfs.compression;
            acltype = "posixacl";
            xattr = "sa";
            atime = cfg.zfs.atime;
            "com.sun:auto-snapshot" = "true"; # sanoid honors this for dataset-level opt-in/opt-out
          };
          options.ashift = "12";
          datasets = {
            # Credstore: LUKS-encrypted volume for ZFS key storage
            #
            # Default password "keystone" enables automated deployments.
            # TPM2 handles unlock after enrollment. Password fallback available.
            credstore = {
              type = "zfs_volume";
              size = cfg.credstore.size;
              content = {
                type = "luks";
                name = "credstore";
                passwordFile = "${./scripts/credstore-password}";
                content = {
                  type = "filesystem";
                  format = "ext4";
                };
              };
            };
            # Encrypted root dataset
            crypt = {
              type = "zfs_fs";
              options.mountpoint = "none";
              options.encryption = "aes-256-gcm";
              options.keyformat = "raw";
              options.keylocation = "file:///etc/credstore/zfs-sysroot.mount";
              preCreateHook = "mount -o X-mount.mkdir /dev/mapper/credstore /etc/credstore && head -c 32 /dev/urandom > /etc/credstore/zfs-sysroot.mount";
              postCreateHook = ''
                umount /etc/credstore && cryptsetup luksClose /dev/mapper/credstore
              '';
            };
            "crypt/system" = {
              type = "zfs_fs";
              mountpoint = "/";
            };
            "crypt/system/nix" = {
              type = "zfs_fs";
              mountpoint = "/nix";
              options = {
                "com.sun:auto-snapshot" = "false";
              };
            };
            "crypt/system/var" = {
              type = "zfs_fs";
              mountpoint = "/var";
            };
          };
        };
      };

      # Explicit mount configuration for stage 1 (initrd)
      # Required for ZFS datasets using 'mountpoint=$path' with 'zfsutil' option
      fileSystems = lib.genAttrs [ "/" "/nix" "/var" ] (fs: {
        device = "rpool/crypt/system${lib.optionalString (fs != "/") fs}";
        fsType = "zfs";
        options = [ "zfsutil" ];
      });

      # ZFS boot configuration
      boot.zfs = {
        forceImportRoot = false;
        allowHibernation = false;
        devNodes = importDir;
      };

      # Kernel parameters for ZFS
      boot.kernelParams = [
        "zfs.zfs_arc_max=${toString arcMaxBytes}"
      ];

      # Enable ZFS services
      services.zfs = {
        autoScrub = mkIf cfg.zfs.autoScrub {
          enable = true;
          interval = "weekly";
        };
        trim = {
          enable = true;
          interval = "weekly";
        };
      };

      # Ensure proper ZFS module loading
      boot.kernelModules = [ "zfs" ];
      boot.extraModulePackages = [ config.boot.kernelPackages.${pkgs.zfs.kernelModuleAttribute} ];
    })

    # ext4 configuration (simpler alternative to ZFS)
    (mkIf (osCfg.enable && cfg.enable && cfg.type == "ext4") {
      # Boot loader configuration
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      boot.initrd.systemd.enable = true;

      # Disko configuration for ext4 with LUKS
      disko.devices = {
        disk.root = {
          type = "disk";
          device = firstDevice;
          content = {
            type = "gpt";
            partitions = {
              esp = {
                name = "ESP";
                size = cfg.esp.size;
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                };
              };
              root = {
                end = if enableSwap then "-${cfg.swap.size}" else "-0";
                content = {
                  type = "luks";
                  name = "cryptroot";
                  passwordFile = "${./scripts/credstore-password}";
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/";
                  };
                };
              };
              swap = mkIf enableSwap {
                size = "100%";
                content =
                  if cfg.hibernate.enable then
                    {
                      type = "luks";
                      name = "cryptswap";
                      passwordFile = "${./scripts/credstore-password}";
                      content = {
                        type = "swap";
                      };
                    }
                  else
                    {
                      type = "swap";
                      randomEncryption = true;
                    };
              };
            };
          };
        };
      };

      boot.initrd.luks.devices.cryptroot = {
        device = "/dev/disk/by-partlabel/disk-root-root";
        crypttabExtraOpts = lib.optionals osCfg.tpm.enable [
          "tpm2-measure-pcr=yes"
          "tpm2-device=auto"
        ];
      };

      # Hibernation support: persistent LUKS swap + resumeDevice
      boot.initrd.luks.devices.cryptswap = mkIf (enableSwap && cfg.hibernate.enable) {
        device = "/dev/disk/by-partlabel/disk-root-swap";
        crypttabExtraOpts = lib.optionals osCfg.tpm.enable [
          "tpm2-measure-pcr=yes"
          "tpm2-device=auto"
        ];
      };

      boot.resumeDevice = mkIf cfg.hibernate.enable "/dev/mapper/cryptswap";

      boot.initrd.availableKernelModules = mkIf cfg.hibernate.enable (lib.mkAfter [ "resume" ]);
    })
  ];
}
