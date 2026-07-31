# Keystone Terminal — Forgejo CLI
#
# Installs `fj` (forgejo-cli) and `tea` (Gitea/Forgejo CLI) when enabled.
# forgejo-cli handles admin and auth operations; tea covers daily workflow
# (PRs, issues, releases) that forgejo-cli doesn't support.
#
# When domain + username are set (bridged from keystone.services.git in
# users.nix and agents.nix), generates:
#   - ~/.config/tea/config.yml — tea login with SSH agent auth (default login)
#   - ~/.local/share/forgejo-cli/keys.json — SSH:port→HTTPS alias so fj
#     resolves the correct API URL from SSH git remotes
#
# IMPORTANT: tea's `ssh_agent: true` only authenticates git transport
# (clone/push/pull), NOT Forgejo REST API calls. All API operations (PRs,
# issues, releases) require a real token in the `token` field. For agents,
# tokens are provisioned automatically by git-server.nix. For humans, add
# a token manually after first deploy — it will be preserved across rebuilds.
#
# Both config files use activation scripts (not home.file) so that
# manually-added or provisioned tokens survive nixos-rebuild.
#
# Auto-enabled via keystone.services.git.host in users.nix and agents.nix
# home-manager bridges.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal;
  forgejoCfg = cfg.git.forgejo;
  hasDomainAndUser = forgejoCfg.domain != null && forgejoCfg.username != null;
  sshPortStr = toString forgejoCfg.sshPort;
in
{
  options.keystone.terminal.git.forgejo = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Install forgejo-cli (fj) for Forgejo server interaction";
    };

    domain = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "git.ncrmro.com";
      description = "FQDN of the Forgejo instance. When set, generates tea and fj config.";
    };

    sshPort = mkOption {
      type = types.port;
      default = 2222;
      description = "SSH port for git operations on the Forgejo instance.";
    };

    username = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "ncrmro";
      description = "Forgejo username for tea login.";
    };
  };

  config = mkIf (cfg.enable && forgejoCfg.enable) (mkMerge [
    {
      home.packages = [
        pkgs.forgejo-cli
        # fj-ex extends forgejo-cli with Actions-focused operations such as
        # queued jobs, recent runs, and job log streaming.
        pkgs.keystone.forgejo-cli-ex
        # tea provides repo/issue/PR operations that forgejo-cli lacks (e.g. tea pr create,
        # tea issue list). forgejo-cli focuses on admin/auth; tea covers the daily workflow.
        pkgs.tea
        pkgs.keystone.fetch-forgejo-sources
        # forgejo-project: project board management via web routes (no REST API exists).
        # Uses session cookie auth; login once with `forgejo-project login --password-cmd ...`
        pkgs.keystone.forgejo-project
      ];
    }

    (mkIf hasDomainAndUser {
      # tea config — SSH agent auth, marked as default login so tea doesn't
      # prompt "falling back to login 'forgejo'?" on every invocation.
      # Uses activation script (not home.file) so manually-added or
      # provisioned API tokens survive nixos-rebuild.
      home.activation.teaConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        TEA_DIR="$HOME/.config/tea"
        TEA_FILE="$TEA_DIR/config.yml"
        mkdir -p "$TEA_DIR"
        if [ ! -f "$TEA_FILE" ]; then
          cat > "$TEA_FILE" << 'SEED'
        ${builtins.toJSON {
          logins = [
            {
              name = "forgejo";
              url = "https://${forgejoCfg.domain}";
              token = "";
              default = true;
              ssh_host = forgejoCfg.domain;
              ssh_key = "~/.ssh/id_ed25519";
              ssh_agent = true;
              version_check = false;
              user = forgejoCfg.username;
            }
          ];
          preferences = {
            editor = false;
            flag_defaults = {
              remote = "";
            };
          };
        }}
        SEED
        else
          # Update url/user/ssh fields but preserve existing token value
          ${pkgs.yq-go}/bin/yq -i '
            .logins[0].url = "https://${forgejoCfg.domain}" |
            .logins[0].user = "${forgejoCfg.username}" |
            .logins[0].ssh_host = "${forgejoCfg.domain}" |
            .logins[0].name = "forgejo" |
            .logins[0].default = true |
            .logins[0].ssh_agent = true |
            .logins[0].version_check = false
          ' "$TEA_FILE"
        fi
      '';

      # fj (forgejo-cli) config — alias SSH host:port to HTTPS host so fj
      # resolves the correct API URL from git remotes like
      # ssh://forgejo@git.ncrmro.com:2222/owner/repo.git
      # Without this alias, fj tries https://git.ncrmro.com:2222 (wrong port).
      #
      # Uses activation script (not home.file) because fj needs to write tokens
      # to this file via `fj auth add-key`. Seeds the alias on first run;
      # merges it into existing config on subsequent activations to preserve
      # user-added tokens.
      home.activation.forgejoCliConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        FJ_DIR="$HOME/.local/share/forgejo-cli"
        FJ_FILE="$FJ_DIR/keys.json"
        mkdir -p "$FJ_DIR"
        if [ ! -f "$FJ_FILE" ]; then
          cat > "$FJ_FILE" << 'SEED'
        ${builtins.toJSON {
          hosts = { };
          aliases = {
            "${forgejoCfg.domain}:${sshPortStr}" = forgejoCfg.domain;
          };
          default_ssh = [ ];
        }}
        SEED
        else
          # Merge alias into existing config, preserving tokens in hosts
          ${pkgs.jq}/bin/jq --arg key "${forgejoCfg.domain}:${sshPortStr}" \
            --arg val "${forgejoCfg.domain}" \
            '.aliases[$key] = $val' "$FJ_FILE" > "$FJ_FILE.tmp" \
            && mv "$FJ_FILE.tmp" "$FJ_FILE"
        fi
      '';
    })
  ]);
}
