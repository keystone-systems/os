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
    escapeShellArg
    filterAttrs
    mapAttrsToList
    mkIf
    mkOption
    optionalString
    types
    ;
  cfg = config.keystone.os.storage;
  datasets = cfg.zfs.datasets;
  managed = filterAttrs (_: dataset: dataset.managed) datasets;
  zfs = "${config.boot.zfs.package}/bin/zfs";

  renderProperties =
    properties:
    concatMapStringsSep " " (
      property: "-o ${escapeShellArg property}=${escapeShellArg properties.${property}}"
    ) (builtins.attrNames properties);

  reconcileDataset =
    name: dataset:
    let
      properties =
        dataset.properties
        // lib.optionalAttrs (dataset.mountpoint != null) {
          mountpoint = dataset.mountpoint;
        };
      mountpoint = properties.mountpoint or null;
      createArgs = renderProperties properties;
    in
    ''
      dataset=${escapeShellArg name}
      if ! ${zfs} list -H -o name "$dataset" >/dev/null 2>&1; then
        ${optionalString (mountpoint != null && mountpoint != "none" && mountpoint != "legacy") ''
          mountpoint=${escapeShellArg mountpoint}
          if [ -d "$mountpoint" ] && [ -n "$(find "$mountpoint" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
            echo "refusing to create $dataset over non-empty $mountpoint" >&2
            exit 1
          fi
        ''}
        ${zfs} create -u ${createArgs} "$dataset"
      fi
      ${concatMapStringsSep "\n" (property: ''
        ${zfs} set ${escapeShellArg property}=${escapeShellArg properties.${property}} "$dataset"
      '') (builtins.attrNames properties)}
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

  config = mkIf (config.keystone.os.enable && cfg.enable && cfg.type == "zfs" && managed != { }) {
    assertions = mapAttrsToList (name: dataset: {
      assertion =
        lib.hasPrefix "rpool/" name && !(dataset.properties ? mountpoint && dataset.mountpoint != null);
      message = "ZFS registry entry '${name}' MUST use an rpool/ name and MUST NOT declare mountpoint twice.";
    }) managed;

    systemd.services.keystone-zfs-datasets = {
      description = "Reconcile Keystone-managed ZFS datasets";
      wantedBy = [ "multi-user.target" ];
      after = [ "zfs.target" ];
      requires = [ "zfs.target" ];
      before = [ "local-fs.target" ];
      path = [ pkgs.findutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = concatMapStringsSep "\n" (entry: reconcileDataset entry.name entry.value) (
        mapAttrsToList (name: value: { inherit name value; }) managed
      );
    };
  };
}
