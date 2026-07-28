{ pkgs }:
let
  audit = pkgs.callPackage ../packages/hardware-key-audit.nix { };
  desiredSystem = "/nix/store/test-system";
  metadata = builtins.toFile "test-luks-metadata.json" (
    builtins.toJSON {
      tokens."1" = {
        type = "systemd-fido2";
        "fido2-credential" = "credential-1";
      };
    }
  );
  projection = pkgs.writeText "test-hardware-key-projection.json" (
    builtins.toJSON {
      contractVersion = 1;
      host = "hardware-key-test";
      findings = [ ];
      keys.yubi-green = {
        serial = "12356";
        owner = "alice";
        consumers = {
          rootSsh = [ "sk-ssh-ed25519@openssh.com AAAATEST1" ];
          pamU2f = [ "pam-handle,pam-public-key" ];
          luks = [ "cryptroot" ];
          sops = [ "age1yubikey1testrecipient" ];
          webauthn = [ ];
        };
      };
      luks.cryptroot = {
        device = "/dev/fake-root";
        enabledKeys = [ "yubi-green" ];
        installed = {
          uuid = "00000000-0000-0000-0000-000000000001";
          enrollments.yubi-green = {
            token = 1;
            credential = "credential-1";
          };
        };
      };
    }
  );
  nixMock = pkgs.writeShellScript "nix-mock" ''
    case "$1" in
      eval) cat ${projection} ;;
      build) printf '%s\n' ${desiredSystem} ;;
      *) exit 2 ;;
    esac
  '';
  ykmanMock = pkgs.writeShellScript "ykman-mock" ''
    [[ "$*" == "list --serials" ]]
    printf '12356\n'
  '';
  cryptsetupMock = pkgs.writeShellScript "cryptsetup-mock" ''
    case "$1" in
      luksUUID) printf '00000000-0000-0000-0000-000000000001\n' ;;
      luksDump) cat ${metadata} ;;
      *) exit 2 ;;
    esac
  '';
  sudoMock = pkgs.writeShellScript "sudo-mock" ''
    [[ "$1" == "-n" ]] && shift
    exec "$@"
  '';
in
pkgs.runCommand "hardware-key-audit-tests"
  {
    nativeBuildInputs = [ pkgs.jq ];
  }
  ''
    # THIS TEST VALIDATES THE CONSUMER-EVALUATOR BOUNDARY
    # The wrapper must inherit Nix from the caller instead of pinning pkgs.nix.
    ! grep -F '${pkgs.nix}/bin' ${audit}/bin/ks-hardware-key-audit

    export KS_HARDWARE_KEY_NIX=${nixMock}
    export KS_HARDWARE_KEY_YKMAN=${ykmanMock}
    export KS_HARDWARE_KEY_CRYPTSETUP=${cryptsetupMock}
    export KS_HARDWARE_KEY_SUDO=${sudoMock}
    export KS_HARDWARE_KEY_CURRENT_SYSTEM=${desiredSystem}

    ${audit}/bin/ks-hardware-key-audit \
      --flake ignored \
      --host hardware-key-test \
      --local \
      --strict \
      --json >complete.json
    jq -e 'all(.status != "warn" and .status != "error")' complete.json >/dev/null
    jq -e 'any(.code == "luks.cryptroot.yubi-green" and .status == "ok")' complete.json >/dev/null

    export KS_HARDWARE_KEY_CURRENT_SYSTEM=/nix/store/stale-system
    ${audit}/bin/ks-hardware-key-audit \
      --flake ignored \
      --host hardware-key-test \
      --local \
      --json >drift.json
    jq -e 'any(.code == "system.generation" and .status == "warn")' drift.json >/dev/null

    touch "$out"
  ''
