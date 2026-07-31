# SSH agent configuration: ssh-agent + git signing + agenix secrets.
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
    topDomain
    agentsWithUids
    useZfs
    sshAgents
    hasSshAgents
    ;
in
{
  config = mkIf (osCfg.enable && cfg != { } && hasSshAgents) {
    # Only assert agenix secrets on the agent's host — other hosts (e.g. ocean)
    # import agent-identities for provisioning but don't need SSH key secrets.
    assertions = concatLists (
      mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
          isAgentHost = agentCfg.host == config.networking.hostName;
        in
        optionals isAgentHost [
          {
            assertion = config.age.secrets ? "${username}-ssh-key";
            message = ''
              Agent '${name}' requires agenix secret "${username}-ssh-key".

              1. Generate an SSH key pair for the agent:
                 ssh-keygen -t ed25519 -C "${username}" -f /tmp/${username}-ssh-key
                 # Enter a passphrase when prompted (you'll need it for the passphrase secret too)

              2. Add the PUBLIC key to the keys registry:
                 keystone.keys."${username}".hosts.<hostname>.publicKey = "$(cat /tmp/${username}-ssh-key.pub)";

              3. Add to agenix-secrets/secrets.nix:
                 "secrets/${username}-ssh-key.age".publicKeys = adminKeys ++ [ systems.workstation ];

              4. Enroll the PRIVATE key as an agenix secret:
                 cd agenix-secrets && cp /tmp/${username}-ssh-key secrets/${username}-ssh-key.age.plain
                 agenix -e secrets/${username}-ssh-key.age  # paste the private key contents
                 rm /tmp/${username}-ssh-key /tmp/${username}-ssh-key.pub secrets/${username}-ssh-key.age.plain

              5. Declare in host config:
                 age.secrets.${username}-ssh-key = {
                   file = "${"$"}{inputs.agenix-secrets}/secrets/${username}-ssh-key.age";
                   owner = "${username}";
                   mode = "0400";
                 };
            '';
          }
          {
            assertion = config.age.secrets ? "${username}-ssh-passphrase";
            message = ''
              Agent '${name}' requires agenix secret "${username}-ssh-passphrase".

              1. Add to agenix-secrets/secrets.nix:
                 "secrets/${username}-ssh-passphrase.age".publicKeys = adminKeys ++ [ systems.workstation ];

              2. Create the secret (use the SAME passphrase from ssh-keygen):
                 cd agenix-secrets && agenix -e secrets/${username}-ssh-passphrase.age

              3. Declare in host config:
                 age.secrets.${username}-ssh-passphrase = {
                   file = "${"$"}{inputs.agenix-secrets}/secrets/${username}-ssh-passphrase.age";
                   owner = "${username}";
                   mode = "0400";
                 };
            '';
          }
          # Bitwarden/Vaultwarden password — rbw pinentry reads from
          # /run/agenix/agent-{name}-bitwarden-password at runtime. Without
          # this assertion, the build succeeds but rbw silently fails.
          {
            assertion = config.age.secrets ? "${username}-bitwarden-password";
            message = ''
              Agent '${name}' requires agenix secret "${username}-bitwarden-password".

              1. Add to agenix-secrets/secrets.nix:
                 "secrets/${username}-bitwarden-password.age".publicKeys = adminKeys ++ [ systems.${agentCfg.host} ];

              2. Create the secret:
                 cd agenix-secrets && agenix -e secrets/${username}-bitwarden-password.age

              3. Declare in host config:
                 age.secrets.${username}-bitwarden-password = {
                   file = "${"$"}{inputs.agenix-secrets}/secrets/${username}-bitwarden-password.age";
                   owner = "${username}";
                   mode = "0400";
                 };

              4. Create a Vaultwarden account for ${username} at
                 https://vaultwarden.${if topDomain != null then topDomain else "example.com"}
                 using the SAME password as the agenix secret.
            '';
          }
        ]
      ) sshAgents
    );

    # Enable OpenSSH
    services.openssh.enable = true;

    # ssh-agent + git-config systemd services per SSH-enabled agent
    systemd.services = mkMerge (
      mapAttrsToList (
        name: agentCfg:
        let
          username = "agent-${name}";
          resolved = agentsWithUids.${name};
          uid = resolved.uid;
          sshKeyPath = "/run/agenix/${username}-ssh-key";
          sshPassphrasePath = "/run/agenix/${username}-ssh-passphrase";
          homesService = if useZfs then "zfs-agent-datasets.service" else "agent-homes.service";
          # Script that outputs the passphrase for SSH_ASKPASS
          askpassScript = pkgs.writeShellScript "ssh-askpass-${username}" ''
            ${pkgs.coreutils}/bin/cat ${sshPassphrasePath}
          '';
          # Script to add the key to the running ssh-agent
          addKeyScript = pkgs.writeShellScript "ssh-add-key-${username}" ''
            # Wait for the ssh-agent socket to be ready
            for i in $(seq 1 50); do
              [ -S "/run/agent-${name}-ssh-agent/agent.sock" ] && break
              sleep 0.1
            done
            export SSH_AUTH_SOCK="/run/agent-${name}-ssh-agent/agent.sock"
            export SSH_ASKPASS="${askpassScript}"
            export SSH_ASKPASS_REQUIRE="force"
            export DISPLAY="none"
            ${pkgs.openssh}/bin/ssh-add ${sshKeyPath}
          '';
        in
        {
          # ssh-agent daemon (foreground mode with -D)
          "agent-${name}-ssh-agent" = {
            description = "SSH agent for ${username}";

            wantedBy = [ "multi-user.target" ];
            after = [ homesService ];
            requires = [ homesService ];

            environment = {
              SSH_AUTH_SOCK = "/run/agent-${name}-ssh-agent/agent.sock";
            };

            serviceConfig = {
              Type = "simple";
              User = username;
              Group = "agents";
              RuntimeDirectory = "agent-${name}-ssh-agent";
              RuntimeDirectoryMode = "0700";
              ExecStart = "${pkgs.openssh}/bin/ssh-agent -D -a /run/agent-${name}-ssh-agent/agent.sock";
              ExecStartPost = "${addKeyScript}";
              Restart = "always";
              RestartSec = 5;
            };
          };

          # Git SSH signing is now handled by keystone.terminal via home-manager
          # (git.signingKey + allowed_signers). No separate systemd service needed.
        }
      ) sshAgents
    );
  };
}
