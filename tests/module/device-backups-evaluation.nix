{
  pkgs,
  lib,
  self,
}:
let
  eval =
    extra:
    (import "${pkgs.path}/nixos/lib/eval-config.nix") {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.operating-system
        {
          system.stateVersion = "25.05";
          networking.hostName = "backup-host";
          boot.loader.systemd-boot.enable = true;
          keystone.os = {
            enable = true;
            storage = {
              enable = false;
              type = "zfs";
              zfs.pools.ocean = {
                role = "fleet-data";
                importService = "import-ocean.service";
              };
              deviceBackups.macbook = {
                pool = "ocean";
                kind = "time-machine";
                quota = "2T";
                auth.passwordFile = "/run/secrets/timemachine";
              };
              deviceBackups.phone = {
                pool = "ocean";
                kind = "files";
                quota = "100G";
                allowedNetworks = [ "192.168.1.0/24" ];
                auth.passwordFile = "/run/secrets/timemachine";
              };
            };
            users.test = {
              fullName = "Test User";
              initialPassword = "test";
              admin = true;
            };
          };
        }
        extra
      ];
    };
  configured = eval { };
  invalid = eval {
    keystone.os.storage.deviceBackups.macbook.pool = lib.mkForce "missing";
  };
  invalidAssertions = builtins.filter (assertion: !assertion.assertion) invalid.config.assertions;
  datasets = configured.config.keystone.os.storage.zfs.datasets;
  timeMachineDataset = datasets."ocean/clients/timemachine/macbook";
  filesDataset = datasets."ocean/clients/images/phone";
  share = configured.config.services.samba.settings."timemachine-macbook";
  phoneShare = configured.config.services.samba.settings."timemachine-phone";
  sambaGlobal = configured.config.services.samba.settings.global;
  sambaConfig = configured.config.environment.etc."samba/smb.conf".source;
  mountGuard = configured.config.systemd.services.keystone-device-backup-mounts;
in
pkgs.runCommand "device-backups-evaluation" { } ''
  mac_acl="$(${pkgs.samba}/bin/testparm --suppress-prompt ${sambaConfig} mac 100.64.0.40 2>&1 || true)"
  ${pkgs.gnugrep}/bin/grep -Fq "Allow connection from mac (100.64.0.40) to timemachine-macbook" <<<"$mac_acl"
  ${pkgs.gnugrep}/bin/grep -Fq "Deny connection from mac (100.64.0.40) to timemachine-phone" <<<"$mac_acl"

  lan_acl="$(${pkgs.samba}/bin/testparm --suppress-prompt ${sambaConfig} phone 192.168.1.20 2>&1 || true)"
  ${pkgs.gnugrep}/bin/grep -Fq "Deny connection from phone (192.168.1.20) to timemachine-macbook" <<<"$lan_acl"
  ${pkgs.gnugrep}/bin/grep -Fq "Allow connection from phone (192.168.1.20) to timemachine-phone" <<<"$lan_acl"

  outside_acl="$(${pkgs.samba}/bin/testparm --suppress-prompt ${sambaConfig} outside 203.0.113.10 2>&1 || true)"
  ${pkgs.gnugrep}/bin/grep -Fq "Deny connection from outside (203.0.113.10) to timemachine-macbook" <<<"$outside_acl"
  ${pkgs.gnugrep}/bin/grep -Fq "Deny connection from outside (203.0.113.10) to timemachine-phone" <<<"$outside_acl"

  mac_ipv6_acl="$(${pkgs.samba}/bin/testparm --suppress-prompt ${sambaConfig} mac-ipv6 fd7a:115c:a1e0::28 2>&1 || true)"
  ${pkgs.gnugrep}/bin/grep -Fq "Allow connection from mac-ipv6 (fd7a:115c:a1e0::28) to timemachine-macbook" <<<"$mac_ipv6_acl"
  ${pkgs.gnugrep}/bin/grep -Fq "Deny connection from mac-ipv6 (fd7a:115c:a1e0::28) to timemachine-phone" <<<"$mac_ipv6_acl"

  outside_ipv6_acl="$(${pkgs.samba}/bin/testparm --suppress-prompt ${sambaConfig} outside-ipv6 2001:db8::1 2>&1 || true)"
  ${pkgs.gnugrep}/bin/grep -Fq "Deny connection from outside-ipv6 (2001:db8::1) to timemachine-macbook" <<<"$outside_ipv6_acl"
  ${pkgs.gnugrep}/bin/grep -Fq "Deny connection from outside-ipv6 (2001:db8::1) to timemachine-phone" <<<"$outside_ipv6_acl"

  ${lib.optionalString
    (
      timeMachineDataset.role != "device-backup"
      || timeMachineDataset.properties.quota != "2T"
      || filesDataset.role != "device-backup"
      || filesDataset.properties.quota != "100G"
    )
    ''
      echo "device backup dataset contracts are incomplete" >&2
      exit 1
    ''
  }
  ${lib.optionalString
    (
      datasets."ocean/clients/timemachine".properties != {
        canmount = "off";
        mountpoint = "none";
      }
      ||
        datasets."ocean/clients/images".properties != {
          canmount = "off";
          mountpoint = "none";
        }
    )
    ''
      echo "device backup structural namespaces are incomplete" >&2
      exit 1
    ''
  }
  ${lib.optionalString
    (
      builtins.any (name: lib.hasPrefix "ocean/device-backups/" name) (builtins.attrNames datasets)
      || datasets ? "ocean/device-backups"
    )
    ''
      echo "legacy device backup datasets are still generated" >&2
      exit 1
    ''
  }
  ${lib.optionalString (share.path != "/ocean/clients/timemachine/macbook") ''
    echo "Time Machine share does not target its canonical client dataset" >&2
    exit 1
  ''}
  ${lib.optionalString (phoneShare.path != "/ocean/clients/images/phone") ''
    echo "files share does not target its canonical client dataset" >&2
    exit 1
  ''}
  ${lib.optionalString ((share."fruit:time machine" or "") != "yes") ''
    echo "Time Machine Samba behavior is absent" >&2
    exit 1
  ''}
  ${lib.optionalString
    (
      share."hosts allow" != "100.64.0.0/10 fd7a:115c:a1e0::/48"
      || phoneShare."hosts allow" != "192.168.1.0/24"
      || sambaGlobal."hosts allow" != "100.64.0.0/10 fd7a:115c:a1e0::/48 192.168.1.0/24"
      || sambaGlobal."hosts deny" != "ALL"
    )
    ''
      echo "device backup network ACLs do not combine global admission with per-share isolation" >&2
      exit 1
    ''
  }
  ${lib.optionalString (!lib.hasInfix "findmnt -n -o SOURCE" mountGuard.script) ''
    echo "exact mount source guard is absent" >&2
    exit 1
  ''}
  ${lib.optionalString (!lib.hasInfix "findmnt -n -o TARGET" mountGuard.script) ''
    echo "exact mount target guard is absent" >&2
    exit 1
  ''}
  ${lib.optionalString
    (
      !lib.elem "keystone-device-backup-mounts.service" configured.config.systemd.services.samba-smbd.requires
    )
    ''
      echo "Samba does not require the exact mount guard" >&2
      exit 1
    ''
  }
  ${lib.optionalString (invalidAssertions == [ ]) ''
    echo "unknown device backup pool did not fail evaluation" >&2
    exit 1
  ''}
  touch "$out"
''
