# Shared test utilities for Keystone NixOS tests
#
# Usage in test files:
#   { pkgs, lib, self }:
#   let testLib = import ../lib.nix { inherit pkgs self; };
#   in ...
#
{
  pkgs,
  self,
}:
{
  # Create a module test with common defaults
  mkModuleTest =
    {
      name,
      module ? null,
      modules ? [ ],
      testScript,
      nodes ? { },
      ...
    }@args:
    pkgs.testers.nixosTest (
      {
        inherit name testScript;
        nodes =
          if nodes != { } then
            nodes
          else
            {
              machine =
                { config, ... }:
                {
                  imports = if module != null then [ module ] ++ modules else modules;
                };
            };
      }
      // removeAttrs args [
        "module"
        "modules"
      ]
    );

  # Standard VM settings for tests
  vmDefaults = {
    virtualisation = {
      memorySize = 4096;
      cores = 2;
    };
  };

  # Minimal VM for fast tests
  vmMinimal = {
    virtualisation = {
      memorySize = 2048;
      cores = 2;
    };
  };

  # VM with graphics for desktop tests
  vmGraphics = {
    virtualisation = {
      memorySize = 4096;
      cores = 2;
      graphics = true;
    };
  };

  # Common test user configuration
  testUser = {
    users.users.testuser = {
      isNormalUser = true;
      initialPassword = "testpass";
      extraGroups = [
        "wheel"
        "networkmanager"
        "video"
        "audio"
      ];
    };
    security.sudo.wheelNeedsPassword = false;
  };
}
