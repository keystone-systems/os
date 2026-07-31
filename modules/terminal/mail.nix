# Keystone Terminal Mail (Himalaya)
#
# This module provides himalaya email client configuration.
# It supports both the legacy single-account options and the newer declarative
# multi-account model used by the desktop account menus.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.mail;

  accountType = types.submodule {
    options = {
      email = mkOption {
        type = types.str;
        default = "";
        description = "Email address";
      };

      displayName = mkOption {
        type = types.str;
        default = "";
        description = "Display name for sent emails";
      };

      login = mkOption {
        type = types.str;
        default = "";
        description = "IMAP or SMTP login name";
      };

      passwordCommand = mkOption {
        type = types.str;
        default = "";
        description = "Command to retrieve the password";
      };

      host = mkOption {
        type = types.str;
        default = "";
        description = "Mail server hostname";
      };

      imap.port = mkOption {
        type = types.int;
        default = 993;
        description = "IMAP port";
      };

      smtp = {
        host = mkOption {
          type = types.str;
          default = "";
          description = "SMTP hostname (defaults to IMAP host when empty)";
        };

        port = mkOption {
          type = types.int;
          default = 465;
          description = "SMTP port";
        };

        encryption = mkOption {
          type = types.enum [
            "tls"
            "start-tls"
            "none"
          ];
          default = "tls";
          description = "SMTP encryption type";
        };
      };

      folders = {
        sent = mkOption {
          type = types.str;
          default = "Sent Items";
          description = "Sent folder name";
        };

        drafts = mkOption {
          type = types.str;
          default = "Drafts";
          description = "Drafts folder name";
        };

        trash = mkOption {
          type = types.str;
          default = "Deleted Items";
          description = "Trash folder name";
        };
      };
    };
  };

  legacyAccountConfigured =
    cfg.accountName != ""
    || cfg.email != ""
    || cfg.displayName != ""
    || cfg.login != ""
    || cfg.passwordCommand != ""
    || cfg.host != "";

  legacyAccountName = if cfg.accountName != "" then cfg.accountName else "default";

  legacyAccount = {
    inherit (cfg)
      email
      displayName
      login
      passwordCommand
      host
      ;
    imap = {
      inherit (cfg.imap) port;
    };
    smtp = {
      inherit (cfg.smtp) host port encryption;
    };
    folders = {
      inherit (cfg.folders) sent drafts trash;
    };
  };

  declaredAccounts =
    cfg.accounts
    // optionalAttrs (legacyAccountConfigured && !(builtins.hasAttr legacyAccountName cfg.accounts)) {
      "${legacyAccountName}" = legacyAccount;
    };

  activeAccounts = filterAttrs (_: account: account.host != "") declaredAccounts;

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
      host = toLower account.host;
    in
    if hasInfix "gmail.com" host then
      "gmail"
    else if hasInfix "icloud.com" host || hasInfix "me.com" host then
      "icloud"
    else if hasInfix "ncrmro.com" host then
      "stalwart"
    else
      "custom";

  metadataJson = builtins.toJSON (
    map (
      name:
      let
        account = activeAccounts.${name};
      in
      {
        inherit name;
        inherit (account)
          email
          displayName
          host
          login
          ;
        provider = providerForAccount account;
        default = name == defaultAccountName;
        services = {
          mail = true;
          calendar = false;
        };
      }
    ) sortedAccountNames
  );

  himalayaConfig = concatStringsSep "\n\n" (
    map (
      name:
      let
        account = activeAccounts.${name};
        smtpHost = if account.smtp.host != "" then account.smtp.host else account.host;
      in
      ''
        [accounts.${name}]
        email = "${account.email}"
        display-name = "${account.displayName}"
        default = ${if name == defaultAccountName then "true" else "false"}

        backend.type = "imap"
        backend.host = "${account.host}"
        backend.port = ${toString account.imap.port}
        backend.encryption.type = "tls"
        backend.login = "${account.login}"
        backend.auth.type = "password"
        backend.auth.command = "${account.passwordCommand}"

        message.send.backend.type = "smtp"
        message.send.backend.host = "${smtpHost}"
        message.send.backend.port = ${toString account.smtp.port}
        message.send.backend.encryption.type = "${account.smtp.encryption}"
        message.send.backend.login = "${account.login}"
        message.send.backend.auth.type = "password"
        message.send.backend.auth.command = "${account.passwordCommand}"

        folder.aliases.sent = "${account.folders.sent}"
        folder.aliases.drafts = "${account.folders.drafts}"
        folder.aliases.trash = "${account.folders.trash}"
      ''
    ) sortedAccountNames
  );
in
{
  options.keystone.terminal.mail = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable mail CLI tools (himalaya)";
    };

    accounts = mkOption {
      type = types.attrsOf accountType;
      default = { };
      description = "Declarative mail accounts keyed by account name.";
    };

    defaultAccount = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Default mail account name when multiple accounts are configured.";
    };

    accountName = mkOption {
      type = types.str;
      default = "";
      description = "Legacy single-account name. Mapped into accounts for compatibility.";
    };

    email = mkOption {
      type = types.str;
      default = "";
      description = "Legacy single-account email address";
    };

    displayName = mkOption {
      type = types.str;
      default = "";
      description = "Legacy single-account display name";
    };

    login = mkOption {
      type = types.str;
      default = "";
      description = "Legacy single-account login";
    };

    passwordCommand = mkOption {
      type = types.str;
      default = "";
      description = "Legacy single-account password retrieval command";
    };

    host = mkOption {
      type = types.str;
      default = "";
      description = "Legacy single-account IMAP hostname";
    };

    imap.port = mkOption {
      type = types.int;
      default = 993;
      description = "Legacy single-account IMAP port";
    };

    smtp = {
      host = mkOption {
        type = types.str;
        default = "";
        description = "Legacy single-account SMTP hostname";
      };

      port = mkOption {
        type = types.int;
        default = 465;
        description = "Legacy single-account SMTP port";
      };

      encryption = mkOption {
        type = types.enum [
          "tls"
          "start-tls"
          "none"
        ];
        default = "tls";
        description = "Legacy single-account SMTP encryption";
      };
    };

    folders = {
      sent = mkOption {
        type = types.str;
        default = "Sent Items";
        description = "Legacy single-account sent folder";
      };

      drafts = mkOption {
        type = types.str;
        default = "Drafts";
        description = "Legacy single-account drafts folder";
      };

      trash = mkOption {
        type = types.str;
        default = "Deleted Items";
        description = "Legacy single-account trash folder";
      };
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    assertions = optional (cfg.defaultAccount != null) {
      assertion = builtins.hasAttr cfg.defaultAccount activeAccounts;
      message = "keystone.terminal.mail.defaultAccount must reference a configured active mail account";
    };

    home.packages = [
      pkgs.keystone.himalaya
      pkgs.keystone.fetch-email-source
    ];

    xdg.configFile."himalaya/config.toml" = mkIf (activeAccounts != { }) {
      text = himalayaConfig;
    };

    xdg.configFile."keystone/mail-accounts.json" = mkIf (activeAccounts != { }) {
      text = metadataJson;
    };
  };
}
