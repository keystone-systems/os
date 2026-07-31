{
  description = "Keystone test suite and development configurations";

  inputs = {
    # Reference the parent Keystone flake
    keystone.url = "path:..";
    # Follow inputs from parent to ensure consistency
    nixpkgs.follows = "keystone/nixpkgs";
    home-manager.follows = "keystone/home-manager";
    disko.follows = "keystone/disko";
    lanzaboote.follows = "keystone/lanzaboote";
    omarchy.follows = "keystone/omarchy";
    hyprland.follows = "keystone/hyprland";
    himalaya.follows = "keystone/himalaya";
    llm-agents.follows = "keystone/llm-agents";
    # These inputs are consumed directly by the tests flake. Keep explicit
    # definitions here because the path-based parent lock can lag nested inputs.
    nix-flatpak.url = "github:gmodena/nix-flatpak";
    walker = {
      url = "github:abenz1267/walker";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    kinda-nvim-hx = {
      url = "github:strash/kinda_nvim.hx";
      flake = false;
    };
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      keystone,
      nixpkgs,
      home-manager,
      disko,
      lanzaboote,
      omarchy,
      hyprland,
      nix-flatpak,
      walker,
      kinda-nvim-hx,
      himalaya,
      llm-agents,
      microvm,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ keystone.overlays.default ];
      };
      lib = pkgs.lib;
    in
    {
      # ============================================================
      # NixOS Configurations for Testing and Development
      # ============================================================

      nixosConfigurations = {
        # Test server configuration for nixos-anywhere deployment
        test-server = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            keystone.nixosModules.operating-system
            ../vms/test-server/configuration.nix
          ];
        };

        # Test Hyprland desktop configuration
        test-hyprland = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            keystone.nixosModules.operating-system
            keystone.nixosModules.desktop
            ../vms/test-hyprland/configuration.nix
          ];
        };

        # Fast VM testing configurations using nixos-rebuild build-vm
        # These skip disko/encryption/secure boot for rapid iteration

        # Terminal development environment testing
        build-vm-terminal = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit keystone; };
          modules = [
            home-manager.nixosModules.home-manager
            ../vms/build-vm-terminal/configuration.nix
          ];
        };

        # Hyprland desktop testing
        build-vm-desktop = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit keystone;
            keystoneInputs = {
              inherit
                nixpkgs
                hyprland
                nix-flatpak
                omarchy
                walker
                kinda-nvim-hx
                ;
            };
          };
          modules = [
            home-manager.nixosModules.home-manager
            nix-flatpak.nixosModules.nix-flatpak
            ../vms/build-vm-desktop/configuration.nix
          ];
        };

        # MicroVM testing configurations
        tpm-microvm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            microvm.nixosModules.microvm
            disko.nixosModules.disko
            keystone.nixosModules.operating-system # This enables keystone.os.* options
            ./microvm/tpm-test.nix
          ];
        };

      };

      # ============================================================
      # Home Manager Configurations for Testing
      # ============================================================

      homeConfigurations = {
        testuser = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          modules = [
            ../modules/keystone/terminal
            {
              home.username = "testuser";
              home.homeDirectory = "/home/testuser";
              home.stateVersion = "25.05";

              keystone.terminal = {
                enable = true;
                git = {
                  userName = "Test User";
                  userEmail = "testuser@keystone-test-vm";
                };
              };
            }
          ];
        };
      };

      # ============================================================
      # VM Tests (in checks)
      # ============================================================

      checks.${system} = {
        # Integration Tests
        test-installer = import ./integration/installer.nix {
          inherit pkgs;
          lib = pkgs.lib;
        };

        test-remote-unlock = import ./integration/remote-unlock.nix {
          inherit pkgs lib;
          self = keystone;
        };

        # Module Isolation Tests
        test-desktop-isolation = import ./module/desktop-isolation.nix {
          inherit pkgs lib;
          self = keystone;
        };

        test-server-isolation = import ./module/server-isolation.nix {
          inherit pkgs lib;
          self = keystone;
        };

        test-agent-isolation = import ./module/agent-isolation.nix {
          inherit pkgs lib;
          self = keystone;
          inherit home-manager;
        };

        # Evaluation Tests
        test-os-evaluation = import ./module/os-evaluation.nix {
          inherit pkgs lib;
          self = keystone;
        };

        test-agent-evaluation = import ./module/agent-evaluation.nix {
          inherit pkgs lib;
          self = keystone;
        };

        test-template-evaluation = import ./module/template-evaluation.nix {
          inherit
            pkgs
            lib
            home-manager
            nixpkgs
            ;
          self = keystone;
        };

        test-iso-evaluation = import ./module/iso-evaluation.nix {
          inherit pkgs lib;
        };

        test-desktop-autostart-assertion = import ./module/desktop-autostart-assertion.nix {
          inherit pkgs lib home-manager;
          self = keystone;
        };
      };

      # Also expose tests as packages for convenience
      packages.${system} = self.checks.${system} // {
        test-microvm-tpm = pkgs.writeShellApplication {
          name = "test-microvm-tpm";
          runtimeInputs = [ pkgs.swtpm ];
          text = builtins.readFile ../bin/test-microvm-tpm;
        };
      };
    };
}
