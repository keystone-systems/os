{
  pkgs,
  lib,
  self,
}:
let
  eval =
    modules:
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
              enable = true;
              type = "zfs";
              devices = [ "/dev/vda" ];
              zfs.datasets = {
                "rpool/crypt/home/test" = {
                  class = "state";
                  mountpoint = "/home/test";
                  properties.refquota = "10G";
                };
                "rpool/crypt/kube-pv/external" = {
                  class = "critical-state";
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
  valid = eval [ ];
  script = valid.config.systemd.services.keystone-zfs-datasets.script;
  invalid = eval [
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
    echo "managed dataset is absent from reconciler" >&2
    exit 1
  ''}
  ${lib.optionalString (lib.hasInfix "rpool/crypt/kube-pv/external" script) ''
    echo "observed dataset leaked into reconciler" >&2
    exit 1
  ''}
  ${lib.optionalString (!lib.hasInfix "refusing to create" script) ''
    echo "non-empty mountpoint guard is absent" >&2
    exit 1
  ''}
  ${lib.optionalString (invalidAssertions == [ ]) ''
    echo "invalid registry entry did not fail an assertion" >&2
    exit 1
  ''}
  touch "$out"
''
