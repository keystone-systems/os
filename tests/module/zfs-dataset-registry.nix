{
  pkgs,
  lib,
  self,
}:
let
  eval =
    storageEnable: modules:
    (import "${pkgs.path}/nixos/lib/eval-config.nix") {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.operating-system
        {
          system.stateVersion = "25.05";
          boot.loader.systemd-boot.enable = true;
          keystone.os = {
            enable = true;
            storage = {
              enable = storageEnable;
              type = "zfs";
              devices = lib.optionals storageEnable [ "/dev/vda" ];
              zfs.datasets = {
                "rpool/crypt/home/test" = {
                  class = "state";
                  mountpoint = "/home/test";
                  preserveExisting = true;
                  properties.refquota = "10G";
                };
                # Left at the preserveExisting default so the reconciler has to
                # refuse a non-empty mountpoint rather than migrate it.
                "rpool/crypt/srv/test" = {
                  class = "state";
                  mountpoint = "/srv/test";
                };
                "rpool/crypt/cache/test" = {
                  class = "cache";
                  managed = false;
                };
              };
            };
            users.test = {
              fullName = "Test User";
              initialPassword = "test";
              admin = true;
            };
          };
        }
      ]
      ++ modules;
    };
  runtimeOnly = eval false [ ];
  partitioned = eval true [ ];
  script = runtimeOnly.config.systemd.services.keystone-zfs-datasets.script;
  service = runtimeOnly.config.systemd.services.keystone-zfs-datasets;
  invalid = eval false [
    {
      keystone.os.storage.zfs.datasets."other/data" = {
        class = "state";
        properties.mountpoint = "/srv/data";
        mountpoint = "/srv/data";
      };
    }
  ];
  invalidAssertions = builtins.filter (assertion: !assertion.assertion) invalid.config.assertions;
in
pkgs.runCommand "zfs-dataset-registry-evaluation" { } ''
  ${lib.optionalString (!lib.hasInfix "rpool/crypt/home/test" script) ''
    echo "explicit dataset is absent when partition management is disabled" >&2
    exit 1
  ''}
  ${lib.optionalString (lib.hasInfix "rpool/crypt/cache/test" script) ''
    echo "observed dataset leaked into reconciler" >&2
    exit 1
  ''}
  ${lib.optionalString (!lib.hasInfix "declared parent dataset" script) ''
    echo "strict parent check is absent" >&2
    exit 1
  ''}
  ${lib.optionalString (!lib.hasInfix "refusing ambiguous migration" script) ''
    echo "ambiguous migration guard is absent" >&2
    exit 1
  ''}
  # Both branches must be generated: /srv/test defaults to preserveExisting =
  # false and must refuse, /home/test opts in and must stage instead.
  ${lib.optionalString (!lib.hasInfix "set preserveExisting = true to migrate it" script) ''
    echo "non-empty mountpoint guard is absent for a non-preserving dataset" >&2
    exit 1
  ''}
  ${lib.optionalString (!lib.hasInfix ''mv "$mountpoint" "$staging"'' script) ''
    echo "preserving dataset does not stage existing contents" >&2
    exit 1
  ''}
  ${lib.optionalString (!lib.hasInfix "used_bytes + available_bytes" script) ''
    echo "migration capacity check is absent" >&2
    exit 1
  ''}
  ${lib.optionalString (!lib.hasInfix "rsync -aHAX --numeric-ids" script) ''
    echo "metadata-preserving migration copy is absent" >&2
    exit 1
  ''}
  ${lib.optionalString (!lib.hasInfix "rsync -aHAXnc --numeric-ids --itemize-changes" script) ''
    echo "checksum verification without deletion is absent" >&2
    exit 1
  ''}
  ${lib.optionalString (lib.hasInfix "--delete" script) ''
    echo "migration verification may delete destination data" >&2
    exit 1
  ''}
  ${lib.optionalString (!lib.hasInfix ".keystone-migration.verified" script) ''
    echo "verified migration cleanup marker is absent" >&2
    exit 1
  ''}
  ${lib.optionalString
    (!lib.elem "zfs-mount.service" service.after || !lib.elem "zfs-mount.service" service.requires)
    ''
      echo "reconciler lacks zfs-mount ordering" >&2
      exit 1
    ''
  }
  ${lib.optionalString (service.unitConfig.DefaultDependencies != false) ''
    echo "reconciler retains default dependencies" >&2
    exit 1
  ''}
  ${lib.optionalString
    (
      lib.attrByPath [
        "zpool"
        "rpool"
        "datasets"
        "crypt/home/test"
      ] null runtimeOnly.config.disko.devices != null
    )
    ''
      echo "Disko output leaked into runtime-only reconciliation" >&2
      exit 1
    ''
  }
  ${lib.optionalString (!partitioned.config.disko.devices.zpool.rpool.datasets ? "crypt/home/test") ''
    echo "partition-managed registry dataset is absent from Disko" >&2
    exit 1
  ''}
  ${lib.optionalString
    (
      !lib.elem "nofail"
        partitioned.config.disko.devices.zpool.rpool.datasets."crypt/home/test".mountOptions
    )
    ''
      echo "generated Disko mount is missing nofail" >&2
      exit 1
    ''
  }
  ${lib.optionalString (invalidAssertions == [ ]) ''
    echo "invalid registry entry did not fail an assertion" >&2
    exit 1
  ''}
  touch "$out"
''
