{
  nixpkgs,
  pkgs,
}:
let
  lib = nixpkgs.lib;
  blackPublicKey = "sk-ssh-ed25519@openssh.com AAAATESTBLACK alice-black";
  greenPublicKey = "sk-ssh-ed25519@openssh.com AAAATESTGREEN alice-green";
  blackHandle = builtins.toFile "yubi-black-handle" "test black handle";
  greenHandle = builtins.toFile "yubi-green-handle" "test green handle";
  fakeYkman = pkgs.writeShellScriptBin "ykman" ''
    if [[ -v PYTHONHOME || -v PYTHONPATH ]]; then
      exit 3
    fi

    if [[ "$#" == 2 && "$1" == list && "$2" == --serials ]]; then
      printf '%s\n' "''${KEYSTONE_TEST_YUBIKEY_SERIALS:-}"
      if [[ "''${KEYSTONE_TEST_YUBIKEY_ERROR:-0}" == 1 ]]; then
        exit 1
      fi
      exit 0
    fi

    exit 2
  '';

  baseModule = {
    networking.hostName = "hardware-key-test";
    system.stateVersion = "25.05";

    boot.loader.grub.device = "nodev";
    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };

    users.users.alice = {
      isNormalUser = true;
      group = "users";
    };

    # The Nix build user cannot read an included ssh_config file from a
    # Nix store path because OpenSSH requires root ownership. The deployed
    # system links that file into /etc with root ownership.
    programs.ssh.systemd-ssh-proxy.enable = false;

    boot.initrd.luks.devices.cryptroot.device = "/dev/disk/by-partlabel/root";
    keystone.hardwareKeyLuksTargets = [ "cryptroot" ];
  };

  completeModule = {
    keystone.hardwareKeys = {
      yubi-green = "12356";
    };
    keystone.hardwareKeyRegistrations.yubi-green = {
      owner = "alice";
      sshPublicKeys = [
        "sk-ssh-ed25519@openssh.com AAAATEST1 alice-green"
        "sk-ssh-ed25519@openssh.com AAAATEST2 alice-green-backup-handle"
      ];
      pamU2f = [
        "pam-handle-1,pam-public-key-1"
        "pam-handle-2,pam-public-key-2"
      ];
      ageRecipients = [
        "age1yubikey1testrecipient1"
        "age1yubikey1testrecipient2"
      ];
      webAuthn = [
        {
          relyingParty = "login.example.test";
          credentialId = "credential-1";
        }
        {
          relyingParty = "admin.example.test";
          credentialId = "credential-2";
        }
      ];
    };
    keystone.hardwareKeyState.luks.cryptroot = {
      uuid = "00000000-0000-0000-0000-000000000001";
      enrollments.yubi-green = {
        token = 1;
        credential = "fido-credential-1";
      };
    };
    keystone.keys.alice.hardwareKeys.yubi-green = {
      publicKey = "sk-ssh-ed25519@openssh.com AAAATEST1 alice-green";
      handleSource = greenHandle;
    };
  };

  mkSystem =
    extraModule:
    lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ../modules
        baseModule
        extraModule
      ];
    };

  complete = (mkSystem completeModule).config;
  empty = (mkSystem { }).config;
  gaps =
    (mkSystem {
      keystone.hardwareKeys.yubi-green = "12356";
      keystone.hardwareKeyRegistrations.yubi-green.owner = "alice";
    }).config;
  stale =
    (mkSystem {
      keystone.hardwareKeyRegistrations.yubi-green =
        completeModule.keystone.hardwareKeyRegistrations.yubi-green;
      keystone.hardwareKeyState.luks.cryptroot = completeModule.keystone.hardwareKeyState.luks.cryptroot;
    }).config;
  duplicateSerial =
    (mkSystem {
      keystone.hardwareKeys = {
        yubi-green = "12356";
        yubi-black = "12356";
      };
    }).config;
  privateIdentity =
    (mkSystem {
      keystone.hardwareKeyRegistrations.yubi-green = {
        owner = "alice";
        ageRecipients = [ "AGE-PLUGIN-YUBIKEY-PRIVATE-HANDLE" ];
      };
    }).config;
  strictGaps =
    (mkSystem {
      keystone.hardwareKeys.yubi-green = "12356";
      keystone.hardwareKeyRegistrations.yubi-green.owner = "alice";
      keystone.hardwareKeyPolicy.strict = true;
    }).config;
  sshSelection =
    (mkSystem {
      nixpkgs.overlays = [
        (_final: _previous: {
          yubikey-manager = fakeYkman;
        })
      ];

      keystone.hardwareKeys = {
        yubi-black = "12345";
        yubi-green = "12356";
      };
      keystone.hardwareKeyRegistrations = {
        yubi-black = {
          owner = "alice";
          sshPublicKeys = [ blackPublicKey ];
        };
        yubi-green = {
          owner = "alice";
          sshPublicKeys = [ greenPublicKey ];
        };
      };
      keystone.keys.alice.hardwareKeys = {
        yubi-black = {
          publicKey = blackPublicKey;
          handleSource = blackHandle;
        };
        yubi-green = {
          publicKey = greenPublicKey;
          handleSource = greenHandle;
        };
      };
    }).config;
  sshMissingHandle =
    (mkSystem {
      nixpkgs.overlays = [
        (_final: _previous: {
          yubikey-manager = fakeYkman;
        })
      ];

      keystone.hardwareKeys.yubi-black = "12345";
      keystone.hardwareKeyRegistrations.yubi-black = {
        owner = "alice";
        sshPublicKeys = [ blackPublicKey ];
      };
    }).config;
  sshClientConfig = sshSelection.environment.etc."ssh/ssh_config".text;
  sshMissingHandleConfig = sshMissingHandle.environment.etc."ssh/ssh_config".text;
  sshClientConfigFile = pkgs.writeText "hardware-key-ssh-config" sshClientConfig;
  sshMissingHandleConfigFile = pkgs.writeText "hardware-key-missing-handle-ssh-config" sshMissingHandleConfig;

  codes = config: map (item: item.code) config.keystone.hardwareKeyFindings;
  assertionWith =
    needle: config: lib.findFirst (item: lib.hasInfix needle item.message) null config.assertions;

  tests = {
    # THIS TEST VALIDATES A HARD REQUIREMENT (KSC-001.4)
    # YOU MUST NOT MODIFY THIS TEST UNLESS THE REQUIREMENT CHANGES
    testSerialEnablesEveryApplicableConsumer = {
      expr = {
        findings = complete.keystone.hardwareKeyFindings;
        rootSsh = complete.users.users.root.openssh.authorizedKeys.keys;
        pamEnabled = complete.security.pam.u2f.enable;
        pamControl = complete.security.pam.u2f.control;
        luksOptions = complete.boot.initrd.luks.devices.cryptroot.crypttabExtraOpts;
        projectedConsumers = complete.keystone.hardwareKeyProjection.keys.yubi-green.consumers;
        runtimeSnapshot = complete.environment.etc ? "keystone/hardware-keys.json";
      };
      expected = {
        findings = [ ];
        rootSsh = completeModule.keystone.hardwareKeyRegistrations.yubi-green.sshPublicKeys;
        pamEnabled = true;
        pamControl = "sufficient";
        luksOptions = [ "fido2-device=auto" ];
        runtimeSnapshot = false;
        projectedConsumers = {
          rootSsh = completeModule.keystone.hardwareKeyRegistrations.yubi-green.sshPublicKeys;
          pamU2f = completeModule.keystone.hardwareKeyRegistrations.yubi-green.pamU2f;
          luks = [ "cryptroot" ];
          sops = completeModule.keystone.hardwareKeyRegistrations.yubi-green.ageRecipients;
          webauthn = completeModule.keystone.hardwareKeyRegistrations.yubi-green.webAuthn;
        };
      };
    };

    # THIS TEST VALIDATES A HARD REQUIREMENT (KSC-001.4)
    # YOU MUST NOT MODIFY THIS TEST UNLESS THE REQUIREMENT CHANGES
    testDisabledMeansNoConsumers = {
      expr = {
        projection = empty.keystone.hardwareKeyProjection.keys;
        rootSsh = empty.users.users.root.openssh.authorizedKeys.keys;
        pamEnabled = empty.security.pam.u2f.enable;
        pcscdEnabled = empty.services.pcscd.enable;
      };
      expected = {
        projection = { };
        rootSsh = [ ];
        pamEnabled = false;
        pcscdEnabled = false;
      };
    };

    # THIS TEST VALIDATES A HARD REQUIREMENT (KSC-001.4)
    # YOU MUST NOT MODIFY THIS TEST UNLESS THE REQUIREMENT CHANGES
    testEnabledUdevRulesHaveCompatibilityGroups = {
      expr = {
        libfido2RulesInstalled = lib.elem pkgs.libfido2 complete.services.udev.packages;
        plugdevExists = complete.users.groups ? plugdev;
      };
      expected = {
        libfido2RulesInstalled = true;
        plugdevExists = true;
      };
    };

    # THIS TEST VALIDATES A HARD REQUIREMENT (KSC-001.4)
    # YOU MUST NOT MODIFY THIS TEST UNLESS THE REQUIREMENT CHANGES
    testDisabledOmitsHardwareKeyUdevIntegration = {
      expr = {
        libfido2RulesInstalled = lib.elem pkgs.libfido2 empty.services.udev.packages;
        plugdevExists = empty.users.groups ? plugdev;
      };
      expected = {
        libfido2RulesInstalled = false;
        plugdevExists = false;
      };
    };

    # THIS TEST VALIDATES A HARD REQUIREMENT (KSC-001.4)
    # YOU MUST NOT MODIFY THIS TEST UNLESS THE REQUIREMENT CHANGES
    testMissingRegistrationsAndEnrollmentWarn = {
      expr = codes gaps;
      expected = [
        "KSC-001.4/missing-root-ssh"
        "KSC-001.4/missing-pam-u2f"
        "KSC-001.4/missing-sops-recipient"
        "KSC-001.4/missing-luks-enrollment"
      ];
    };

    # THIS TEST VALIDATES A HARD REQUIREMENT (KSC-001.4)
    # YOU MUST NOT MODIFY THIS TEST UNLESS THE REQUIREMENT CHANGES
    #
    # A declared LUKS target must never make the initrd demand a credential
    # that is not enrolled. systemd does not fall back to the passphrase when
    # FIDO2 unlock fails (systemd issue 19872), so emitting fido2-device=auto
    # for an unenrolled target stops the host from booting.
    testUnenrolledTargetDoesNotDemandFido2AtBoot = {
      expr = {
        unenrolled = gaps.boot.initrd.luks.devices.cryptroot.crypttabExtraOpts;
        enrolled = complete.boot.initrd.luks.devices.cryptroot.crypttabExtraOpts;
      };
      expected = {
        unenrolled = [ ];
        enrolled = [ "fido2-device=auto" ];
      };
    };

    # THIS TEST VALIDATES A HARD REQUIREMENT (KSC-001.4)
    # YOU MUST NOT MODIFY THIS TEST UNLESS THE REQUIREMENT CHANGES
    testRemovalReportsStaleStateWithoutDeletingIt = {
      expr = {
        codes = codes stale;
        installed = stale.keystone.hardwareKeyState.luks.cryptroot.enrollments.yubi-green.token;
      };
      expected = {
        codes = [ "KSC-001.4/stale-luks-enrollment" ];
        installed = 1;
      };
    };

    # THIS TEST VALIDATES A HARD REQUIREMENT (KSC-001.4)
    # YOU MUST NOT MODIFY THIS TEST UNLESS THE REQUIREMENT CHANGES
    testMultipleCredentialsOfEachClassRemainIndependent = {
      expr = {
        ssh = builtins.length complete.keystone.hardwareKeyProjection.keys.yubi-green.consumers.rootSsh;
        pam = builtins.length complete.keystone.hardwareKeyProjection.keys.yubi-green.consumers.pamU2f;
        sops = builtins.length complete.keystone.hardwareKeyProjection.keys.yubi-green.consumers.sops;
        webauthn = builtins.length complete.keystone.hardwareKeyProjection.keys.yubi-green.consumers.webauthn;
      };
      expected = {
        ssh = 2;
        pam = 2;
        sops = 2;
        webauthn = 2;
      };
    };

    # THIS TEST VALIDATES A HARD REQUIREMENT (KSC-001.3)
    # YOU MUST NOT MODIFY THIS TEST UNLESS THE REQUIREMENT CHANGES
    testDuplicateSerialsAreRejected = {
      expr = (assertionWith "serials must be unique" duplicateSerial).assertion;
      expected = false;
    };

    # THIS TEST VALIDATES A HARD REQUIREMENT (KSC-001.4)
    # YOU MUST NOT MODIFY THIS TEST UNLESS THE REQUIREMENT CHANGES
    testPrivateIdentityFormatsAreRejectedInAnyPublicValue = {
      expr = (assertionWith "private identity" privateIdentity).assertion;
      expected = false;
    };

    # THIS TEST VALIDATES A HARD REQUIREMENT (KSC-001.4)
    # YOU MUST NOT MODIFY THIS TEST UNLESS THE REQUIREMENT CHANGES
    testStrictWorkflowsRejectFindings = {
      expr = (assertionWith "strict hardware-key validation failed" strictGaps).assertion;
      expected = false;
    };

    # THIS TEST VALIDATES A HARD REQUIREMENT (KSC-001.4)
    # YOU MUST NOT MODIFY THIS TEST UNLESS THE REQUIREMENT CHANGES
    testRootSshSelectsOnlyConnectedHardwareKeys = {
      expr = {
        failClosed = lib.hasInfix "IdentityFile none" sshClientConfig;
        identitiesOnly = lib.hasInfix "IdentitiesOnly yes" sshClientConfig;
        ignoresAgent = lib.hasInfix "IdentityAgent none" sshClientConfig;
        blackSerial = lib.hasInfix "grep -Fxq -- 12345" sshClientConfig;
        greenSerial = lib.hasInfix "grep -Fxq -- 12356" sshClientConfig;
        detectorUsesPipefail = lib.hasInfix "bash -o pipefail -c" sshClientConfig;
        detectorClearsPythonEnvironment = lib.hasInfix "env -u PYTHONHOME -u PYTHONPATH" sshClientConfig;
        blackHandle = lib.hasInfix "IdentityFile /home/alice/.ssh/id_ed25519_sk_yubi-black" sshClientConfig;
        greenHandle = lib.hasInfix "IdentityFile /home/alice/.ssh/id_ed25519_sk_yubi-green" sshClientConfig;
        suppressesYkmanErrors = lib.hasInfix "ykman list --serials 2>/dev/null" sshClientConfig;
        noBlackAgentLoader = !(sshSelection.systemd.user.services ? ssh-add-alice-yubi-black);
        noGreenAgentLoader = !(sshSelection.systemd.user.services ? ssh-add-alice-yubi-green);
        installsBlackHandle = lib.any (lib.hasInfix "/home/alice/.ssh/id_ed25519_sk_yubi-black") sshSelection.systemd.tmpfiles.rules;
        installsGreenHandle = lib.any (lib.hasInfix "/home/alice/.ssh/id_ed25519_sk_yubi-green") sshSelection.systemd.tmpfiles.rules;
        reportsMissingHandle = lib.elem "KSC-001.4/missing-ssh-handle" (codes sshMissingHandle);
        protectsRootWithoutHandle = lib.hasInfix "IdentityFile none" sshMissingHandleConfig;
        noMissingDynamicHandle = !(lib.hasInfix "id_ed25519_sk_yubi-black" sshMissingHandleConfig);
      };
      expected = {
        failClosed = true;
        identitiesOnly = true;
        ignoresAgent = true;
        blackSerial = true;
        greenSerial = true;
        detectorUsesPipefail = true;
        detectorClearsPythonEnvironment = true;
        blackHandle = true;
        greenHandle = true;
        suppressesYkmanErrors = true;
        noBlackAgentLoader = true;
        noGreenAgentLoader = true;
        installsBlackHandle = true;
        installsGreenHandle = true;
        reportsMissingHandle = true;
        protectsRootWithoutHandle = true;
        noMissingDynamicHandle = true;
      };
    };
  };

  failures = lib.runTests tests;
  resultFile = builtins.toFile "hardware-key-test-results.json" (builtins.toJSON failures);
