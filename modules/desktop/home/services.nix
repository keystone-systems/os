{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop;
in
{
  config = mkIf cfg.enable {
    # Walker update now launches `ks update --approve` as a graphical session
    # app via `uwsm app -- systemd-cat ...`, so there is no dedicated
    # ks-update.service / notifier template to install here anymore.
  };
}
