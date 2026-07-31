# Keystone Terminal Tasks (cfait)
#
# This module provides cfait (CalDAV task/TODO manager TUI) configuration.
# When enabled with either a host or url configured, it generates
# cfait/config.toml that connects to a CalDAV endpoint.
#
# Credentials default from the mail module — if mail is already configured,
# only `tasks.enable = true` is needed for Stalwart.
#
# SECURITY: cfait does not support password commands — only plaintext passwords.
# A wrapper script resolves the password command at launch time and writes a
# temporary config, avoiding permanent plaintext password storage on disk.
#
# Implements REQ-022 (cfait CalDAV Task Manager)
# See docs/specs/REQ-022-cfait-tasks.md
#
# ## Stalwart (self-hosted) Example
#
# ```nix
# keystone.terminal.tasks = {
#   enable = true;
#   # All other options auto-default from keystone.terminal.mail
# };
# ```
#
# ## Explicit Configuration
#
# ```nix
# keystone.terminal.tasks = {
#   enable = true;
#   host = "caldav.example.com";
#   login = "me";
#   passwordCommand = "rbw get caldav-password";
# };
# ```
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.tasks;
  mailCfg = config.keystone.terminal.mail;

  mailLegacyConfigured =
    mailCfg.accountName != ""
    || mailCfg.email != ""
    || mailCfg.displayName != ""
    || mailCfg.login != ""
    || mailCfg.passwordCommand != ""
    || mailCfg.host != "";

  mailLegacyName = if mailCfg.accountName != "" then mailCfg.accountName else "default";

  mailLegacyAccount = {
    inherit (mailCfg)
      email
      displayName
      login
      passwordCommand
      host
      ;
  };

  declaredMailAccounts =
    mailCfg.accounts
    // optionalAttrs (mailLegacyConfigured && !(builtins.hasAttr mailLegacyName mailCfg.accounts)) {
      "${mailLegacyName}" = mailLegacyAccount;
    };

  sortedMailAccountNames = sort builtins.lessThan (attrNames declaredMailAccounts);

  defaultMailAccountName =
    if
      mailCfg.defaultAccount != null && builtins.hasAttr mailCfg.defaultAccount declaredMailAccounts
    then
      mailCfg.defaultAccount
    else if builtins.hasAttr mailLegacyName declaredMailAccounts then
      mailLegacyName
    else if sortedMailAccountNames != [ ] then
      head sortedMailAccountNames
    else
      null;

  defaultMailAccount =
    if defaultMailAccountName != null then declaredMailAccounts.${defaultMailAccountName} else null;

  # Use explicit url if set; otherwise build Stalwart's default path.
  # Stalwart's /.well-known/caldav redirects to /dav/cal, but PROPFIND
  # to the root URL gets a 400 from nginx — use direct path instead.
  calDavUrl = if cfg.url != "" then cfg.url else "https://${cfg.host}/dav/cal";

  # Wrapper script that resolves the password command at launch time
  # and writes a temporary config. This avoids storing plaintext passwords
  # on disk permanently — cfait only supports plaintext password in config.
  cfait-wrapped = pkgs.writeShellScriptBin "cfait" ''
        set -euo pipefail

        CFAIT_CONFIG_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/cfait"
        CFAIT_CONFIG="$CFAIT_CONFIG_DIR/config.toml"

        mkdir -p "$CFAIT_CONFIG_DIR"

        # Resolve password via command
        CFAIT_PASSWORD="$(${cfg.passwordCommand})"

        # Write config with resolved password (mode 0600 for security)
        install -m 0600 /dev/null "$CFAIT_CONFIG"
        cat > "$CFAIT_CONFIG" <<TOML
    url = "${calDavUrl}"
    username = "${cfg.login}"
    password = "$CFAIT_PASSWORD"
    TOML

        exec ${pkgs.keystone.cfait}/bin/cfait "$@"
  '';
in
{
  options.keystone.terminal.tasks = {
    enable = mkOption {
      type = types.bool;
      default = mailCfg.enable;
      description = "Enable CalDAV task management TUI (cfait). Auto-enables when mail is configured.";
    };

    host = mkOption {
      type = types.str;
      default = if defaultMailAccount != null then defaultMailAccount.host else "";
      description = "CalDAV server hostname (defaults to mail host)";
    };

    login = mkOption {
      type = types.str;
      default = if defaultMailAccount != null then defaultMailAccount.login else "";
      description = "CalDAV username (defaults to mail login)";
    };

    passwordCommand = mkOption {
      type = types.str;
      default = if defaultMailAccount != null then defaultMailAccount.passwordCommand else "";
      description = "Command to retrieve the password (defaults to mail passwordCommand)";
    };

    url = mkOption {
      type = types.str;
      default = "";
      description = ''
        CalDAV endpoint URL. When empty, defaults to https://{host}/dav/cal
        (Stalwart). Set explicitly for external providers:
          iCloud: https://caldav.icloud.com
      '';
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    home.packages = [
      cfait-wrapped
    ];
  };
}
