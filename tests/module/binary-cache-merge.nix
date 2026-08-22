{
  pkgs,
  lib,
  self,
}:
let
  nixosSystem = import "${pkgs.path}/nixos/lib/eval-config.nix";
  mkResult =
    binaryCaches:
    nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.operating-system
        {
          system.stateVersion = "25.05";
          boot.loader.systemd-boot.enable = true;
          keystone.domain = "example.com";
          keystone.os = {
            enable = true;
            inherit binaryCaches;
            storage = {
              type = "lvm";
              devices = [ "/dev/vda" ];
            };
            users.testuser = {
              fullName = "Test User";
              initialPassword = "testpass";
            };
          };
          fileSystems."/" = {
            device = lib.mkForce "/dev/vda2";
            fsType = lib.mkForce "ext4";
          };
        }
      ];
    };

  result = mkResult {
    extra = {
      ocean = {
        enable = true;
        url = "https://s3.example.com/nix-cache";
        publicKey = "ocean-1:TEST_PUBLIC_KEY";
      };
      disabled = {
        enable = false;
        url = "https://disabled.example.com/nix-cache";
        publicKey = "disabled-1:TEST_PUBLIC_KEY";
      };
    };
  };
  incompleteResult = mkResult {
    extra.incomplete.enable = true;
  };
  extraOnlyResult = mkResult {
    ksSystems.enable = false;
    extra.ocean = {
      enable = true;
      url = "https://s3.example.com/nix-cache";
      publicKey = "ocean-1:TEST_PUBLIC_KEY";
    };
  };
  invalidUrlResult = mkResult {
    extra = {
      http = {
        enable = true;
        url = "http://cache.example.com/nix-cache";
        publicKey = "http-1:TEST_PUBLIC_KEY";
      };
      userinfo = {
        enable = true;
        url = "https://writer:secret@cache.example.com/nix-cache";
        publicKey = "userinfo-1:TEST_PUBLIC_KEY";
      };
      token = {
        enable = true;
        url = "https://cache.example.com/nix-cache?token=secret";
        publicKey = "token-1:TEST_PUBLIC_KEY";
      };
    };
  };

  failedAssertions =
    evaluation: builtins.filter (assertion: !assertion.assertion) evaluation.config.assertions;
  substitutersJson = builtins.toJSON result.config.nix.settings.substituters;
  trustedPublicKeysJson = builtins.toJSON result.config.nix.settings.trusted-public-keys;
  incompleteSubstitutersJson = builtins.toJSON incompleteResult.config.nix.settings.substituters;
  incompleteKeysJson = builtins.toJSON incompleteResult.config.nix.settings.trusted-public-keys;
  incompleteMessagesJson = builtins.toJSON (
    map (assertion: assertion.message) (failedAssertions incompleteResult)
  );
  extraOnlySubstitutersJson = builtins.toJSON extraOnlyResult.config.nix.settings.substituters;
  extraOnlyKeysJson = builtins.toJSON extraOnlyResult.config.nix.settings.trusted-public-keys;
  invalidUrlMessagesJson = builtins.toJSON (
    map (assertion: assertion.message) (failedAssertions invalidUrlResult)
  );
in
pkgs.runCommand "binary-cache-merge-check" { } ''
  set -euo pipefail

  grep -Fq 'https://ks-systems.cachix.org' <<<'${substitutersJson}'
  grep -Fq 'https://s3.example.com/nix-cache' <<<'${substitutersJson}'
  grep -Fq 'ks-systems.cachix.org-1:Abbd38auzcLIfJUtX7kSD6zdGUU4v831Sb2KfajR5Mo=' <<<'${trustedPublicKeysJson}'
  grep -Fq 'ocean-1:TEST_PUBLIC_KEY' <<<'${trustedPublicKeysJson}'

  if grep -Fq 'disabled.example.com' <<<'${substitutersJson}' \
      || grep -Fq 'disabled-1:TEST_PUBLIC_KEY' <<<'${trustedPublicKeysJson}'; then
    echo 'FAIL: disabled cache values reached Nix settings' >&2
    exit 1
  fi

  grep -Fq 'binaryCaches.extra.incomplete.url' <<<'${incompleteMessagesJson}'
  grep -Fq 'binaryCaches.extra.incomplete.publicKey' <<<'${incompleteMessagesJson}'
  if grep -Fq 'incomplete' <<<'${incompleteSubstitutersJson}${incompleteKeysJson}'; then
    echo 'FAIL: incomplete cache reached Nix settings' >&2
    exit 1
  fi

  grep -Fq 'https://cache.nixos.org' <<<'${extraOnlySubstitutersJson}'
  grep -Fq 'https://s3.example.com/nix-cache' <<<'${extraOnlySubstitutersJson}'
  grep -Fq 'ocean-1:TEST_PUBLIC_KEY' <<<'${extraOnlyKeysJson}'
  if grep -Fq 'ks-systems.cachix.org' <<<'${extraOnlySubstitutersJson}${extraOnlyKeysJson}'; then
    echo 'FAIL: disabled ksSystems cache reached Nix settings' >&2
    exit 1
  fi

  for name in http userinfo token; do
    grep -Fq "binaryCaches.extra.$name.url must use credential-free HTTPS" \
      <<<'${invalidUrlMessagesJson}'
  done

  touch "$out"
''
