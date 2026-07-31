# Keystone Terminal Calendar (Calendula)
#
# This module provides calendula configuration for both the legacy single
# account style and the newer declarative multi-account model used by the
# desktop account menus.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.calendar;
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

  accountType = types.submodule {
    options = {
      host = mkOption {
        type = types.str;
        default = "";
        description = "CalDAV server hostname";
      };

      login = mkOption {
        type = types.str;
        default = "";
        description = "CalDAV username";
      };

      passwordCommand = mkOption {
        type = types.str;
        default = "";
        description = "Command to retrieve the password";
      };

      url = mkOption {
        type = types.str;
        default = "";
        description = "CalDAV home URI";
      };
    };
  };

  legacyAccountConfigured =
    cfg.accountName != ""
    || cfg.host != ""
    || cfg.url != ""
    || cfg.login != ""
    || cfg.passwordCommand != "";

  legacyAccountName =
    if cfg.accountName != "" then
      cfg.accountName
    else if defaultMailAccountName != null then
      defaultMailAccountName
    else
      "default";

  legacyAccount = {
    host =
      if cfg.host != "" then
        cfg.host
      else if defaultMailAccount != null then
        defaultMailAccount.host
      else
        "";
    login =
      if cfg.login != "" then
        cfg.login
      else if defaultMailAccount != null then
        defaultMailAccount.login
      else
        "";
    passwordCommand =
      if cfg.passwordCommand != "" then
        cfg.passwordCommand
      else if defaultMailAccount != null then
        defaultMailAccount.passwordCommand
      else
        "";
    inherit (cfg) url;
  };

  declaredAccounts =
    cfg.accounts
    // optionalAttrs (legacyAccountConfigured && !(builtins.hasAttr legacyAccountName cfg.accounts)) {
      "${legacyAccountName}" = legacyAccount;
    };

  activeAccounts = filterAttrs (_: account: account.host != "" || account.url != "") declaredAccounts;

  sortedAccountNames = sort builtins.lessThan (attrNames activeAccounts);

  defaultAccountName =
    if cfg.defaultAccount != null && builtins.hasAttr cfg.defaultAccount activeAccounts then
      cfg.defaultAccount
    else if builtins.hasAttr legacyAccountName activeAccounts then
      legacyAccountName
    else if sortedAccountNames != [ ] then
      head sortedAccountNames
    else
      null;

  providerForAccount =
    account:
    let
      endpoint = toLower (if account.url != "" then account.url else account.host);
    in
    if hasInfix "gmail.com" endpoint || hasInfix "google.com" endpoint then
      "gmail"
    else if hasInfix "icloud.com" endpoint then
      "icloud"
    else if hasInfix "ncrmro.com" endpoint then
      "stalwart"
    else
      "custom";

  accountUri =
    account:
    if account.url != "" then account.url else "https://${account.host}/dav/cal/${account.login}";

  metadataJson = builtins.toJSON (
    map (
      name:
      let
        account = activeAccounts.${name};
      in
      {
        inherit name;
        inherit (account) host login url;
        provider = providerForAccount account;
        default = name == defaultAccountName;
        services = {
          calendar = true;
        };
      }
    ) sortedAccountNames
  );

  calendulaConfig = concatStringsSep "\n\n" (
    map (
      name:
      let
        account = activeAccounts.${name};
      in
      ''
        [accounts.${name}]
        default = ${if name == defaultAccountName then "true" else "false"}

        caldav.home-uri = "${accountUri account}"
        caldav.auth.basic.username = "${account.login}"
        caldav.auth.basic.password.command = ["sh", "-c", "${account.passwordCommand}"]
      ''
    ) sortedAccountNames
  );
in
{
  options.keystone.terminal.calendar = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable calendar CLI tools (calendula)";
    };

    accounts = mkOption {
      type = types.attrsOf accountType;
      default = { };
      description = "Declarative calendar accounts keyed by account name.";
    };

    defaultAccount = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Default calendar account name when multiple accounts are configured.";
    };

    accountName = mkOption {
      type = types.str;
      default = if defaultMailAccountName != null then defaultMailAccountName else "";
      description = "Legacy single-account name. Mapped into accounts for compatibility.";
    };

    host = mkOption {
      type = types.str;
      default = if defaultMailAccount != null then defaultMailAccount.host else "";
      description = "Legacy single-account CalDAV server hostname";
    };

    login = mkOption {
      type = types.str;
      default = if defaultMailAccount != null then defaultMailAccount.login else "";
      description = "Legacy single-account CalDAV username";
    };

    passwordCommand = mkOption {
      type = types.str;
      default = if defaultMailAccount != null then defaultMailAccount.passwordCommand else "";
      description = "Legacy single-account password retrieval command";
    };

    url = mkOption {
      type = types.str;
      default = "";
      description = ''
        Legacy single-account CalDAV home URI. When empty, defaults to
        https://{host}/dav/cal/{login} for Stalwart-style accounts.
      '';
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    assertions = optional (cfg.defaultAccount != null) {
      assertion = builtins.hasAttr cfg.defaultAccount activeAccounts;
      message = "keystone.terminal.calendar.defaultAccount must reference a configured active calendar account";
    };

    home.packages = [
      pkgs.keystone.calendula
    ];

    xdg.configFile."calendula/config.toml" = mkIf (activeAccounts != { }) {
      text = calendulaConfig;
    };

    xdg.configFile."keystone/calendar-accounts.json" = mkIf (activeAccounts != { }) {
      text = metadataJson;
    };
  };
}
