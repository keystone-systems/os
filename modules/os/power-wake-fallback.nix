{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.keystone.os;
  active = cfg.enable && cfg.hostKind == "laptop" && cfg.power.suspendThenHibernate.enable;
  checker = pkgs.writeShellApplication {
    name = "keystone-closed-lid-wake-hibernate";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
    ];
    text = builtins.readFile ./scripts/closed-lid-wake-hibernate.sh;
  };
in
{
  config = lib.mkIf active {
    # systemctl's sleep verbs return after enqueueing, so user-space code
    # cannot treat their return as a resume signal. OnSuccess runs only after
    # systemd-sleep has returned from the complete suspend-then-hibernate
    # operation, including any early wake.
    systemd.services.systemd-suspend-then-hibernate.unitConfig.OnSuccess =
      "keystone-closed-lid-wake-hibernate.service";

    systemd.services.keystone-closed-lid-wake-hibernate = {
      description = "Hibernate after a closed-lid early wake";
      after = [ "systemd-suspend-then-hibernate.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${checker}/bin/keystone-closed-lid-wake-hibernate";
      };
    };
  };
}
