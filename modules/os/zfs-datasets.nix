# Role-aware ZFS dataset registry and non-destructive reconciler (REQ-033).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatMapStringsSep
    concatStringsSep
    escapeShellArg
    filterAttrs
    mapAttrs'
    mapAttrsToList
    mkIf
    mkMerge
    mkOption
    nameValuePair
    optionalString
    types
    ;
  cfg = config.keystone.os.storage;
  rootNames = [
    "users"
    "shared"
    "services"
    "device-backups"
    "vms"
    "scratch"
    "replicas"
    "migrations"
    "legacy"
  ];
  generatedRoots = lib.foldlAttrs (
    result: pool: poolCfg:
    result
    // lib.listToAttrs (
      map (root: {
        name = "${pool}/${root}";
        value = {
          class = "ephemeral";
          role = "structural";
          managed = true;
          mountpoint = null;
          preserveExisting = false;
          properties = {
            canmount = "off";
            mountpoint = "none";
          };
        };
      }) (builtins.filter (root: poolCfg.roots.${root}) rootNames)
    )
  ) { } (filterAttrs (_: pool: pool.role == "fleet-data") cfg.zfs.pools);
  datasets = cfg.zfs.datasets // generatedRoots;
  managed = filterAttrs (_: dataset: dataset.managed) datasets;
  poolOf = name: builtins.head (lib.splitString "/" name);
  systemManaged = filterAttrs (
    name: _: (cfg.zfs.pools.${poolOf name} or { role = "system"; }).role == "system"
  ) managed;
  fleetManaged = filterAttrs (
    name: _: (cfg.zfs.pools.${poolOf name} or { role = "system"; }).role == "fleet-data"
  ) managed;
  zfs = "${config.boot.zfs.package}/bin/zfs";

  # Effective mountpoint of a registry entry: the dedicated option, or a raw
  # property for entries that spell it that way. The assertion below rejects
  # declaring it in both places, so at most one of the two is ever set.
  mountpointOf =
    dataset:
    if dataset.mountpoint != null then dataset.mountpoint else dataset.properties.mountpoint or null;

  # Only entries ZFS mounts on a directory have contents worth migrating or a
  # mount unit worth generating; "none" and "legacy" have neither.
  isFilesystemMount =
    dataset:
    let
      mountpoint = mountpointOf dataset;
    in
    mountpoint != null && mountpoint != "none" && mountpoint != "legacy";

  filesystemDatasets = filterAttrs (_: isFilesystemMount) managed;
  diskoDatasets = filterAttrs (name: _: lib.hasPrefix "rpool/" name) filesystemDatasets;
  importServices = lib.unique (
    builtins.filter (service: service != null) (
      mapAttrsToList (_: pool: pool.importService) cfg.zfs.pools
    )
  );

  reconcileDataset =
    name: dataset:
    let
      properties =
        dataset.properties
        // lib.optionalAttrs (dataset.mountpoint != null) {
          mountpoint = dataset.mountpoint;
        };
      createArgs = concatMapStringsSep " " (
        property: "-o ${escapeShellArg property}=${escapeShellArg properties.${property}}"
      ) (builtins.attrNames properties);

      # Reassert declared properties, but only the ones that actually drifted.
      # `zfs set mountpoint=` unmounts and remounts even when the value is
      # unchanged, which on every rebuild that restarts this unit would pull
      # the dataset out from under a consumer already running on top of it.
      reassertProperties = concatMapStringsSep "\n" (
        property:
        let
          key = escapeShellArg property;
          value = escapeShellArg properties.${property};
        in
        ''
          if [ "$(${zfs} get -H -o value ${key} "$dataset")" != ${value} ]; then
            ${zfs} set ${key}=${value} "$dataset"
          fi
        ''
      ) (builtins.attrNames properties);

      migrates = isFilesystemMount dataset;
    in
    ''
      dataset=${escapeShellArg name}
      parent="''${dataset%/*}"
      ${zfs} list -H -o name "$parent" >/dev/null 2>&1 || {
        echo "refusing to create $dataset: declared parent dataset $parent does not exist" >&2
        exit 1
      }
      ${optionalString migrates ''
        mountpoint=${escapeShellArg (mountpointOf dataset)}
        staging="''${mountpoint}.keystone-migration"
        verified="''${mountpoint}.keystone-migration.verified"
      ''}

      if ! ${zfs} list -H -o name "$dataset" >/dev/null 2>&1; then
        ${optionalString migrates ''
          source_has_data=false
          if [ -d "$mountpoint" ] && [ -n "$(find "$mountpoint" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
            source_has_data=true
          fi

          if [ -e "$staging" ] && [ "$source_has_data" = true ]; then
            echo "refusing ambiguous migration for $dataset: both $staging and $mountpoint contain data" >&2
            exit 1
          fi
          ${
            if dataset.preserveExisting then
              # Renaming within the parent filesystem is atomic, so a crash
              # anywhere around it still leaves exactly one copy on disk.
              ''
                if [ "$source_has_data" = true ]; then
                  mv "$mountpoint" "$staging"
                fi
              ''
            else
              ''
                if [ "$source_has_data" = true ]; then
                  echo "refusing to create $dataset over non-empty $mountpoint; set preserveExisting = true to migrate it" >&2
                  exit 1
                fi
              ''
          }
        ''}
        ${zfs} create -u ${createArgs} "$dataset"
      fi

      ${reassertProperties}

      ${optionalString migrates ''
        mkdir -p "$mountpoint"
        if [ "$(${zfs} get -H -o value mounted "$dataset")" != yes ]; then
          ${zfs} mount "$dataset"
        fi

        if [ -e "$staging" ] && [ ! -e "$verified" ]; then
          if [ ! -d "$staging" ]; then
            echo "migration staging path is not a directory: $staging" >&2
            exit 1
          fi

          staged_bytes="$(du -s -B1 "$staging" | cut -f1)"
          used_bytes="$(${zfs} get -Hp -o value used "$dataset")"
          available_bytes="$(${zfs} get -Hp -o value available "$dataset")"
          if [ "$staged_bytes" -gt "$((used_bytes + available_bytes))" ]; then
            echo "insufficient space to migrate $staged_bytes bytes into $dataset" >&2
            exit 1
          fi

          rsync -aHAX --numeric-ids "$staging"/ "$mountpoint"/
          differences="$(rsync -aHAXnc --numeric-ids --itemize-changes "$staging"/ "$mountpoint"/)"
          if [ -n "$differences" ]; then
            echo "dataset migration verification failed for $dataset:" >&2
            printf '%s\n' "$differences" >&2
            exit 1
          fi
          touch "$verified"
        fi
        if [ -e "$verified" ]; then
          rm -rf --one-file-system "$staging"
          rm -f "$verified"
        fi
      ''}
    '';
in
{
  options.keystone.os.storage.zfs = {
    pools = mkOption {
      default.rpool = {
        role = "system";
        importService = null;
      };
      description = "ZFS pools available to the dataset registry.";
      type = types.attrsOf (
        types.submodule {
          options = {
            role = mkOption {
              type = types.enum [
                "system"
                "fleet-data"
              ];
              description = "Whether the pool contains an operating system or fleet data.";
            };
            importService = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Systemd unit that imports a non-root pool before reconciliation.";
            };
            roots = lib.genAttrs rootNames (
              root:
              mkOption {
                type = types.bool;
                default =
                  !builtins.elem root [
                    "migrations"
                    "legacy"
                  ];
                description = "Create the structural ${root} root on a fleet-data pool.";
              }
            );
          };
        }
      );
    };

    datasets = mkOption {
      default = { };
      description = ''
        Registry of ZFS datasets keyed by their full ZFS name. Managed entries
        are created and have declared properties reasserted; observed entries
        are policy inputs only.
      '';
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              class = mkOption {
                type = types.enum [
                  "system"
                  "state"
                  "critical-state"
                  "log"
                  "cache"
                  "ephemeral"
                  "key-escrow"
                ];
                description = "Snapshot and replication policy class for ${name}.";
              };
              role = mkOption {
                type = types.enum [
                  "system"
                  "user"
                  "shared"
                  "service"
                  "device-backup"
                  "vm"
                  "scratch"
                  "replica"
                  "migration"
                  "legacy"
                  "structural"
                ];
                default = "system";
                description = "Fleet layout role for ${name}; independent of snapshot retention class.";
              };
              managed = mkOption {
                type = types.bool;
                default = true;
                description = "Whether Keystone creates the dataset and reasserts its properties.";
              };
              mountpoint = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Optional managed ZFS mountpoint property.";
              };
              preserveExisting = mkOption {
                type = types.bool;
                default = false;
                description = "Migrate existing mountpoint contents when first creating the dataset.";
              };
              properties = mkOption {
                type = types.attrsOf types.str;
                default = { };
                description = "ZFS properties reasserted for a managed dataset.";
              };
            };
          }
        )
      );
    };
  };

  # Consumers with an existing disko layout disable Keystone partitioning but
  # still use this registry to declaratively reconcile datasets.
  config = mkIf (config.keystone.os.enable && cfg.type == "zfs" && managed != { }) (mkMerge [
    {
      assertions =
        mapAttrsToList (
          name: dataset:
          let
            pool = builtins.head (lib.splitString "/" name);
            poolCfg = cfg.zfs.pools.${pool} or null;
          in
          {
            assertion =
              builtins.match "[^/]+/.+" name != null
              && poolCfg != null
              && !(dataset.properties ? mountpoint && dataset.mountpoint != null)
              && (pool == "rpool" || (poolCfg.role == "fleet-data" && poolCfg.importService != null));
            message = "ZFS registry entry '${name}' MUST name a declared pool, avoid duplicate mountpoints, and use an import service for non-rpool fleet-data pools.";
          }
        ) managed
        ++ mapAttrsToList (pool: poolCfg: {
          assertion = pool == "rpool" || poolCfg.role != "fleet-data" || poolCfg.importService != null;
          message = "Fleet-data pool '${pool}' MUST declare importService.";
        }) cfg.zfs.pools;

      systemd.services = mkMerge [
        (mkIf (systemManaged != { }) {
          keystone-zfs-datasets = {
            description = "Reconcile Keystone-managed system ZFS datasets";
            wantedBy = [ "local-fs.target" ];
            after = [ "zfs-mount.service" ];
            requires = [ "zfs-mount.service" ];
            before = [ "local-fs.target" ];
            unitConfig.DefaultDependencies = false;
            path = [
              pkgs.coreutils
              pkgs.findutils
              pkgs.rsync
            ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = concatStringsSep "\n" (mapAttrsToList reconcileDataset systemManaged);
          };
        })
        (mkIf (fleetManaged != { }) {
          keystone-zfs-fleet-datasets = {
            description = "Reconcile Keystone-managed fleet-data ZFS datasets";
            wantedBy = [ "multi-user.target" ];
            after = importServices;
            requires = importServices;
            path = [
              pkgs.coreutils
              pkgs.findutils
              pkgs.rsync
            ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = concatStringsSep "\n" (mapAttrsToList reconcileDataset fleetManaged);
          };
        })
      ];
    }

    # Only hosts whose partitioning Keystone owns get a Disko layout. The
    # guard has to sit above `disko.devices`, not on the `datasets` value: a
    # definition anywhere under `disko.devices.zpool.rpool` instantiates that
    # submodule even when its value is `mkIf false`.
    (mkIf cfg.enable {
      disko.devices.zpool.rpool.datasets = mapAttrs' (
        name: dataset:
        nameValuePair (lib.removePrefix "rpool/" name) {
          type = "zfs_fs";
          options = dataset.properties;
          mountpoint = mountpointOf dataset;
          mountOptions = [ "nofail" ];
        }
      ) diskoDatasets;
    })
  ]);
}
