# Keystone OS Hypervisor Module
#
# Libvirt/KVM hypervisor with OVMF, TPM emulation, and SPICE support.
# Grants `libvirtd` group membership to the admin user only (via the
# _autoUserGroups.adminOnly sink); non-admin users with a polkit path
# retain prompt-based access. See conventions/process.user-groups.md.
# When keystone.desktop is also enabled, the client adds the virt-manager GUI.
#
# Home-manager integration (when imported):
# - Sets uri_default in ~/.config/libvirt/libvirt.conf
# - Configures virt-manager dconf connection bookmarks
#
{
  config,
  lib,
  pkgs,
  options,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  cfg = osCfg.hypervisor;
  clientCfg = cfg.client;
  hasDesktop = options ? keystone && config.keystone.desktop.enable or false;

  ovmfPkg = pkgs.OVMF.override {
    secureBoot = true;
    tpmSupport = true;
    msVarsTemplate = true;
  };
  qemuPkg = pkgs.qemu_kvm;

  # All connection URIs: default + additional bookmarks. A client-only host
  # may retain a local URI as a manual bookmark, but it must not try to connect
  # to a server that this module did not enable.
  allUris = [ cfg.defaultUri ] ++ cfg.connections;
  isLocalUri = uri: hasPrefix "qemu:///" uri;
  autoconnectUris = if cfg.enable then allUris else filter (uri: !isLocalUri uri) allUris;

  # Desktop users who should get virt-manager home-manager config
  desktopUsers = filterAttrs (_: u: u.desktop.enable) osCfg.users;
  zvolCfg = cfg.zvolStorage;
  zvolUsers = builtins.attrNames osCfg.users;
  userDataset = user: "${zvolCfg.dataset}/users/${user}";
  zvolDatasetProperties = {
    canmount = "off";
    "com.sun:auto-snapshot" = "false";
  };
  zvolDatasets =
    lib.genAttrs
      (
        [
          zvolCfg.dataset
          "${zvolCfg.dataset}/users"
        ]
        ++ map userDataset zvolUsers
      )
      (name: {
        class = "ephemeral";
        mountpoint = "none";
        properties =
          zvolDatasetProperties // lib.optionalAttrs (name == zvolCfg.dataset) { quota = zvolCfg.quota; };
      });
  delegatedPermissions = [
    "create"
    "mount"
    "destroy"
    "snapshot"
    "rollback"
    "volsize"
    "volblocksize"
    "compression"
    "snapdev"
    "volmode"
    "userprop"
  ];
  zfs = "${config.boot.zfs.package}/bin/zfs";
  zvolPackages = [
    config.boot.zfs.package
    pkgs.libvirt
    qemuPkg
    pkgs.swtpm
  ];
  backendConfig =
    if zvolCfg.enable then
      {
        backend = "zvol";
        dataset = zvolCfg.dataset;
        quota = zvolCfg.quota;
        volblocksize = zvolCfg.volblocksize;
      }
    else
      { backend = "qcow2"; };
in
{
  options.keystone.os.hypervisor = {
    enable = mkEnableOption "Libvirt/KVM hypervisor with OVMF, TPM, and SPICE support";

    client.enable = mkOption {
      type = types.bool;
      default = cfg.enable;
      defaultText = literalExpression "config.keystone.os.hypervisor.enable";
      description = "Enable the Virt Manager client and its connection settings";
    };

    defaultUri = mkOption {
      type = types.str;
      default = "qemu:///session";
      description = "Default libvirt connection URI for virt-manager";
    };

    connections = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "qemu+ssh://user@server/session" ];
      description = "Additional virt-manager connection URIs (shown as bookmarks)";
    };

    allowedBridges = mkOption {
      type = types.listOf types.str;
      default = [ "virbr0" ];
      example = [
        "virbr0"
        "br0"
      ];
      description = "Bridge devices usable by session VMs via qemu-bridge-helper. Written to /etc/qemu/bridge.conf.";
    };

    zvolStorage = {
      enable = mkOption {
        type = types.bool;
        default =
          osCfg.storage.type == "zfs"
          && hasDesktop
          && clientCfg.enable
          && cfg.defaultUri == "qemu:///session";
        defaultText = literalExpression ''storage.type == "zfs" && desktop.enable && client.enable && defaultUri == "qemu:///session"'';
        description = "Use per-user sparse ZFS volumes for local session VMs";
      };
      dataset = mkOption {
        type = types.str;
        default = "rpool/crypt/vms";
        description = "Encrypted parent dataset for per-user VM datasets";
      };
      quota = mkOption {
        type = types.str;
        default = "500G";
        description = "Quota applied to the VM storage parent dataset";
      };
      volblocksize = mkOption {
        type = types.str;
        default = "16K";
        description = "ZFS volume block size used for newly created VM disks";
      };
    };
  };

  config = mkMerge [
    (mkIf (osCfg.enable && zvolCfg.enable) {
      assertions = [
        {
          assertion = osCfg.storage.type == "zfs";
          message = "keystone.os.hypervisor.zvolStorage requires ZFS storage.";
        }
        {
          assertion = lib.hasPrefix "rpool/crypt/" zvolCfg.dataset;
          message = "keystone.os.hypervisor.zvolStorage.dataset MUST be a native-encrypted child of rpool/crypt.";
        }
        {
          assertion = cfg.defaultUri == "qemu:///session";
          message = "keystone.os.hypervisor.zvolStorage requires the local qemu:///session URI.";
        }
        {
          assertion = clientCfg.enable;
          message = "keystone.os.hypervisor.zvolStorage requires the local hypervisor client.";
        }
      ];

      keystone.os.storage.zfs.datasets = zvolDatasets;

      systemd.services.keystone-zvol-delegation = {
        description = "Reconcile rootless VM zvol delegation";
        wantedBy = [ "multi-user.target" ];
        after = [ "keystone-zfs-datasets.service" ];
        requires = [ "keystone-zfs-datasets.service" ];
        serviceConfig.Type = "oneshot";
        script = concatMapStringsSep "\n" (user: ''
          ${zfs} unallow -u ${escapeShellArg user} ${escapeShellArg (userDataset user)} 2>/dev/null || true
          ${zfs} allow -u ${escapeShellArg user} ${escapeShellArg (concatStringsSep "," delegatedPermissions)} ${escapeShellArg (userDataset user)}
        '') zvolUsers;
      };

      services.udev.extraRules = concatMapStringsSep "\n" (user: ''
        KERNEL=="zd*", SUBSYSTEM=="block", ACTION=="add|change", PROGRAM=="${config.boot.zfs.package}/lib/udev/zvol_id $devnode", RESULT=="${zvolCfg.dataset}/users/${user}/*", OWNER="${user}", MODE="0600"
      '') zvolUsers;

      # qemu:///session starts per-user virtqemud/QEMU processes; it does not
      # require the root libvirtd service, but the client and emulator must be
      # present in the system profile.
      environment.systemPackages = zvolPackages;
    })

    (mkIf osCfg.enable {
      environment.etc."keystone/virtual-machine-backend.json".text = builtins.toJSON backendConfig;
    })
    (mkIf (osCfg.enable && cfg.enable) {
      virtualisation.libvirtd = {
        enable = true;
        allowedBridges = cfg.allowedBridges;
        qemu = {
          package = mkDefault qemuPkg;
          runAsRoot = true;
          swtpm.enable = true;
        };
      };

      # Add passt for user-mode networking
      systemd.services.libvirtd.path = [
        qemuPkg
        pkgs.netcat
        pkgs.passt
      ];

      # Polkit: allow libvirtd group members to manage VMs.
      # This rule also covers non-admin wheel users via the polkit auth
      # flow (they get an interactive prompt, not silent access); only
      # the admin receives libvirtd membership below for a frictionless
      # virt-manager session.
      security.polkit.enable = true;
      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.libvirt.unix.manage" &&
              subject.isInGroup("libvirtd")) {
            return polkit.Result.YES;
          }
        });
      '';

      # Grant the admin user membership in the `libvirtd` group. Previously
      # keystone added every keystone.os.users entry to libvirtd; we now
      # narrow to admin-only, because hardware/service access follows
      # `admin = true`, not sudo. Non-admin users that need libvirtd
      # silent access should opt in via their own `extraGroups`. See
      # conventions/process.user-groups.md.
      #
      # The libvirtd group itself is created by the upstream libvirtd
      # module (nixos/modules/virtualisation/libvirtd.nix assigns a fixed
      # gid), so no explicit users.groups.libvirtd declaration is needed.
      keystone.os._autoUserGroups.adminOnly = [ "libvirtd" ];

      # OVMF firmware symlinks
      systemd.tmpfiles.rules = [
        "d /var/lib/libvirt/qemu/nvram 0755 root root -"
        "d /var/lib/libvirt/images 0755 root root -"
        "d /run/libvirt/nix-ovmf 0755 root root -"
        "L+ /run/libvirt/nix-ovmf/OVMF_CODE.fd - - - - ${ovmfPkg.fd}/FV/OVMF_CODE.fd"
        "L+ /run/libvirt/nix-ovmf/OVMF_VARS.fd - - - - ${ovmfPkg.fd}/FV/OVMF_VARS.fd"
        "L+ /run/libvirt/nix-ovmf/OVMF_CODE.ms.fd - - - - ${ovmfPkg.fd}/FV/OVMF_CODE.fd"
        "L+ /run/libvirt/nix-ovmf/OVMF_VARS.ms.fd - - - - ${ovmfPkg.fd}/FV/OVMF_VARS.ms.fd"
        "L+ /run/libvirt/nix-ovmf/AAVMF_CODE.fd - - - - ${ovmfPkg.fd}/FV/AAVMF_CODE.fd"
        "L+ /run/libvirt/nix-ovmf/AAVMF_VARS.fd - - - - ${ovmfPkg.fd}/FV/AAVMF_VARS.fd"
        "L+ /run/libvirt/nix-ovmf/edk2-x86_64-code.fd - - - - ${qemuPkg}/share/qemu/edk2-x86_64-code.fd"
        "L+ /run/libvirt/nix-ovmf/edk2-x86_64-secure-code.fd - - - - ${qemuPkg}/share/qemu/edk2-x86_64-secure-code.fd"
      ];

      # Only virtual interfaces are server-owned. A bridge MEMBER NIC
      # (e.g. br0 enslaving an onboard ethernet) must be added by the host's
      # own config — a wildcard like enp* here strands every ethernet
      # adapter on the host, including hotplugged USB ones a laptop needs
      # for wired restore/install paths.
      networking.networkmanager.unmanaged = mkIf hasDesktop [
        "interface-name:virbr*"
        "interface-name:vnet*"
        "interface-name:br0"
      ];

      # Server-only: extra packages for headless management
      environment.systemPackages = mkIf (!hasDesktop) (
        with pkgs;
        [
          virt-viewer
          libguestfs
        ]
      );
    })

    # Desktop client. This does not enable libvirtd or install server packages.
    (mkIf (osCfg.enable && clientCfg.enable && hasDesktop) {
      programs.virt-manager.enable = true;
    })

    # Home-manager: virt-manager defaults for desktop users
    # Separate mkMerge entry — see users.nix for why optionalAttrs must not
    # be merged with // into a mkIf block.
    (optionalAttrs (options ? home-manager) {
      home-manager.users = mkIf (osCfg.enable && clientCfg.enable && hasDesktop && desktopUsers != { }) (
        mapAttrs (
          username: _:
          { ... }:
          {
            # Default libvirt connection URI
            xdg.configFile."libvirt/libvirt.conf".text = ''
              uri_default = "${cfg.defaultUri}"
            '';

            # virt-manager connection bookmarks via dconf
            dconf.settings."org/virt-manager/virt-manager/connections" = {
              uris = allUris;
              autoconnect = autoconnectUris;
            };
          }
        ) desktopUsers
      );
    })
  ];
}