in
pkgs.runCommand "hardware-key-module-tests"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.openssh
    ];
  }
  ''
    jq . ${resultFile}
    jq -e 'length == 0' ${resultFile} >/dev/null

    local_user="$(${pkgs.coreutils}/bin/id -un)"
    ${pkgs.gnused}/bin/sed "s/localuser alice/localuser $local_user/g" \
      ${sshClientConfigFile} > "$TMPDIR/ssh-config"
    ${pkgs.gnused}/bin/sed "s/localuser alice/localuser $local_user/g" \
      ${sshMissingHandleConfigFile} > "$TMPDIR/ssh-config-missing-handle"

    check_case() {
      local serials="$1"
      local expect_black="$2"
      local expect_green="$3"
      local ykman_error="$4"
      local output

      output="$(
        PYTHONHOME=/poisoned-python-home \
        PYTHONPATH=/poisoned-python-path \
        KEYSTONE_TEST_YUBIKEY_SERIALS="$serials" \
        KEYSTONE_TEST_YUBIKEY_ERROR="$ykman_error" \
          ssh -F "$TMPDIR/ssh-config" -G root@192.0.2.1 2>/dev/null
      )"

      printf '%s\n' "$output" | grep -Fx 'identityfile none' >/dev/null
      printf '%s\n' "$output" | grep -Fx 'identityagent none' >/dev/null
      printf '%s\n' "$output" | grep -Fx 'identitiesonly yes' >/dev/null

      if [[ "$expect_black" == yes ]]; then
        printf '%s\n' "$output" | grep -Fx \
          'identityfile /home/alice/.ssh/id_ed25519_sk_yubi-black' >/dev/null
      elif printf '%s\n' "$output" | grep -Fq \
        '/home/alice/.ssh/id_ed25519_sk_yubi-black'; then
        echo "black handle was selected when its serial was absent" >&2
        exit 1
      fi

      if [[ "$expect_green" == yes ]]; then
        printf '%s\n' "$output" | grep -Fx \
          'identityfile /home/alice/.ssh/id_ed25519_sk_yubi-green' >/dev/null
      elif printf '%s\n' "$output" | grep -Fq \
        '/home/alice/.ssh/id_ed25519_sk_yubi-green'; then
        echo "green handle was selected when its serial was absent" >&2
        exit 1
      fi
    }

    check_case '12345' yes no 0
    check_case '12356' no yes 0
    check_case $'12345\n12356' yes yes 0
    check_case "" no no 0
    check_case '12345' no no 1

    missing_handle_output="$(
      KEYSTONE_TEST_YUBIKEY_SERIALS='12345' \
        ssh -F "$TMPDIR/ssh-config-missing-handle" -G root@192.0.2.1 2>/dev/null
    )"
    printf '%s\n' "$missing_handle_output" | grep -Fx 'identityfile none' >/dev/null
    printf '%s\n' "$missing_handle_output" | grep -Fx 'identityagent none' >/dev/null
    if printf '%s\n' "$missing_handle_output" | grep -Fq 'id_ed25519_sk_yubi-black'; then
      echo "root SSH selected a handle that Keystone did not install" >&2
      exit 1
    fi

    non_root_output="$(
      KEYSTONE_TEST_YUBIKEY_SERIALS=$'12345\n12356' \
        ssh -F "$TMPDIR/ssh-config" -G alice@192.0.2.1 2>/dev/null
    )"
    if printf '%s\n' "$non_root_output" | grep -Fq 'identityfile none'; then
      echo "the root SSH policy changed non-root SSH" >&2
      exit 1
    fi
    if printf '%s\n' "$non_root_output" | grep -Fq 'id_ed25519_sk_yubi-'; then
      echo "the root SSH policy selected a YubiKey for non-root SSH" >&2
      exit 1
    fi
    printf '%s\n' "$non_root_output" | grep -Fx 'identityfile ~/.ssh/id_rsa' >/dev/null

    touch "$out"
  ''
