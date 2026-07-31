{
  pkgs,
  self,
  home-manager,
  ...
}:
let
  desktopConfig =
    (home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        self.homeModules.terminal
        self.homeModules.desktop
        {
          home.username = "testuser";
          home.homeDirectory = "/home/testuser";
          home.stateVersion = "25.05";
          programs.ssh.enableDefaultConfig = false;
          keystone.terminal = {
            enable = true;
            git = {
              userName = "Test User";
              userEmail = "test@test";
            };
          };
          keystone.desktop.enable = true;
        }
      ];
    }).config;

  files = builtins.attrNames desktopConfig.home.file;
  migratedPrefixes = [
    ".config/hypr/"
    ".config/waybar/"
    ".config/walker/"
    ".config/wofi/"
    ".config/satty/"
    ".config/helix/"
    ".config/ghostty/"
    ".config/clipse/"
    ".config/btop/"
    ".config/bat/"
    ".config/zellij/"
  ];
  ownsMigratedFile =
    file: builtins.any (prefix: builtins.match ".*${prefix}.*" file != null) migratedPrefixes;
  collisions = builtins.filter ownsMigratedFile files;
in
assert collisions == [ ];
pkgs.runCommand "desktop-provisions-without-owning-dotfiles" { } ''
  test -x "${pkgs.hypridle}/bin/hypridle"
  test -x "${pkgs.hyprlock}/bin/hyprlock"
  test -x "${pkgs.waybar}/bin/waybar"
  touch "$out"
''
