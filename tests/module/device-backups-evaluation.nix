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
  mountGuard = configured.config.systemd.services.keystone-device-backup-mounts;
in
pkgs.runCommand "device-backups-evaluation" { } ''
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
      || sambaGlobal ? "hosts allow"
    )
    ''
      echo "device backup network ACLs are not isolated per share" >&2
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
