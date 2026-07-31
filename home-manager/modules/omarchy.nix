{
  lib,
  config,
  pkgs,
  omarchy,
  ...
}:
with lib;
{
  options.keystone.home.omarchy = {
    enable = mkEnableOption "Enable omarchy configuration and tools" // {
      default = true;
    };
  };

  config = mkIf config.keystone.home.omarchy.enable {
    # Copy omarchy bin directory to XDG config directory
    home.file."${config.xdg.configHome}/omarchy/bin" = {
      source = "${omarchy}/bin";
      recursive = true;
    };

    # Add omarchy bin to session path
    home.sessionPath = [
      "${config.xdg.configHome}/omarchy/bin"
    ];
  };
}
