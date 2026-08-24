# Classed ZFS dataset registry and non-destructive reconciler (REQ-033).
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
  datasets = cfg.zfs.datasets;
  managed = filterAttrs (_: dataset: dataset.managed) datasets;
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
  options.keystone.os.storage.zfs.datasets = mkOption {
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

  # Consumers with an existing disko layout disable Keystone partitioning but
  # still use this registry to declaratively reconcile datasets.
  config = mkIf (config.keystone.os.enable && cfg.type == "zfs" && managed != { }) (mkMerge [
    {
      assertions = mapAttrsToList (name: dataset: {
        assertion =
          lib.hasPrefix "rpool/" name && !(dataset.properties ? mountpoint && dataset.mountpoint != null);
        message = "ZFS registry entry '${name}' MUST use an rpool/ name and MUST NOT declare mountpoint twice.";
      }) managed;

      systemd.services.keystone-zfs-datasets = {
        description = "Reconcile Keystone-managed ZFS datasets";
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
        script = concatStringsSep "\n" (mapAttrsToList reconcileDataset managed);
      };
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
      ) filesystemDatasets;
    })
  ]);
}
