{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal;
in
{
  config = mkIf cfg.enable {
    home.packages = [ pkgs.keystone.zide ];

    home.sessionVariables = {
      ZIDE_DEFAULT_LAYOUT = mkDefault "default";
      ZIDE_FILE_PICKER = mkDefault "yazi";
    };
  };
}
