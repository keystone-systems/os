# Base agent configuration: user creation, groups, tmpfiles, sudo, home dirs, activation.
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  agentsLib = import ./lib.nix { inherit lib config pkgs; };
  inherit (agentsLib)
    osCfg
    cfg
    agentsWithUids
    useZfs
    allKeysForAgent
    labwcConfigScript
    sortedAgentNames
    ;
in
{
  config = mkMerge [
    (mkIf (osCfg.enable && cfg != { }) {
      # REQ-017.11: warn when Grafana MCP is enabled but no secret is provisioned
      warnings = concatLists (
        mapAttrsToList (
          name: agentCfg:
          optional agentCfg.grafana.mcp.enable "Agent '${name}' has grafana.mcp.enable = true. Ensure the agenix secret 'grafana-api-token' is provisioned and decryptable on this host."
        ) cfg
      );

      assertions = [
        # All agent UIDs must be unique
        {
          assertion =
            let
              uids = mapAttrsToList (_: a: a.uid) agentsWithUids;
              uniqueUids = unique uids;
            in
            length uids == length uniqueUids;
          message = "All agent UIDs must be unique";
        }
        # Agent UIDs must not collide with human user UIDs
        {
          assertion =
            let
              agentUids = mapAttrsToList (_: a: a.uid) agentsWithUids;
              humanUids = filter (u: u != null) (mapAttrsToList (_: u: u.uid) osCfg.users);
            in
            all (aUid: !elem aUid humanUids) agentUids;
          message = "Agent UIDs must not collide with human user UIDs";
        }
      ];

      # Create the agents group (agents belong here) and agent-admins (human users who manage agents)
      users.groups.agents = { };
      users.groups.agent-admins = { };

      # Allow agent-admins to access agent user dbus sockets for systemctl --user -M
      # systemd-logind creates /run/user/<uid> as 0700; we add an ACL so agent-admins
      # can traverse the directory and connect to the bus socket.
      # For all defined agents.
      systemd.tmpfiles.rules = concatLists (
        mapAttrsToList (
          name: _:
          let
            username = "agent-${name}";
            resolved = agentsWithUids.${name};
          in
          [
            "a /run/user/${toString resolved.uid} - - - - g:agent-admins:x"
            "a /run/user/${toString resolved.uid}/bus - - - - g:agent-admins:rw"
          ]
        ) cfg
      );

      # SECURITY: The helper script is the sole sudoers target. SETENV is NOT
      # granted — the script hardcodes XDG_RUNTIME_DIR internally. This prevents
      # LD_PRELOAD injection that SETENV would allow. The helper's verb allowlist
      # prevents dangerous systemctl verbs (edit, set-environment, import-environment).
      security.sudo.extraRules = mapAttrsToList (name: _: {
        groups = [ "agent-admins" ];
        runAs = "agent-${name}";
        commands = [
          {
            command = "${agentsLib.agentSvcHelper name}";
            options = [ "NOPASSWD" ];
          }
        ];
      }) cfg;

      # Add all keystone.os.users to agent-admins so they can read agent home dirs
      users.users = mkMerge [
        (mapAttrs (_: _: {
          extraGroups = [ "agent-admins" ];
        }) config.keystone.os.users)

        # Generate NixOS users for all defined agents
        (mapAttrs' (
          name: agentCfg:
          let
            username = "agent-${name}";
            resolved = agentsWithUids.${name};
          in
          nameValuePair username {
            isNormalUser = true;
            uid = resolved.uid;
            description = agentCfg.fullName;
            home = "/home/${username}";
            createHome = !useZfs;
            homeMode = "2770";
            group = "agents";
            extraGroups = optionals useZfs [ "zfs" ];
            shell = pkgs.zsh;
            linger = true;
            openssh.authorizedKeys.keys = allKeysForAgent name;
            # No password -- agents are non-interactive

            # Rootless Podman requires subordinate UID/GID ranges for user
            # namespace mapping. Each agent gets a non-overlapping 65536-wide
            # range starting at 100000 + (idx * 65536).
            subUidRanges =
              let
                idx =
                  findFirst (i: elemAt sortedAgentNames i == name)
                    (throw "agent '${name}' not found in sortedAgentNames")
                    (genList (x: x) (length sortedAgentNames));
              in
              [
                {
                  startUid = 100000 + idx * 65536;
                  count = 65536;
                }
              ];
            subGidRanges =
              let
                idx =
                  findFirst (i: elemAt sortedAgentNames i == name)
                    (throw "agent '${name}' not found in sortedAgentNames")
                    (genList (x: x) (length sortedAgentNames));
              in
              [
                {
                  startGid = 100000 + idx * 65536;
                  count = 65536;
                }
              ];
          }
        ) cfg)
      ];

      # Fix agent home ownership after NixOS user creation (activation runs after useradd)
      # useradd sets group to "agents" (the user's primary group), but we need "agent-admins"
      # so human administrators can read agent home directories.
      # setgid (2xxx) ensures new files inherit agent-admins group.
      # Default ACL ensures new files get group write regardless of umask.
      # For all defined agents.
      system.activationScripts.agent-home-permissions = {
        deps = [
          "users"
          "groups"
        ];
        text = ''
          ${concatStringsSep "\n" (
            mapAttrsToList (
              name: _:
              let
                username = "agent-${name}";
              in
              ''
                if [ -d /home/${username} ]; then
                  chown ${username}:agent-admins /home/${username}
                  chmod 2770 /home/${username}
                  ${pkgs.acl}/bin/setfacl -d -m g::rwx /home/${username}
                  for _qf_name in TASKS PROJECTS; do
                    _qf="/home/${username}/$_qf_name.yaml"
                    if [ ! -f "$_qf" ]; then
                      _key=$(echo "$_qf_name" | tr '[:upper:]' '[:lower:]')
                      printf -- '---\n%s: []\n' "$_key" > "$_qf"
                      chown ${username}:agent-admins "$_qf"
                      chmod 0660 "$_qf"
                    fi
                  done
                fi
              ''
            ) cfg
          )}
        '';
      };

      # Home directory creation for ext4
      systemd.services.agent-homes = mkIf (!useZfs) {
        description = "Create and configure agent home directories";

        wantedBy = [ "multi-user.target" ];
        before = [ "systemd-user-sessions.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          ${concatStringsSep "\n" (
            mapAttrsToList (
              name: agentCfg:
              let
                username = "agent-${name}";
              in
              ''
                if [ ! -d /home/${username} ]; then
                  mkdir -p /home/${username}
                fi
                chown ${username}:agent-admins /home/${username}
                chmod 2770 /home/${username}
                ${pkgs.acl}/bin/setfacl -d -m g::rwx /home/${username}
                for _qf_name in TASKS PROJECTS; do
                  _qf="/home/${username}/$_qf_name.yaml"
                  if [ ! -f "$_qf" ]; then
                    _key=$(echo "$_qf_name" | tr '[:upper:]' '[:lower:]')
                    printf -- '---\n%s: []\n' "$_key" > "$_qf"
                    chown ${username}:agent-admins "$_qf"
                    chmod 0660 "$_qf"
                  fi
                done

                ${labwcConfigScript username agentCfg}
              ''
            ) cfg
          )}
        '';
      };

      /*
        # ZFS dataset creation for agent homes
        # TODO: Re-evaluate ZFS home folder management for agents before re-enabling.
        systemd.services.zfs-agent-datasets = mkIf useZfs {
          description = "Create ZFS datasets for agent home directories";

          wantedBy = [ "multi-user.target" ];
          after = [ "zfs-mount.service" ];
          before = [ "systemd-user-sessions.service" ];
          requires = [ "zfs-mount.service" ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };

          path = [ config.boot.zfs.package ];

          script = ''
            set -euo pipefail

            # Create parent home dataset if needed
            if ! zfs list -H -o name rpool/crypt/home > /dev/null 2>&1; then
              zfs create -o mountpoint=/home rpool/crypt/home
            fi

            ${concatStringsSep "\n" (
              mapAttrsToList (
                name: agentCfg:
                let
                  username = "agent-${name}";
                in
                ''
                  zfs create -p -o mountpoint=/home/${username} rpool/crypt/home/${username} 2>/dev/null || true
                  zfs set compression=lz4 rpool/crypt/home/${username}
                  chown ${username}:agent-admins /home/${username}
                  chmod 2770 /home/${username}
                  ${pkgs.acl}/bin/setfacl -d -m g::rwx /home/${username}

                  ${labwcConfigScript username agentCfg}
                ''
              ) cfg
            )}
          '';
        };
      */
    })
  ];
}
