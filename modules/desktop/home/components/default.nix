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
  imports = [
    ./btop.nix
    ./clipboard.nix
    ./ghostty.nix
    ./launcher.nix
    ./mako.nix
    ./screenshot.nix
    ./ssh-agent.nix
    ./swayosd.nix
    ./waybar.nix
  ];

  # Components don't need their own options - they're enabled by keystone.desktop.enable
}
