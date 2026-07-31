{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop;
in
{
  config = mkIf cfg.enable {
    # Enable mako service - config symlink is created in theming activation script
    # to ensure proper symlink ordering (theme symlinks must exist first)
    services.mako.enable = mkDefault true;
  };
}
