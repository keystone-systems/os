# ISO installer configuration
#
# Provides ISO-specific config layered on top of keystone.os (which handles
# SSH, firewall, flakes, locale) and keystone.terminal (helix, zsh, starship).
#
# The ISO is a reachable live environment, not an interactive installer. Boot
# it, then run `ks-fleet install <host>` from an operator machine: disko and
# nixos-anywhere do the partitioning and the install over SSH. The ISO
# therefore ships the recovery tooling and an sshd with root keys, and starts
# a plain login shell on tty1.
#
# This module adds:
# - Root SSH login override (keystone.os defaults to prohibit-password)
# - ZFS, Secure Boot, TPM, and disko tooling pre-installed
#
# Usage:
#   keystone.installer.sshKeys = [ "ssh-ed25519 AAAAC3..." ];
{
  config,
  pkgs,
  lib,
  ...
}:
let
  installerCfg = config.keystone.installer;
in
{
  options.keystone.installer = {
    edition = lib.mkOption {
      type = lib.types.str;
      default = "server";
      description = "ISO edition name used in the filename (e.g. server, desktop).";
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0";
      description = "Keystone installer version embedded in the ISO filename.";
    };

    sshKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH public keys for root access on the installer ISO";
    };

    bootstrapPassword = lib.mkOption {
      type = lib.types.str;
      default = "changeme";
      description = ''
        Public temporary root password for the release-candidate installer.
        Use the ISO only on a trusted local network.
      '';
    };
  };

  config = {
    # The live installer builds the target system before first boot, so it needs
    # the shared Keystone cache itself; the normal keystone.os cache defaults are
    # not imported into this minimal ISO module stack.
    # The live environment realizes flake-based closures (nixos-anywhere
    # builds against the consumer flake), so it needs flakes itself. This
    # minimal ISO stack does not import keystone.os, which is where the rest
    # of the fleet gets these.
    nix.settings.experimental-features = lib.mkDefault [
      "nix-command"
      "flakes"
    ];

    nix.settings.substituters = lib.mkBefore [ "https://ks-systems.cachix.org" ];
    nix.settings.trusted-public-keys = lib.mkBefore [
      "ks-systems.cachix.org-1:Abbd38auzcLIfJUtX7kSD6zdGUU4v831Sb2KfajR5Mo="
    ];

    # The live installer can still hit legitimate cache misses while realizing
    # the target host closure. The default minimal ISO has no swap, which makes
    # moderate-memory VM installs fragile. Enable zram-backed swap on the live
    # environment so `nixos-install` has some headroom when the cache is cold.
    zramSwap.enable = true;

    # Enable SSH daemon for remote access
    # The public RC uses one obvious, temporary credential so a controller
    # machine without pre-provisioned keys can reach the live environment.
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = lib.mkForce "yes";
        PasswordAuthentication = true;
        PubkeyAuthentication = true;
        KbdInteractiveAuthentication = false;
      };
      extraConfig = ''
        UseDNS no
      '';
    };

    # Configure root user with SSH keys
    users.users.root = {
      initialPassword = installerCfg.bootstrapPassword;
      openssh.authorizedKeys.keys = installerCfg.sshKeys;
    };

    services.getty.helpLine = ''
      Keystone OS installer (INSECURE BOOTSTRAP)
      SSH: root@\\4  password: ${installerCfg.bootstrapPassword}
      If no address appears, log in and run: ip -br address
      Use only on a trusted local network.
    '';

    # Disable wpa_supplicant — NetworkManager handles wireless
    networking = {
      wireless.enable = lib.mkForce false;
    };

    # Tools for installation. The ISO is a reachable live environment, not an
    # interactive installer: `ks-fleet install` drives nixos-anywhere against
    # the sshd configured above.
    environment.systemPackages = (
      with pkgs;
      [
        git
        curl
        wget
        htop
        lsof
        rsync
        jq
        # Tools needed for installation and recovery
        parted
        cryptsetup
        util-linux
        dosfstools
        e2fsprogs
        nix
        nixos-install-tools
        disko
        shadow
        iproute2
        networkmanager
        tpm2-tools
        # ZFS utilities — use the same package boot.supportedFilesystems selects
        config.boot.zfs.package
        # Secure Boot key management
        sbctl
      ]
    );

    # installation-cd-minimal enables NetworkManager by default, but in headless
    # VM tests that can leave interfaces unconfigured. Use classic DHCP so SSH
    # comes up reliably.
    networking.networkmanager.enable = lib.mkForce false;
    networking.useDHCP = lib.mkForce true;

    # tty1 wiring: the installer relies on the standard agetty + autologin
    # flow. The unit is materialized by the getty module, but
    # `installation-cd-base` upstream does not pull it into multi-user.target,
    # leaving it "linked but inactive" — boot reaches multi-user with no
    # process attached to tty1, so the framebuffer keeps whatever was last
    # drawn and the keyboard registers nothing. Explicitly want it.
    systemd.services."getty@tty1".wantedBy = [ "multi-user.target" ];

    # Suppress boot-status residue on the live installer console.
    # - Plain-shell ISO uses `systemd.show_status=auto`: systemd shows the
    #   normal `[ OK ] Started …` scroll DURING boot (so the user sees
    #   progress and any [FAILED] units), then stops emitting once
    #   multi-user.target is reached. Without this, late-starting services
    #   keep printing to /dev/console after the autologin shell prompt has
    #   already been drawn, leaving residue on tty1.
    # - Kernel warnings still surface, which is what the plain-shell flavor
    #   wants.
    # - Journal records everything regardless of these console flags.
    # - Serial still receives all boot logs for remote debugging.
    boot.kernelParams = [ "systemd.show_status=auto" ];

    # Ensure SSH starts on boot
    systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

    # Note: kernel is set in flake.nix to override minimal CD default

    # Enable ZFS for nixos-anywhere deployments
    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.forceImportRoot = false;

    # ZFS kernel modules — boot.supportedFilesystems handles extraModulePackages,
    # udev, and systemd integration. Only need to ensure the module is loaded.
    boot.kernelModules = [ "zfs" ];

    # Set required hostId for ZFS
    networking.hostId = lib.mkDefault "8425e349";

    # Optimize for installation - less bloat
    documentation.enable = false;
    documentation.nixos.enable = false;

    # Set the ISO name, label, and boot splash image
    image.baseName = lib.mkForce "keystone-${installerCfg.edition}-installer-${installerCfg.version}";
    isoImage.volumeID = lib.mkDefault "KEYSTONE";
    isoImage.efiSplashImage = ../assets/installer-splash.png;
    isoImage.splashImage = ../assets/installer-splash.png;
    # Disable the default NixOS GRUB theme so the keystone splash image shows
    isoImage.grubTheme = null;

    # Include the keystone modules in the ISO for reference
    environment.etc."keystone-modules".source = ../modules;
  }; # close config
}
