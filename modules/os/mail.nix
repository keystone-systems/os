# TODO this should move to a dedicated server-os module at some point to delinate it from deskop (maybe)
# Keystone Mail Server (Stalwart)
#
# See conventions/tool.stalwart.md
# Implements REQ-007 (OS Agents — FR-004: Email via Stalwart)
# See docs/specs/REQ-024-agentic-calendar.md (REQ-024.19, REQ-024.20: cross-calendar ACLs)
#
# This module provides a basic Stalwart mail server configuration.
# On first boot, Stalwart generates a random admin password in the logs.
#
# ## Setting Admin Password with Agenix
#
# To use a managed admin password instead, extend this config in your host:
#
# ```nix
# # 1. Add to secrets.nix:
# "secrets/stalwart-admin-password.age".publicKeys = adminKeys ++ [ systems.yourhost ];
#
# # 2. Create the secret with a SHA-512 hashed password (NOT plaintext).
# #    fallback-admin.secret requires a $6$ hash format.
# #    Generate the hash: mkpasswd -m sha-512 "your-password"
# #    Then store it:     echo -n '$6$...' | agenix -e secrets/stalwart-admin-password.age
#
# # 3. In your host configuration:
# age.secrets.stalwart-admin-password = {
#   file = ../../secrets/stalwart-admin-password.age;
#   owner = "root";
#   mode = "0400";
# };
#
# services.stalwart-mail = {
#   credentials = {
#     admin_password = config.age.secrets.stalwart-admin-password.path;
#   };
#   settings.authentication.fallback-admin = {
#     user = "admin";
#     secret = "%{file:/run/credentials/stalwart-mail.service/admin_password}%";
#   };
# };
# ```
#
# The credentials option uses systemd's LoadCredential to securely pass
# the secret to the service, accessible via the %{file:...}% macro.
#
# ## IMAP/SMTP Client Authentication
#
# When connecting with an IMAP/SMTP client (e.g. himalaya), the login
# username is the Stalwart account **name** (e.g. "ncrmro"), NOT the
# email address. The email is only used as the envelope/from address.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.os.mail;
  topDomain = config.keystone.domain;

  # Agents that want mail provisioning on this host (where Stalwart runs).
  # This is NOT filtered by agent.host — provisioning runs on the mail server,
  # which is typically a different host from the agent's designated host.
  #
  # CRITICAL (agenix): agent-{name}-mail-password must list BOTH the agent's
  # host (for himalaya client) AND this server's host key (for Stalwart
  # provisioning) in its publicKeys recipients. Otherwise agenix will fail
  # to decrypt at activation time on this host.
  provisionAgents = filterAttrs (_: a: a.mail.provision) config.keystone.os.agents;
  hasProvisionAgents = provisionAgents != { };

  # Human usernames for CalDAV sharing — agents grant these users read/write
  # access to their calendars so the human can schedule tasks via CalDAV.
  humanUsers = attrNames config.keystone.os.users;
