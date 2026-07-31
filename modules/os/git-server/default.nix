# Forgejo Configuration Cheat Sheet: https://forgejo.org/docs/next/admin/config-cheat-sheet/
# Keystone Git Server Module
#
# Provides a self-hosted git server using Forgejo (Gitea fork):
# - Web-based repository management
# - Issue tracking and pull requests
# - CI/CD integration (via Actions/Runners)
# - User authentication and access control
#
# Forgejo Actions runner is supported via keystone.os.gitServer.runner.
# Enable with runner.enable = true — the token is auto-provisioned at runtime
# by discovering the first admin user and fetching a registration token from
# the Forgejo API. A rootless podman socket is set up for the runner user so
# actions run in rootless containers via DOCKER_HOST.
#
{
  lib,
  config,
  pkgs,
  utils,
  ...
}:
with lib;
let
  cfg = config.keystone.os.gitServer;
  keysCfg = config.keystone.keys;
  runnerUid = 3000;

  # Agents that want git provisioning on this host (where Forgejo runs).
  # This is NOT filtered by agent.host — provisioning runs on the git server,
  # which is typically a different host from the agent's designated host.
  provisionAgents = filterAttrs (_: a: a.git.provision) config.keystone.os.agents;
  hasProvisionAgents = provisionAgents != { };

  # Systemd service name for the gitea-actions-runner instance
  runnerServiceName = "gitea-runner-${utils.escapeSystemdPath cfg.runner.name}";

  # Get an agent's SSH public key from the keystone.keys registry
  agentPublicKey =
    name:
    let
      registryName = "agent-${name}";
      u = keysCfg.${registryName} or null;
      hostKeys = if u != null then mapAttrsToList (_: h: h.publicKey) u.hosts else [ ];
    in
    if hostKeys != [ ] then head hostKeys else null;
