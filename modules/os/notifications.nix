# Keystone OS Notification System
#
# Terminal notification system for pending manual actions.
# Notifications appear at interactive shell login when their associated
# marker file is absent from disk.
#
# Other modules register notifications by appending to keystone.os.notifications.items:
#
#   config.keystone.os.notifications.items = [{
#     id = "my-action";
#     title = "Action Required";
#     body = "Please run: my-command";
#     markerFile = "/var/lib/keystone/my-action-complete";
#   }];
#
# The marker file is written by a systemd service (running as root) when the
# required action is complete — regular users cannot write to /var/lib/keystone.
#
# Desktop integration: the same marker files under /var/lib/keystone/ can be
# polled by desktop notification daemons for GUI alerts.
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.os.notifications;
in
{
  options.keystone.os.notifications = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Keystone terminal notification system for pending manual actions";
    };

    items = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            id = mkOption {
              type = types.str;
              description = "Unique notification identifier (used for the Nix store path)";
              example = "tpm-enrollment";
            };

            title = mkOption {
              type = types.str;
              description = "Short human-readable notification title";
              example = "TPM Enrollment Required";
            };

            body = mkOption {
              type = types.str;
              description = "Full notification text displayed in the terminal. Use plain text or ASCII art.";
            };

            markerFile = mkOption {
              type = types.addCheck types.str (p: lib.hasPrefix "/" p);
              description = "Absolute path to a marker file. When this file exists, the notification is suppressed.";
              example = "/var/lib/keystone/tpm-enrollment-complete";
            };
          };
        }
      );
      default = [ ];
      description = "Notifications shown at interactive shell login when their marker file is absent.";
    };
  };

  config = mkIf cfg.enable {
    # Display each pending notification at interactive shell login.
    # Each notification's body is stored as a separate file in the Nix store so
    # that multi-line text and special characters are handled correctly.
    environment.interactiveShellInit = concatMapStringsSep "\n" (
      item:
      let
        bodyFile = pkgs.writeText "keystone-notification-${item.id}" item.body;
      in
      ''
        # Keystone notification: ${item.id}
        if [[ ! -f ${lib.escapeShellArg item.markerFile} ]]; then
          cat ${bodyFile}
        fi
      ''
    ) cfg.items;
  };
}
