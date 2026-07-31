# D-Bus socket race condition fix.
#
# When nixos-rebuild switch restarts user@UID.service, the old systemd user
# instance's cleanup ("Closed D-Bus User Message Bus Socket") races with the
# new instance's setup ("Listening on D-Bus User Message Bus Socket"). Both
# happen within the same second, and the old instance can delete the socket
# file the new one just created. This leaves the new instance with a stale
# file descriptor and no socket at /run/user/UID/bus.
#
# Cascading effects: Home Manager activation sees "User systemd daemon not
# running. Skipping reload." Chromium spams D-Bus errors. agentctl commands
# all fail with "Failed to connect to user scope bus".
#
# This system-level oneshot runs after user@UID.service, waits for the race
# window to close, and restarts the user service if the socket is missing.
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  agentsLib = import ./lib.nix { inherit lib config pkgs; };
  inherit (agentsLib) osCfg cfg agentsWithUids;
in
{
  config = mkIf (osCfg.enable && cfg != { }) {
    systemd.services = mkMerge (
      mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
          resolved = agentsWithUids.${name};
          uid = resolved.uid;
          socket = "/run/user/${toString uid}/bus";
        in
        {
          "agent-${name}-ensure-dbus" = {
            description = "Ensure D-Bus socket exists for ${username}";
            after = [ "user@${toString uid}.service" ];
            requires = [ "user@${toString uid}.service" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              set -euo pipefail

              # Brief wait for the old instance's cleanup to finish (the race window)
              sleep 2

              if [ -S "${socket}" ]; then
                echo "${username}: D-Bus socket OK"
                exit 0
              fi

              echo "${username}: D-Bus socket missing at ${socket}, restarting user@${toString uid}.service"
              systemctl restart "user@${toString uid}.service"

              # Wait for socket to appear (max 10s)
              for i in $(seq 1 20); do
                [ -S "${socket}" ] && { echo "${username}: D-Bus socket restored"; exit 0; }
                sleep 0.5
              done

              echo "WARNING: ${username}: D-Bus socket still missing after restart" >&2
              exit 1
            '';
          };
        }
      ) cfg
    );
  };
}
