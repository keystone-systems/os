# Keystone Terminal Timer (Comodoro)
#
# This module provides comodoro (Pimalaya Pomodoro timer CLI) configuration.
# Comodoro is a centralized timer server controllable by multiple clients
# simultaneously, with customizable work/rest cycles and notification hooks.
#
# ## Example Usage
#
# ```nix
# keystone.terminal.timer = {
#   enable = true;
#   # Uses default Pomodoro cycles (25/5/25/5/25/30)
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
  cfg = config.keystone.terminal.timer;
in
{
  options.keystone.terminal.timer = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable timer CLI tools (comodoro)";
    };
  };

  config = mkIf (config.keystone.terminal.enable && cfg.enable) {
    home.packages = [
      pkgs.keystone.comodoro
    ];

    xdg.configFile."comodoro/config.toml" = {
      text = ''
        [accounts.default]
        default = true

        unix-socket.path = "/tmp/comodoro.sock"
        unix-socket.default = true

        cycles = [
          { name = "Work", duration = 1500 },
          { name = "Rest", duration = 300 },
          { name = "Work", duration = 1500 },
          { name = "Rest", duration = 300 },
          { name = "Work", duration = 1500 },
          { name = "Long rest", duration = 1800 },
        ]

        precision = "minute"

        hooks.on-work-begin.notify.summary = "Comodoro"
        hooks.on-work-begin.notify.body = "Work started!"
        hooks.on-rest-begin.notify.summary = "Comodoro"
        hooks.on-rest-begin.notify.body = "Take a break!"
        hooks.on-long-rest-begin.notify.summary = "Comodoro"
        hooks.on-long-rest-begin.notify.body = "Long break time!"
      '';
    };
  };
}
