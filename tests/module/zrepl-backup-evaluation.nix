{
  pkgs,
  lib,
  self,
}:
let
  hosts = {
    source = {
      hostname = "source";
      role = "client";
      tailscaleIP = "100.64.0.10";
      zfs.backups.rpool = {
        targets = [ "target:lake" ];
        targetPolicies."target:lake" = {
          port = 29801;
          receiveBandwidthLimit = "10 MiB";
        };
      };
    };
    target = {
      hostname = "target";
      role = "server";
      tailscaleIP = "100.64.0.11";
    };
  };
  evalWithHosts =
    hostRegistry: hostname: extra:
    (import "${pkgs.path}/nixos/lib/eval-config.nix") {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.operating-system
        {
          system.stateVersion = "25.05";
          networking.hostName = hostname;
          boot.loader.systemd-boot.enable = true;
          keystone = {
            hosts = hostRegistry;
            os = {
              enable = true;
              storage = {
                enable = true;
                type = "zfs";
                devices = [ "/dev/vda" ];
              };
              users.test = {
                fullName = "Test User";
                initialPassword = "test";
                admin = true;
              };
            };
          };
        }
        extra
      ];
    };
  eval = evalWithHosts hosts;
  source = eval "source" {
    keystone.os.storage.zfs.datasets = {
      "rpool/crypt/home/test" = {
        class = "state";
        managed = false;
      };
      "rpool/crypt/cache" = {
        class = "cache";
        managed = false;
      };
      "rpool/credstore" = {
        class = "key-escrow";
        managed = false;
      };
    };
  };
  target = eval "target" { };
  format = pkgs.formats.yaml { };
  sourceConfig = format.generate "source-zrepl.yml" source.config.services.zrepl.settings;
  targetConfig = format.generate "target-zrepl.yml" target.config.services.zrepl.settings;
  sourceJobs = source.config.services.zrepl.settings.jobs;
  targetJobs = target.config.services.zrepl.settings.jobs;
  dataSource = lib.findFirst (job: job.name == "source-target-lake-rpool-data") null sourceJobs;
  escrowSource = lib.findFirst (job: job.name == "source-target-lake-rpool-escrow") null sourceJobs;
  dataPull = lib.findFirst (job: job.name == "pull-source-rpool-data") null targetJobs;
  escrowPull = lib.findFirst (job: job.name == "pull-source-rpool-escrow") null targetJobs;
  receiverRootUnit = target.config.systemd.services.zrepl-receiver-roots;
  receiverRootScript = receiverRootUnit.serviceConfig.ExecStart;
  prometheusTarget = eval "target" { services.prometheus.enable = true; };
  alertRules = builtins.concatStringsSep "\n" prometheusTarget.config.services.prometheus.rules;
  failingMessages =
    result:
    map (assertion: assertion.message) (
      builtins.filter (assertion: !assertion.assertion) result.config.assertions
    );
  hasFailure =
    text: result: builtins.any (message: lib.hasInfix text message) (failingMessages result);
  unknownTarget = evalWithHosts (
    hosts
    // {
      source = hosts.source // {
        zfs.backups.rpool = {
          targets = [ "missing:lake" ];
          targetPolicies."missing:lake".port = 29801;
        };
      };
    }
  ) "source" { };
  missingTailnet = evalWithHosts (
    hosts
    // {
      target = hosts.target // {
        tailscaleIP = null;
      };
    }
  ) "source" { };
  collidingPorts = evalWithHosts (
    hosts
    // {
      source = hosts.source // {
        zfs.backups.rpool = {
          targets = [
            "target:lake"
            "target2:lake"
          ];
          targetPolicies = {
            "target:lake".port = 29801;
            "target2:lake".port = 29802;
          };
        };
      };
      target2 = hosts.target // {
        hostname = "target2";
        tailscaleIP = "100.64.0.12";
      };
    }
  ) "source" { };
  invalidBandwidth = evalWithHosts (
    hosts
    // {
      source = hosts.source // {
        zfs.backups.rpool = {
          targets = [ "target:lake" ];
          targetPolicies."target:lake" = {
            port = 29801;
            receiveBandwidthLimit = "fast";
          };
        };
      };
    }
  ) "source" { };
  invalidSchedule = evalWithHosts (
    hosts
    // {
      source = hosts.source // {
        zfs.backups.rpool = {
          targets = [ "target:lake" ];
          targetPolicies."target:lake" = {
            port = 29801;
            schedule = "hourly";
          };
        };
      };
    }
  ) "source" { };
  mixedEscrow = eval "source" {
    keystone.os.storage.zfs.datasets."rpool/credstore" = {
      class = "state";
      managed = false;
    };
  };
