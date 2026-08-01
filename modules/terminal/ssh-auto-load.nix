# Keystone Terminal SSH Auto-Load
#
# Systemd user service that auto-loads an SSH private key into ssh-agent at login
# using a sops-managed passphrase. Eliminates the manual passphrase prompt on
# first SSH/git use after login.
#
# ## Security Model
#
# SSH private keys are host-bound (generated locally, never stored in the
# secrets repo). Only the passphrase is stored as a sops secret in each
# host's secrets file, since every machine has a different key+passphrase
# pair.
#
# SECURITY: The passphrase file at /run/secrets/* is root-owned, mode 0400,
# readable only by the specified user. The askpass script simply cats it —
# this is the same pattern used by agents.nix for agent SSH keys.
#
# ## Example Usage
#
# ```nix
# # In home-manager config:
# keystone.terminal.sshAutoLoad = {
#   enable = true;
#   # passphrasePath defaults to /run/secrets/${username}-ssh-passphrase
#   # keyFile defaults to ~/.ssh/id_ed25519
# };
#
# # In NixOS host config:
# keystone.secrets.provided."ncrmro-ssh-passphrase" = {
#   owner = "ncrmro";
#   mode = "0400";
# };
# ```
#
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.sshAutoLoad;
  sshCfg = config.keystone.terminal.ssh;
in
{
  options.keystone.terminal.sshAutoLoad = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Auto-load SSH key into ssh-agent at login using a sops-managed passphrase";
    };

    passphrasePath = mkOption {
      type = types.str;
      default = "/run/secrets/${config.home.username}-ssh-passphrase";
      defaultText = literalExpression ''"/run/secrets/''${config.home.username}-ssh-passphrase"'';
      description = "Path to the decrypted passphrase file installed by sops-nix.";
    };

    keyFile = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.ssh/id_ed25519";
      defaultText = literalExpression ''"''${config.home.homeDirectory}/.ssh/id_ed25519"'';
      description = "Path to the SSH private key to load";
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) (
    let
      # Script that outputs the passphrase for SSH_ASKPASS
      # Converges with agents.nix askpassScript pattern
      askpassScript = pkgs.writeShellScript "ssh-askpass" ''
        ${pkgs.coreutils}/bin/cat ${cfg.passphrasePath}
      '';
    in
    {
      # Ensure ssh-agent and ssh client are configured
      services.ssh-agent.enable = true;
      home.packages = [ pkgs.openssh ];

      systemd.user.services.ssh-auto-load = {
        Unit = {
          Description = "Auto-load SSH key into ssh-agent";
          After = [ "ssh-agent.service" ];
          Requires = [ "ssh-agent.service" ];
        };

        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "15s";
          Environment = [
            "SSH_AUTH_SOCK=${sshCfg.authSock}"
          ];

          # Poll for ssh-agent socket readiness (converges with agents.nix:1746-1749)
          ExecStartPre = toString (
            pkgs.writeShellScript "wait-for-ssh-agent" ''
              for i in $(seq 1 50); do
                [ -S "$SSH_AUTH_SOCK" ] && exit 0
                sleep 0.1
              done
              echo "ssh-agent socket not ready after 5s" >&2
              exit 1
            ''
          );

          ExecStart = toString (
            pkgs.writeShellScript "ssh-auto-load" ''
              set -euo pipefail

              key_file=${lib.escapeShellArg cfg.keyFile}
              pubkey_file="$key_file.pub"

              if [[ -f "$pubkey_file" ]]; then
                key_fingerprint="$(${pkgs.openssh}/bin/ssh-keygen -lf "$pubkey_file" | ${pkgs.gawk}/bin/awk '{print $2}')"
                if [[ -n "$key_fingerprint" ]] && ${pkgs.openssh}/bin/ssh-add -l 2>/dev/null | ${pkgs.gnugrep}/bin/grep -Fq -- "$key_fingerprint"; then
                  echo "ssh-auto-load: key already loaded"
                  exit 0
                fi
              fi

              export SSH_ASKPASS="${askpassScript}"
              export SSH_ASKPASS_REQUIRE="force"
              export DISPLAY="none"

              if ${pkgs.coreutils}/bin/timeout 10s ${pkgs.openssh}/bin/ssh-add "$key_file"; then
                exit 0
              else
                status=$?
              fi

              if [[ "$status" -eq 124 ]]; then
                echo "ssh-auto-load: timed out adding key; passphrase secret may be stale" >&2
              else
                echo "ssh-auto-load: failed to add key (exit $status); passphrase secret may be stale" >&2
              fi

              # SSH auto-load is a convenience service. A stale passphrase secret
              # must not wedge Home Manager activation or leave the user manager
              # blocked in a long-running oneshot start.
              exit 0
            ''
          );
        };

        Install = {
          WantedBy = [ "default.target" ];
        };
      };
    }
  );
}
