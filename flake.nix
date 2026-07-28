{
  description = "Keystone OS — fleet library and unified vm/machine test harness";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      mkFleet = import ./lib/mk-fleet.nix { inherit nixpkgs; };

      ks-fleet = pkgs.writeShellApplication {
        name = "ks-fleet";
        runtimeInputs = [
          pkgs.jq
          pkgs.openssh
          pkgs.nixos-rebuild
        ];
        text = builtins.readFile ./bin/ks-fleet;
      };
      hardware-key-audit = pkgs.callPackage ./packages/hardware-key-audit.nix { };

      # Self-demonstrating example fleet: ks-demo-a defaults to a VM;
      # ks-demo-b carries a machine target (the ks-test-delltop pattern) and
      # defaults to it, while remaining bootable as a VM via `--as vm`.
      # `ks-fleet test` on this repo therefore exercises the mixed path.
      example = mkFleet {
        hostsDir = ./examples/hosts;
        baseModules = [ disko.nixosModules.disko ];
        targets = {
          ks-demo-b = {
            machine = {
              sshTarget = "192.168.1.64";
              user = "ncrmro";
            };
          };
          # LUKS host demonstrating the install realization: boots the real
          # disko-built disk image with an emulated TPM2 attached.
          ks-demo-luks.install = { };
        };
      };
    in
    {
      lib = {
        inherit mkFleet;
      };

      nixosModules = {
        default = import ./modules;
        diskoVmToolsCompat = import ./modules/disko-vm-tools-compat.nix;
      };

      inherit (example) nixosConfigurations fleetMeta;

      packages.${system} = {
        inherit hardware-key-audit ks-fleet;
        default = ks-fleet;
      }
      // example.packages.${system};

      checks.${system} = {
        hardware-keys = import ./tests/hardware-keys.nix {
          inherit nixpkgs pkgs;
        };
        hardware-key-audit = import ./tests/hardware-key-audit.nix {
          inherit pkgs;
        };
      };

      apps.${system} = example.apps.${system};
    };
}