in
pkgs.runCommand "zrepl-backup-evaluation" { nativeBuildInputs = [ pkgs.zrepl ]; } ''
  zrepl --config ${sourceConfig} configcheck
  zrepl --config ${targetConfig} configcheck
  ${lib.optionalString (dataSource == null || dataSource.filesystems ? "rpool/crypt/cache") ''
    echo "data source did not preserve registry exclusions" >&2
    exit 1
  ''}
  ${lib.optionalString (dataSource == null || !(dataSource.send.encrypted or false)) ''
    echo "data source is not encrypted-send only" >&2
    exit 1
  ''}
  ${lib.optionalString
    (
      escrowSource == null || !(escrowSource.send.raw or false) || (escrowSource.send.encrypted or false)
    )
    ''
      echo "escrow source is not strict raw, non-encrypted mode" >&2
      exit 1
    ''
  }
  ${lib.optionalString (dataPull == null || (dataPull.recv.bandwidth_limit.max or null) != "10 MiB")
    ''
      echo "receiver bandwidth limit is absent" >&2
      exit 1
    ''
  }
  ${lib.optionalString
    (
      dataPull == null
      || dataPull.root_fs != "lake/backups/zfs/source"
      || escrowPull == null
      || escrowPull.root_fs != "lake/backups/escrow/source"
    )
    ''
      echo "receiver roots duplicate or omit the source pool path" >&2
      exit 1
    ''
  }
  ${lib.optionalString
    (!(builtins.elem "zrepl-receiver-roots.service" target.config.systemd.services.zrepl.requires))
    ''
      echo "zrepl does not require receiver-root provisioning" >&2
      exit 1
    ''
  }
  for dataset in \
    lake/backups \
    lake/backups/zfs \
    lake/backups/zfs/source \
    lake/backups/escrow \
    lake/backups/escrow/source; do
    grep -F -- "$dataset" ${receiverRootScript} >/dev/null || {
      echo "zrepl receiver-root setup omits $dataset" >&2
      exit 1
    }
  done
  ${lib.optionalString (!hasFailure "known '<host>:<pool>'" unknownTarget) ''
    echo "unknown target did not fail closed" >&2
    exit 1
  ''}
  ${lib.optionalString (!hasFailure "declare tailscaleIP" missingTailnet) ''
    echo "missing tailnet identity did not fail closed" >&2
    exit 1
  ''}
  ${lib.optionalString (!hasFailure "MUST NOT collide" collidingPorts) ''
    echo "source port collision did not fail closed" >&2
    exit 1
  ''}
  ${lib.optionalString (!hasFailure "positive IEC byte rates" invalidBandwidth) ''
    echo ${lib.escapeShellArg "invalid bandwidth did not fail closed: ${builtins.toJSON (failingMessages invalidBandwidth)}"} >&2
    exit 1
  ''}
  ${lib.optionalString (!hasFailure "positive second, minute, or hour" invalidSchedule) ''
    echo "invalid schedule did not fail closed" >&2
    exit 1
  ''}
  ${lib.optionalString (!hasFailure "exactly rpool/credstore" mixedEscrow) ''
    echo "mixed data and escrow classification did not fail closed" >&2
    exit 1
  ''}
  ${lib.optionalString
    (
      !lib.hasInfix "ZreplReplicationFilesystemErrors" alertRules
      || !lib.hasInfix "ZreplMetricsAbsent" alertRules
      || !lib.hasInfix "ZfsPoolCapacityHigh" alertRules
    )
    ''
      echo "derived zrepl alert coverage is incomplete" >&2
      exit 1
    ''
  }
  touch "$out"
''
