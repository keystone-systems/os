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
          boot.loader.systemd-boot.enable = true;
          keystone.os = {
            enable = true;
            storage = {
              enable = false;
              type = "zfs";
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
  enabled = eval {
    keystone.os.services.ollama = {
      enable = true;
      acceleration = null;
      zfsDataset.enable = true;
    };
  };
  disabled = eval {
    keystone.os.services.ollama.enable = true;
  };
  nonZfs = eval {
    keystone.os.storage.type = lib.mkForce "lvm";
    keystone.os.services.ollama.enable = true;
  };
  # Explicitly requesting provisioning on a non-ZFS host must fail closed.
  invalidNonZfs = eval {
    keystone.os.storage.type = lib.mkForce "lvm";
    keystone.os.services.ollama = {
      enable = true;
      acceleration = null;
      zfsDataset.enable = true;
    };
  };
  invalidNonZfsFailures = map (assertion: assertion.message) (
    lib.filter (assertion: !assertion.assertion) invalidNonZfs.config.assertions
  );
  name = "rpool/crypt/system/var/lib/ollama";
  dataset = enabled.config.keystone.os.storage.zfs.datasets.${name};
  ollama = enabled.config.systemd.services.ollama;
in
pkgs.runCommand "ollama-zfs-dataset-evaluation" { } ''
  ${lib.optionalString (dataset.class != "cache") ''
    echo "Ollama dataset is not classified as cache" >&2
    exit 1
  ''}
  ${lib.optionalString (!dataset.preserveExisting) ''
    echo "Ollama dataset does not preserve existing models" >&2
    exit 1
  ''}
  ${lib.optionalString (dataset.mountpoint != "/var/lib/private/ollama") ''
    echo "unexpected Ollama dataset mountpoint" >&2
    exit 1
  ''}
  ${lib.optionalString
    (dataset.properties.recordsize != "1M" || dataset.properties.refquota != "200G")
    ''
      echo "unexpected Ollama dataset properties" >&2
      exit 1
    ''
  }
  ${lib.optionalString (dataset.properties."com.sun:auto-snapshot" != "false") ''
    echo "Ollama dataset is not excluded from automatic snapshots" >&2
    exit 1
  ''}
  ${lib.optionalString (!lib.elem "keystone-zfs-datasets.service" ollama.after) ''
    echo "Ollama does not start after dataset reconciliation" >&2
    exit 1
  ''}
  ${lib.optionalString (!lib.elem "keystone-zfs-datasets.service" ollama.requires) ''
    echo "Ollama does not require dataset reconciliation" >&2
    exit 1
  ''}
  ${lib.optionalString (disabled.config.keystone.os.storage.zfs.datasets != { }) ''
    echo "disabled Ollama ZFS option emitted a dataset" >&2
    exit 1
  ''}
  ${lib.optionalString (disabled.config.systemd.services ? keystone-zfs-datasets) ''
    echo "disabled Ollama ZFS option emitted a reconciler" >&2
    exit 1
  ''}
  ${lib.optionalString
    (!lib.any (message: lib.hasInfix ''storage.type = "zfs"'' message) invalidNonZfsFailures)
    ''
      echo "non-ZFS Ollama dataset provisioning did not fail an assertion" >&2
      exit 1
    ''
  }
  ${lib.optionalString (nonZfs.config.keystone.os.storage.zfs.datasets != { }) ''
    echo "non-ZFS Ollama emitted a dataset" >&2
    exit 1
  ''}
  ${lib.optionalString (nonZfs.config.systemd.services ? keystone-zfs-datasets) ''
    echo "non-ZFS Ollama emitted a reconciler" >&2
    exit 1
  ''}
  touch "$out"
''
