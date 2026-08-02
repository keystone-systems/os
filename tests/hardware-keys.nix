{
  nixpkgs,
  pkgs,
}:
let
  lib = nixpkgs.lib;

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
  };

  failures = lib.runTests tests;
  resultFile = builtins.toFile "hardware-key-test-results.json" (builtins.toJSON failures);
in
pkgs.runCommand "hardware-key-module-tests"
  {
    nativeBuildInputs = [ pkgs.jq ];
  }
  ''
    jq . ${resultFile}
    jq -e 'length == 0' ${resultFile} >/dev/null
    touch "$out"
  ''
