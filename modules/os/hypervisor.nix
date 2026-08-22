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
  };

  config = mkMerge [
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
