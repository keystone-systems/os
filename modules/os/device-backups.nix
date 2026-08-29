# Per-device backup datasets and fail-closed Samba exports.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    attrNames
    attrValues
    concatMapStringsSep
    filter
    findFirst
    genAttrs
    mapAttrs'
    mapAttrsToList
    mkIf
    mkOption
    nameValuePair
    types
    unique
    ;
  cfg = config.keystone.os.storage;
  backups = cfg.deviceBackups;
  backupList = attrValues backups;
  users = unique (map (backup: backup.auth.user) backupList);
  userServices = map (user: "keystone-samba-user-${user}.service") users;
  leaf = backup: if backup.kind == "time-machine" then "timemachine" else "files";
  dataset = name: backup: "${backup.pool}/device-backups/${name}/${leaf backup}";
  mountpoint = name: backup: "/${dataset name backup}";
  userBackup = user: findFirst (backup: backup.auth.user == user) null backupList;
  shares = mapAttrs' (
    name: backup:
    nameValuePair backup.shareName (
      {
        path = mountpoint name backup;
        "hosts allow" = lib.concatStringsSep " " backup.allowedNetworks;
        "valid users" = backup.auth.user;
        "force user" = backup.auth.user;
        "force group" = backup.auth.user;
        "read only" = "no";
        browseable = "yes";
        "create mask" = "0600";
        "directory mask" = "0700";
        "vfs objects" = "catia fruit streams_xattr";
      }
      // lib.optionalAttrs (backup.kind == "time-machine") {
        "fruit:time machine" = "yes";
        "fruit:time machine max size" = backup.quota;
      }
    )
  ) backups;
in
{
  options.keystone.os.storage.deviceBackups = mkOption {
    default = { };
    description = "Per-device file and Time Machine backup datasets exported by Samba.";
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            pool = mkOption {
              type = types.str;
              description = "Declared fleet-data pool that stores this device backup.";
            };
            kind = mkOption {
              type = types.enum [
                "time-machine"
                "files"
              ];
              description = "Backup protocol and leaf dataset type.";
            };
            quota = mkOption {
              type = types.str;
              description = "Hard ZFS quota and advertised Time Machine maximum.";
            };
            shareName = mkOption {
              type = types.str;
              default = "timemachine-${name}";
              description = "Unique Samba share name.";
            };
            auth = {
              user = mkOption {
                type = types.str;
                default = "timemachine";
                description = "Local and Samba account allowed to write this backup.";
              };
              passwordFile = mkOption {
                type = types.str;
                description = "Runtime secret file containing the Samba password.";
              };
            };
            allowedNetworks = mkOption {
              type = types.listOf types.str;
              default = config.keystone.os.networks.headscale;
              description = "Networks allowed to reach this backup share.";
            };
          };
        }
      )
    );
  };

  config = mkIf (config.keystone.os.enable && backups != { }) {
    assertions =
      mapAttrsToList (name: backup: {
        assertion =
          builtins.hasAttr backup.pool cfg.zfs.pools && cfg.zfs.pools.${backup.pool}.role == "fleet-data";
        message = "Device backup '${name}' MUST use a declared fleet-data pool.";
      }) backups
      ++ [
        {
          assertion =
            builtins.length (map (backup: backup.shareName) backupList)
            == builtins.length (unique (map (backup: backup.shareName) backupList));
          message = "Device backup Samba share names MUST be unique.";
        }
        {
          assertion = builtins.all (
            user:
            let
              passwordFiles = unique (
                map (backup: backup.auth.passwordFile) (filter (backup: backup.auth.user == user) backupList)
              );
            in
            builtins.length passwordFiles == 1
          ) users;
          message = "Device backups sharing an auth user MUST use the same password file.";
        }
      ];

    keystone.os.storage.zfs.datasets = lib.mkMerge (
      mapAttrsToList (
        name: backup:
        let
          parent = "${backup.pool}/device-backups/${name}";
          target = dataset name backup;
        in
        {
          ${parent} = {
            class = "ephemeral";
            role = "structural";
            properties = {
              canmount = "off";
              mountpoint = "none";
            };
          };
          ${target} = {
            class = "critical-state";
            role = "device-backup";
            mountpoint = "/${target}";
            properties = {
              compression = "lz4";
              quota = backup.quota;
            };
          };
        }
      ) backups
    );

    users.groups = genAttrs users (_: { });
    users.users = genAttrs users (user: {
      isSystemUser = true;
      group = user;
      home = "/var/empty";
      createHome = false;
    });

    services.samba = {
      enable = true;
      openFirewall = true;
      settings = {
        global = {
          workgroup = "WORKGROUP";
          "server string" = "Keystone backup server";
          "netbios name" = config.networking.hostName;
          security = "user";
          "hosts deny" = "0.0.0.0/0";
          "map to guest" = "bad user";
          "server smb encrypt" = "required";
          "server min protocol" = "SMB3_00";
          "fruit:aapl" = "yes";
          "fruit:nfs_aces" = "no";
          "fruit:copyfile" = "no";
        };
      }
      // shares;
    };

    systemd.services = {
      samba-smbd = {
        requires = [ "keystone-device-backup-mounts.service" ] ++ userServices;
        after = [ "keystone-device-backup-mounts.service" ] ++ userServices;
      };
      keystone-device-backup-mounts = {
        description = "Verify exact device-backup mounts before Samba";
        requires = [ "keystone-zfs-fleet-datasets.service" ];
        after = [ "keystone-zfs-fleet-datasets.service" ];
        before = [ "samba-smbd.service" ];
        requiredBy = [ "samba-smbd.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.util-linux
        ];
        script = concatMapStringsSep "\n" (
          name:
          let
            backup = backups.${name};
            target = dataset name backup;
            path = mountpoint name backup;
          in
          ''
            test "$(findmnt -n -o SOURCE --target ${lib.escapeShellArg path})" = ${lib.escapeShellArg target}
            test "$(findmnt -n -o TARGET --target ${lib.escapeShellArg path})" = ${lib.escapeShellArg path}
            chown ${lib.escapeShellArg "${backup.auth.user}:${backup.auth.user}"} ${lib.escapeShellArg path}
            chmod 0700 ${lib.escapeShellArg path}
          ''
        ) (attrNames backups);
      };
    }
    // lib.listToAttrs (
      map (
        user:
        let
          backup = userBackup user;
        in
        {
          name = "keystone-samba-user-${user}";
          value = {
            description = "Configure Samba password for ${user}";
            before = [ "samba-smbd.service" ];
            requiredBy = [ "samba-smbd.service" ];
            after = [ "network.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              password="$(tr -d '\n' < ${lib.escapeShellArg backup.auth.passwordFile})"
              printf '%s\n%s\n' "$password" "$password" | ${pkgs.samba}/bin/smbpasswd -a -s ${lib.escapeShellArg user}
            '';
          };
        }
      ) users
    );
  };
}