in
{
  options.keystone.os.mail = {
    allowedIps = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "IP ranges to whitelist from fail2ban blocking (e.g., Tailscale ranges)";
      example = [
        "100.64.0.0/10"
        "fd7a:115c:a1e0::/48"
      ];
    };
  };

  # Auto-enable when keystone.services.mail.host matches this machine's hostname.
  # No manual `enable = true` needed — just set keystone.services.mail.host once.
  config =
    mkIf
      (
        config.keystone.services.mail.host != null
        && config.keystone.services.mail.host == config.networking.hostName
      )
      {
        services.stalwart-mail = {
          enable = true;
          package = pkgs.stalwart-mail;
          openFirewall = true;

          settings = {
            # Server configuration
            server = {
              hostname = config.networking.hostName;

              # Allow IPs to bypass fail2ban blocking
              # Using table syntax instead of set notation (NixOS can't generate { "ip" } sets)
              "allowed-ip" = lib.listToAttrs (map (ip: lib.nameValuePair ip "") cfg.allowedIps);
              tls = {
                enable = true;
                implicit = true;
              };
              listener = {
                # SMTP for mail delivery (port 25)
                smtp = {
                  protocol = "smtp";
                  bind = [ "[::]:25" ];
                };
                # SMTP Submission with TLS (port 465)
                submissions = {
                  protocol = "smtp";
                  bind = [ "[::]:465" ];
                  tls.implicit = true;
                };
                # SMTP Submission (port 587)
                submission = {
                  protocol = "smtp";
                  bind = [ "[::]:587" ];
                };
                # IMAPS (port 993)
                imaps = {
                  protocol = "imap";
                  bind = [ "[::]:993" ];
                  tls.implicit = true;
                };
                # JMAP/Management interface (localhost only)
                # Using 8082 to avoid conflict with common ingress port 8080
                # TODO: Can revert to 8080 after removing k8s ingress-nginx
                jmap = {
                  protocol = "http";
                  bind = [ "127.0.0.1:8082" ];
                };
              };
            };

            # Storage configuration - use RocksDB for persistence
            store = {
              db = {
                type = "rocksdb";
                path = "/var/lib/stalwart-mail/data";
              };
              blob = {
                type = "rocksdb";
                path = "/var/lib/stalwart-mail/blob";
              };
            };
            storage = {
              data = "db";
              blob = "blob";
              fts = "db";
              lookup = "db";
            };

            # Directory for user authentication
            directory = {
              internal = {
                type = "internal";
                store = "db";
              };
            };

            # Session configuration
            # Note: Directory references need single quotes for Stalwart TOML
            session = {
              rcpt = {
                directory = "'internal'";
              };
              auth = {
                directory = "'internal'";
                mechanisms = "[plain, login]";
              };
            };

            # Queue configuration - route all mail locally
            # (next-hop deprecated in v0.13.0, replaced by queue.strategy.route)
            queue.strategy.route = "'local'";

            # Resolver configuration
            resolver = {
              type = "system";
            };

            # Tracing/logging
            tracer = {
              stdout = {
                type = "stdout";
                level = "info";
                ansi = false;
                enable = true;
              };
            };

            # Web admin interface is configured automatically by nixpkgs
            # (sets webadmin.path to /var/cache/stalwart-mail)

            # CalDAV/CardDAV sharing between principals
            # allow-directory-query: lets users discover other principals for sharing
            # assisted-discovery: makes PROPFIND Depth:1 return shared collections
            sharing = {
              allow-directory-query = true;
              max-shares-per-item = 50;
            };
            dav.collection.assisted-discovery = true;

            # Spam filter - disabled to avoid missing file error
            # TODO: Spam filter is currently disabled because the default `spamfilter.toml`
            # resource was not found in the Stalwart Mail package. To re-enable, either:
            # 1. Find or create a `spamfilter.toml` file and point the `resource`
            #    option to its path.
            # 2. Configure spam filtering directly within the `spam-filter` section.
            spam-filter = {
              resource = "";
            };
          };
        };

        # Firewall configuration for mail ports
        networking.firewall = {
          allowedTCPPorts = [
            25 # SMTP
            465 # SMTPS (Submission over TLS)
            587 # Submission
            993 # IMAPS
          ];
        };

        # Auto-provision Stalwart mail accounts for agents with mail.provision = true
        assertions = mkIf hasProvisionAgents (
          [
            {
              assertion = config.age.secrets ? "stalwart-admin-password";
              message = "Agent mail provisioning requires agenix secret 'stalwart-admin-password' for Stalwart admin API access.";
            }
          ]
          ++ (mapAttrsToList (name: _: {
            assertion = config.age.secrets ? "agent-${name}-mail-password";
            message = ''
              Agent '${name}' has mail.provision = true but agenix secret "agent-${name}-mail-password" is not declared.
              This secret must contain the plaintext password for the agent's Stalwart account.
            '';
          }) provisionAgents)
        );

        # Idempotent: GET /api/principal/{name} → 200 means account exists, skip.
        # NOTE: The systemd unit is "stalwart.service" (not "stalwart-mail.service").
        # The admin password secret may be a SHA-512 hash ($6$...) — Stalwart
        # accepts hashed passwords in HTTP basic auth, so provisioning still works.
        systemd.services = mkIf hasProvisionAgents (
          mapAttrs' (
            name: agentCfg:
            let
              username = "agent-${name}";
              mailAddr =
                if agentCfg.mail.address != null then agentCfg.mail.address else "${username}@${topDomain}";
              adminPasswordPath = "/run/agenix/stalwart-admin-password";
              agentPasswordPath = "/run/agenix/${username}-mail-password";
            in
            nameValuePair "provision-agent-mail-${name}" {
              description = "Provision Stalwart mail account for ${username}";
              after = [ "stalwart.service" ];
              requires = [ "stalwart.service" ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };

              path = [
                pkgs.curl
                pkgs.jq
              ];

              script =
                let
                  # Build ACL XML granting each human user read+write on the agent's calendar
                  aclAces = concatMapStringsSep "\n" (user: ''
                    <D:ace>
                      <D:principal><D:href>/dav/pal/${user}/</D:href></D:principal>
                      <D:grant>
                        <D:privilege><D:read/></D:privilege>
                        <D:privilege><D:write/></D:privilege>
                      </D:grant>
                    </D:ace>
                  '') humanUsers;
                in
                ''
                  set -euo pipefail

                  ADMIN_PASS=$(cat ${adminPasswordPath})
                  AGENT_PASS=$(tr -d '\n' < ${agentPasswordPath})
                  API="http://127.0.0.1:8082/api"

                  # Check if account already exists
                  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
                    -u "admin:$ADMIN_PASS" \
                    "$API/principal/${username}")

                  if [[ "$STATUS" != "200" ]]; then
                    echo "${username}: Creating Stalwart mail account..."

                    # Create the account
                    curl -sf -u "admin:$ADMIN_PASS" \
                      "$API/principal" \
                      -H "Content-Type: application/json" \
                      -d "$(jq -n \
                        --arg name "${username}" \
                        --arg pass "$AGENT_PASS" \
                        --arg email "${mailAddr}" \
                        '{type: "individual", name: $name, secrets: [$pass], emails: [$email]}')"

                    echo "${username}: Stalwart mail account created successfully"
                  else
                    echo "${username}: Stalwart account already exists"
                  fi

                  # Always ensure role is set (idempotent) — needed for CalDAV/CardDAV permissions
                  curl -sf -u "admin:$ADMIN_PASS" \
                    "$API/principal/${username}" -X PATCH \
                    -H "Content-Type: application/json" \
                    -d '[{"action":"set","field":"roles","value":["user"]}]'

                  # Grant human users read/write access to the agent's default calendar.
                  # The ACL request must be authenticated as the calendar owner (agent).
                  # Stalwart auto-creates the default calendar on first CalDAV access.
                  echo "${username}: Setting CalDAV sharing ACLs..."

                  # First, trigger default calendar creation by accessing the agent's CalDAV home
                  curl -sf -u "${username}:$AGENT_PASS" \
                    "http://127.0.0.1:8082/dav/cal/${username}/" \
                    -X PROPFIND -H "Content-Type: application/xml" -H "Depth: 1" \
                    -d '<?xml version="1.0"?><propfind xmlns="DAV:"><prop><resourcetype/></prop></propfind>' \
                    -o /dev/null || true

                  # Set ACL on the agent's default calendar
                  ACL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
                    -u "${username}:$AGENT_PASS" \
                    "http://127.0.0.1:8082/dav/cal/${username}/default/" \
                    -X ACL -H "Content-Type: application/xml" \
                    -d '<?xml version="1.0" encoding="utf-8"?>
                  <D:acl xmlns:D="DAV:">
                  ${aclAces}
                  </D:acl>')

                  if [[ "$ACL_STATUS" = "200" || "$ACL_STATUS" = "204" ]]; then
                    echo "${username}: CalDAV sharing ACLs set successfully"
                  else
                    echo "${username}: WARNING: CalDAV ACL request returned HTTP $ACL_STATUS" >&2
                  fi
                '';
            }
          ) provisionAgents
        );
      };
}
