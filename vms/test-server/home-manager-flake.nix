{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, home-manager, ... }:
    {
      homeConfigurations."testuser" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        modules = [
          ./home-manager/modules/terminal-dev-environment
          {
            home.username = "testuser";
            home.homeDirectory = "/home/testuser";
            home.stateVersion = "25.05";

            programs.terminal-dev-environment.enable = true;

            programs.git = {
              userName = "Test User";
              userEmail = "testuser@keystone-test-vm";
            };

            programs.home-manager.enable = true;
          }
        ];
      };
    };
}
