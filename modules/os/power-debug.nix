{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.keystone.os.power.debug;
  recorder = pkgs.writeShellApplication {
    name = "keystone-power-event-debug";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnugrep
      systemd
    ];
    text = builtins.readFile ./scripts/power-event-debug.sh;
  };
in
{
  options.keystone.os.power.debug.enable = lib.mkEnableOption ''
    persistent suspend and resume diagnostics
  '';

  config = lib.mkIf (config.keystone.os.enable && cfg.enable) {
    systemd.tmpfiles.rules = [
      "d /var/lib/keystone/power-events 0700 root root - -"
    ];

    environment.etc."systemd/system-sleep/keystone-power-event-debug" = {
      source = "${recorder}/bin/keystone-power-event-debug";
      mode = "0755";
    };

    systemd.services.keystone-power-debug-messages = {
      description = "Enable kernel power-management debug messages";
      wantedBy = [ "multi-user.target" ];
      before = [ "sleep.target" ];
      unitConfig.ConditionPathExists = "/sys/power/pm_debug_messages";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        printf '1\n' > /sys/power/pm_debug_messages
      '';
    };
  };
}