in
{
  options.keystone.os.gitServer = {
    enable = mkEnableOption "Git server with Forgejo (self-hosted Gitea fork)";

    domain = mkOption {
      type = types.str;
      default = config.networking.hostName;
      example = "git.example.com";
      description = "Domain name for the git server";
    };

    httpPort = mkOption {
      type = types.port;
      default = 3000;
      description = "HTTP port for Forgejo web interface";
    };

    sshPort = mkOption {
      type = types.port;
      default = 2222;
      description = "SSH port for git operations (separate from system SSH)";
    };

    database = {
      type = mkOption {
        type = types.enum [
          "sqlite3"
          "postgres"
          "mysql"
        ];
        default = "sqlite3";
        description = "Database backend for Forgejo";
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Database host (for postgres/mysql)";
      };

      port = mkOption {
        type = types.port;
        default = 5432;
        description = "Database port (for postgres/mysql)";
      };

      name = mkOption {
        type = types.str;
        default = "forgejo";
        description = "Database name";
      };

      user = mkOption {
        type = types.str;
        default = "forgejo";
        description = "Database user";
      };

      # Password should be set via secrets management
      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing database password";
      };
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/forgejo";
      description = "Directory for Forgejo state and repositories";
    };

    repositoryRoot = mkOption {
      type = types.path;
      default = "${cfg.stateDir}/repositories";
      description = "Root directory for git repositories";
    };

    lfs = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Git LFS (Large File Storage) support";
      };
    };

    mailer = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable email notifications";
      };

      from = mkOption {
        type = types.str;
        default = "noreply@${cfg.domain}";
        description = "From address for emails";
      };

      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "SMTP server host";
      };

      port = mkOption {
        type = types.port;
        default = 25;
        description = "SMTP server port";
      };
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall ports for HTTP and SSH";
    };

    ssh = {
      openFirewall = mkOption {
        type = types.bool;
        default = false;
        description = "Open firewall for Git SSH port";
      };

      tailscaleOnly = mkOption {
        type = types.bool;
        default = false;
        description = "Restrict SSH access to Tailscale interface only (requires openFirewall = true)";
      };
    };

    adminUsers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Forgejo usernames to add as admin collaborators on every provisioned agent repo";
    };

    runner = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Forgejo Actions runner. Enabled by default when the git server is active.";
      };

      name = mkOption {
        type = types.str;
        default = config.networking.hostName;
        description = "Runner name shown in Forgejo UI";
      };
    };
  };

  # Auto-enable when keystone.services.git.host matches this machine's hostname,
  # or when explicitly enabled via keystone.os.gitServer.enable.
  config =
    mkIf
      (
        cfg.enable
        || (
          config.keystone.services.git.host != null
          && config.keystone.services.git.host == config.networking.hostName
        )
      )
      (mkMerge [
        {
          # Forgejo service configuration
          services.forgejo = {
            enable = true;
            package = pkgs.forgejo;
            stateDir = cfg.stateDir;
            lfs.enable = cfg.lfs.enable;

            settings = {
              server = {
                DOMAIN = cfg.domain;
                ROOT_URL = mkDefault "http://${cfg.domain}:${toString cfg.httpPort}/";
                HTTP_PORT = cfg.httpPort;
                SSH_PORT = cfg.sshPort;
                SSH_LISTEN_HOST = "0.0.0.0";
                START_SSH_SERVER = true;
              };

              database = {
                DB_TYPE = cfg.database.type;
              }
              // (
                if cfg.database.type != "sqlite3" then
                  {
                    HOST = "${cfg.database.host}:${toString cfg.database.port}";
                    NAME = cfg.database.name;
                    USER = cfg.database.user;
                    PASSWD = mkIf (cfg.database.passwordFile != null) (builtins.readFile cfg.database.passwordFile);
                  }
                else
                  { }
              );

              repository = {
                ROOT = cfg.repositoryRoot;
              };

              "repository.pull-request" = {
                DEFAULT_MERGE_STYLE = "squash";
                DEFAULT_DELETE_BRANCH_AFTER_MERGE = true;
              };

              # Server-side commit signing (merge commits, web editor, etc.)
              # SIGNING_KEY must point to the SSH public key file (.pub) — Forgejo
              # calls ssh.ParseAuthorizedKey() on the file contents, not the private key.
              # The corresponding private key is used by the built-in SSH server for signing.
              "repository.signing" = {
                SIGNING_KEY = "${cfg.stateDir}/ssh/ssh_host_ed25519_key.pub";
                FORMAT = "ssh";
                SIGNING_NAME = "Forgejo";
                SIGNING_EMAIL = "noreply@${cfg.domain}";
              };

              mailer = mkIf cfg.mailer.enable {
                ENABLED = true;
                FROM = cfg.mailer.from;
                SMTP_ADDR = cfg.mailer.host;
                SMTP_PORT = cfg.mailer.port;
              };

              service = {
                DISABLE_REGISTRATION = mkDefault false;
                REQUIRE_SIGNIN_VIEW = mkDefault false;
              };

              # Enable Actions (GitHub Actions compatible CI/CD)
              actions = {
                ENABLED = true;
              };
            };
          };

          # Firewall configuration for HTTP (when openFirewall is true)
          networking.firewall.allowedTCPPorts =
            (optionals cfg.openFirewall [
              cfg.httpPort
              cfg.sshPort
            ])
            ++ (optionals (cfg.ssh.openFirewall && !cfg.ssh.tailscaleOnly) [ cfg.sshPort ]);

          # SSH firewall: restrict to Tailscale interface only
          networking.firewall.interfaces."tailscale0".allowedTCPPorts = mkIf (
            cfg.ssh.openFirewall && cfg.ssh.tailscaleOnly
          ) [ cfg.sshPort ];

          # Add helpful packages
          environment.systemPackages = with pkgs; [
            forgejo
            git
          ];

        }
        {
          # Auto-provision Forgejo users and repos for agents with git.provision = true.
          # Uses `forgejo admin` CLI for user creation (must run as the forgejo system
          # user — hence sudo -u) and the local API with a short-lived token for SSH
          # keys and repos. The token is scoped to the agent's own user (--username),
          # not the global admin. The --raw flag outputs just the token string.
          systemd.services = mkIf hasProvisionAgents (
            mapAttrs' (
              name: agentCfg:
              let
                username = agentCfg.git.username;
                email =
                  if agentCfg.email != null then agentCfg.email else "agent-${name}@${config.keystone.domain}";
                repoName = agentCfg.git.repoName;
                apiUrl = "http://127.0.0.1:${toString cfg.httpPort}/api/v1";
                forgejoUser = config.services.forgejo.user;
              in
              nameValuePair "provision-agent-git-${name}" {
                description = "Provision Forgejo user and repo for agent-${name}";
                after = [
                  "forgejo.service"
                  "home-manager-agent-${name}.service"
                ];
                requires = [ "forgejo.service" ];
                wantedBy = [ "multi-user.target" ];

                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                };

                path = [
                  pkgs.forgejo
                  pkgs.curl
                  pkgs.jq
                  pkgs.coreutils
                  pkgs.sudo
                  pkgs.yq-go
                ];

                environment = {
                  FORGEJO_USER = forgejoUser;
                  STATE_DIR = cfg.stateDir;
                  API_URL = apiUrl;
                  USERNAME = username;
                  EMAIL = email;
                  REPO_NAME = repoName;
                  AGENT_NAME = name;
                  DOMAIN = cfg.domain;
                  AGENT_PUBKEY =
                    let
                      pubKey = agentPublicKey name;
                    in
                    if pubKey != null then pubKey else "";
                  ADMIN_USERS_JSON = builtins.toJSON cfg.adminUsers;
                };

                script = builtins.readFile ./scripts/provision-agent-git.sh;
              }
            ) provisionAgents
          );
        }
        (mkIf cfg.runner.enable (
          let
            runnerSettings = {
              runner.file = ".runner";
            };
            runnerConfigFile =
              (pkgs.formats.yaml { }).generate "forgejo-runner-${cfg.runner.name}-config.yaml"
                runnerSettings;
            runnerDaemonWrapper = pkgs.writeShellScript "forgejo-runner-daemon-${cfg.runner.name}" ''
              set -euo pipefail

              uid="$(${pkgs.coreutils}/bin/id -u gitea-runner)"
              export XDG_RUNTIME_DIR="/run/user/$uid"
              export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"

              exec ${config.services.gitea-actions-runner.package}/bin/act_runner daemon --config ${runnerConfigFile}
            '';
          in
          {
            # Rootless podman for the runner user.
            # The gitea-actions-runner module uses DynamicUser=true with User="gitea-runner".
            # Declaring a static user with the same name causes systemd to reuse it
            # (per the DynamicUser docs), giving us a stable user we can set up linger for.
            virtualisation.podman.enable = true;

            users.users.gitea-runner = {
              isNormalUser = true;
              uid = runnerUid; # Service-level normal user range (3000-3999)
              createHome = true;
              group = "gitea-runner";
              home = "/var/lib/gitea-runner";
            };
            users.groups.gitea-runner = { };

            # Linger keeps the gitea-runner user session alive across boots so that
            # user-level systemd units (including podman.socket) start without login.
            systemd.tmpfiles.rules = [
              "f /var/lib/systemd/linger/gitea-runner 0644 root root -"
            ];

            # Start the lingering gitea-runner user manager before the runner
            # starts, then wait for the globally-enabled rootless podman socket to
            # appear. Avoid `systemctl --user -M gitea-runner@` here because PID 1
            # context is prone to "Transport endpoint is not connected" failures.
            systemd.services."forgejo-runner-podman-socket" = {
              description = "Start rootless podman socket for Forgejo runner";
              wantedBy = [ "multi-user.target" ];
              before = [ "${runnerServiceName}.service" ];
              after = [ "systemd-user-sessions.service" ];
              path = [
                pkgs.coreutils
                pkgs.systemd
              ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              script = ''
                uid="$(id -u gitea-runner)"
                socket_path="/run/user/$uid/podman/podman.sock"

                systemctl start "user@$uid.service"

                # Wait for the lingering user manager to bring up the global
                # podman.socket user unit. Retry for up to 30 s.
                for i in $(seq 1 30); do
                  if [ -S "$socket_path" ]; then
                    exit 0
                  fi
                  sleep 1
                done

                echo "Timed out waiting for Forgejo runner podman socket at $socket_path" >&2
                systemctl status "user@$uid.service" --no-pager || true
                exit 1
              '';
            };

            # Point the runner at the rootless podman socket by deriving
            # XDG_RUNTIME_DIR from the live service user at startup time.
            systemd.services.${runnerServiceName} = {
              serviceConfig = {
                DynamicUser = mkForce false;
                User = "gitea-runner";
                Group = "gitea-runner";
                ExecStart = mkForce runnerDaemonWrapper;
              };
            };

            # Token auto-provisioning: discovers the first admin user at runtime,
            # generates a short-lived write:admin token, fetches the runner
            # registration token, then deletes the temp token.
            #
            # SECURITY: The temp token is scoped to write:admin and deleted on exit.
            # The TOKEN env-file is written to a root-owned path under
            # /var/lib/forgejo-runner and read by the runner via EnvironmentFile=.
            systemd.services."provision-runner-token-${cfg.runner.name}" = {
              description = "Provision Forgejo Actions runner registration token for ${cfg.runner.name}";
              after = [ "forgejo.service" ];
              requires = [ "forgejo.service" ];
              before = [ "${runnerServiceName}.service" ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                StateDirectory = "forgejo-runner";
                StateDirectoryMode = "0700";
              };

              path = [
                pkgs.forgejo
                pkgs.curl
                pkgs.jq
                pkgs.coreutils
                pkgs.sudo
                pkgs.gawk
              ];

              environment = {
                FORGEJO_USER = config.services.forgejo.user;
                STATE_DIR = cfg.stateDir;
                API_URL = "http://127.0.0.1:${toString cfg.httpPort}/api/v1";
                TOKEN_FILE = "/var/lib/forgejo-runner/runner-token";
              };

              script = builtins.readFile ./scripts/provision-runner-token.sh;
            };

            # Use the official Forgejo runner (pkgs.forgejo-runner) rather than the
            # older gitea act_runner (pkgs.gitea-actions-runner) that the module
            # defaults to. Labels follow the standard Forgejo runner label format
            # (see `forgejo-runner generate-config`); docker:// scheme is satisfied
            # by the rootless podman socket via DOCKER_HOST above.
            services.gitea-actions-runner.package = pkgs.forgejo-runner;
            services.gitea-actions-runner.instances.${cfg.runner.name} = {
              enable = true;
              name = cfg.runner.name;
              url = "http://127.0.0.1:${toString cfg.httpPort}";
              settings = runnerSettings;
              labels = [
                "native:host"
                "ubuntu-latest:docker://node:20-bookworm"
                "ubuntu-22.04:docker://node:20-bookworm"
                "ubuntu-20.04:docker://node:20-focal"
              ];
              tokenFile = "/var/lib/forgejo-runner/runner-token";
            };
          }
        ))
      ]);
}
