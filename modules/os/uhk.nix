{
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.keystone.hardware.uhk;
in
{
  options.keystone.hardware.uhk = {
    enable = mkEnableOption "Ultimate Hacking Keyboard support";
  };

  config = mkIf cfg.enable {
    hardware.keyboard.uhk.enable = true;
  };
}
