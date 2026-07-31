# Keystone OS iPhone Tether Module
#
# Enables iOS USB tethering/hotspot support via libimobiledevice and usbmuxd.
# This allows using an iPhone's cellular connection over USB.
#
{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  osCfg = config.keystone.os;
  cfg = osCfg.iphoneTether;
in
{
  config = mkIf (osCfg.enable && cfg.enable) {
    # iPhone USB tethering support
    environment.systemPackages = [
      pkgs.libimobiledevice
    ];

    # USB multiplexer daemon needed for iOS device communication
    services.usbmuxd.enable = true;
  };
}
