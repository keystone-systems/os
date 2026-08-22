{
  pkgs,
  lib,
  self,
}:
let
  nixosSystem = import "${pkgs.path}/nixos/lib/eval-config.nix";

  result = nixosSystem {
    system = "x86_64-linux";
    modules = [
      self.nixosModules.operating-system
      self.nixosModules.binaryCacheClient
      {
        system.stateVersion = "25.05";
        boot.loader.systemd-boot.enable = true;
        keystone.domain = "example.com";

        keystone.os = {
          enable = true;
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

        keystone.binaryCache = {
          enable = true;
          publicKey = "main:TEST_PUBLIC_KEY";
        };

        keystone.os.binaryCaches.extra = {
          ocean = {
            enable = true;
            url = "https://s3.example.com/nix-cache";
            publicKey = "ocean-1:TEST_PUBLIC_KEY";
          };
          disabled.enable = false;
        };
      }
    ];
  };

  missingValuesResult = nixosSystem {
    system = "x86_64-linux";
    modules = [
      self.nixosModules.operating-system
      {
        system.stateVersion = "25.05";
        boot.loader.systemd-boot.enable = true;
        keystone.os = {
          enable = true;
          binaryCaches.extra.incomplete.enable = true;
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

  substitutersJson = builtins.toJSON result.config.nix.settings.substituters;
  trustedPublicKeysJson = builtins.toJSON result.config.nix.settings.trusted-public-keys;
  missingValueFailures = builtins.filter (
    assertion: !assertion.assertion
  ) missingValuesResult.config.assertions;
  missingValueMessagesJson = builtins.toJSON (
    map (assertion: assertion.message) missingValueFailures
  );
in
pkgs.runCommand "binary-cache-client-merge-check" { } ''
  if ! echo '${substitutersJson}' | grep -Fq 'https://ks-systems.cachix.org'; then
    echo "FAIL: missing ks-systems substituter" >&2
    echo '${substitutersJson}' >&2
    exit 1
  fi

  if ! echo '${substitutersJson}' | grep -Fq 'https://cache.example.com/main'; then
    echo "FAIL: missing Attic substituter" >&2
    echo '${substitutersJson}' >&2
    exit 1
  fi

  if ! echo '${substitutersJson}' | grep -Fq 'https://s3.example.com/nix-cache'; then
    echo "FAIL: missing generic signed cache substituter" >&2
    echo '${substitutersJson}' >&2
    exit 1
  fi

  if echo '${substitutersJson}' | grep -Fq 'disabled'; then
    echo "FAIL: disabled cache was added as a substituter" >&2
    echo '${substitutersJson}' >&2
    exit 1
  fi

  if ! echo '${trustedPublicKeysJson}' | grep -Fq 'ks-systems.cachix.org-1:Abbd38auzcLIfJUtX7kSD6zdGUU4v831Sb2KfajR5Mo='; then
    echo "FAIL: missing ks-systems public key" >&2
    echo '${trustedPublicKeysJson}' >&2
    exit 1
  fi

  if ! echo '${trustedPublicKeysJson}' | grep -Fq 'main:TEST_PUBLIC_KEY'; then
    echo "FAIL: missing Attic public key" >&2
    echo '${trustedPublicKeysJson}' >&2
    exit 1
  fi

  if ! echo '${trustedPublicKeysJson}' | grep -Fq 'ocean-1:TEST_PUBLIC_KEY'; then
    echo "FAIL: missing generic signed cache public key" >&2
    echo '${trustedPublicKeysJson}' >&2
    exit 1
  fi

  if ! echo '${missingValueMessagesJson}' | grep -Fq 'binaryCaches.extra.incomplete.url'; then
    echo "FAIL: enabled caches without a URL must fail an assertion" >&2
    echo '${missingValueMessagesJson}' >&2
    exit 1
  fi

  if ! echo '${missingValueMessagesJson}' | grep -Fq 'binaryCaches.extra.incomplete.publicKey'; then
    echo "FAIL: enabled caches without a public key must fail an assertion" >&2
    echo '${missingValueMessagesJson}' >&2
    exit 1
  fi

  touch "$out"
''
