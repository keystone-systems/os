{
  pkgs,
  self,
  home-manager,
  ...
}:
let
  mkConfig =
    osConfig:
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit osConfig; };
      modules = [
        self.homeModules.notes
        self.homeModules.terminal
        {
          nixpkgs.overlays = [ self.overlays.default ];
          home.username = "testuser";
          home.homeDirectory = "/home/testuser";
          home.stateVersion = "25.05";
          keystone.terminal = {
            enable = true;
            git = {
              userName = "Test User";
              userEmail = "testuser@example.com";
            };
          };
        }
      ];
    };
  vars = osConfig: (mkConfig osConfig).config.home.sessionVariables;
  enabled = vars {
    keystone.os = {
      enable = true;
      binaryCaches = {
        ksSystems = {
          enable = true;
          url = "https://ks.example.com";
          publicKey = "ks-1:KEY";
        };
        extra = {
          ocean = {
            enable = true;
            url = "https://ocean.example.com/nix-cache";
            publicKey = "ocean-1:KEY";
          };
          disabled = {
            enable = false;
            url = "https://disabled.example.com";
            publicKey = "disabled-1:KEY";
          };
        };
      };
    };
  };
  disabled = vars {
    keystone.os = {
      enable = true;
      binaryCaches = {
        ksSystems.enable = false;
        extra.disabled = {
          enable = false;
          url = "https://disabled.example.com";
          publicKey = "disabled-1:KEY";
        };
      };
    };
  };
  partial = vars { keystone.os.enable = true; };
  osDisabled = vars {
    keystone.os = {
      enable = false;
      binaryCaches.extra.ocean = {
        enable = true;
        url = "https://ocean.example.com/nix-cache";
        publicKey = "ocean-1:KEY";
      };
    };
  };
in
assert
  enabled.PODMAN_AGENT_EXTRA_SUBSTITUTERS
  == "https://ks.example.com https://ocean.example.com/nix-cache";
assert enabled.PODMAN_AGENT_EXTRA_TRUSTED_PUBLIC_KEYS == "ks-1:KEY ocean-1:KEY";
assert !(disabled ? PODMAN_AGENT_EXTRA_SUBSTITUTERS);
assert !(disabled ? PODMAN_AGENT_EXTRA_TRUSTED_PUBLIC_KEYS);
assert !(partial ? PODMAN_AGENT_EXTRA_SUBSTITUTERS);
assert !(partial ? PODMAN_AGENT_EXTRA_TRUSTED_PUBLIC_KEYS);
assert !(osDisabled ? PODMAN_AGENT_EXTRA_SUBSTITUTERS);
assert !(osDisabled ? PODMAN_AGENT_EXTRA_TRUSTED_PUBLIC_KEYS);
pkgs.runCommand "terminal-sandbox-binary-caches-check" { } ''
  touch "$out"
''
