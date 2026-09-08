# OS module evaluation test
#
# This test verifies that the OS module evaluates correctly with various
# configuration options. It doesn't boot a VM (which would require disko
# to actually partition disks), but validates the module's NixOS options
# and configuration generation.
#
# Build: nix build .#checks.x86_64-linux.os-evaluation
#
{
  pkgs,
  lib,
  self,
}:
# This is a simple evaluation test, not a VM test
# We verify the module evaluates without errors for various configurations
let
  nixosSystem = import "${pkgs.path}/nixos/lib/eval-config.nix";

  eval =
    name: modules:
    let
      result = nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.operating-system
          {
            system.stateVersion = "25.05";
            boot.loader.systemd-boot.enable = true;
          }
        ]
        ++ modules;
      };
      servicesJson = builtins.toJSON (builtins.attrNames result.config.systemd.services);
      socketsJson = builtins.toJSON (builtins.attrNames result.config.systemd.sockets);
    in
    pkgs.runCommand "eval-${name}" { } ''
      echo "Evaluating ${name}..."
      echo "  Services: ${servicesJson}"
      echo "  Sockets: ${socketsJson}"
      touch $out
    '';

  # Evaluate a module set and assert keystone.os.adminUsername resolves
  # to `expected`. Pins the auto-derivation from the admin flag.
  assertAdminUsername =
    name: expected: modules:
    let
      result = (import "${pkgs.path}/nixos/lib/eval-config.nix") {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.operating-system
          {
            system.stateVersion = "25.05";
            boot.loader.systemd-boot.enable = true;
          }
        ]
        ++ modules;
      };
      actual = result.config.keystone.os.adminUsername;
    in
    pkgs.runCommand "admin-username-${name}" { } ''
      if [ "${actual}" != "${expected}" ]; then
        echo "FAIL: ${name}: expected adminUsername=${expected}, got ${actual}" >&2
        exit 1
      fi
      echo "OK: ${name}: adminUsername=${actual}"
      touch $out
    '';

  # Evaluate a module set and assert at least one failing assertion contains
  # `expectedText`. adminUsername itself still resolves (to its default) —
  # the assertion list is what flags the invalid config.
  assertHasFailingAssertion =
    name: expectedText: modules:
    let
      result = (import "${pkgs.path}/nixos/lib/eval-config.nix") {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.operating-system
          {
            system.stateVersion = "25.05";
            boot.loader.systemd-boot.enable = true;
          }
        ]
        ++ modules;
      };
      failing = builtins.filter (a: !a.assertion) result.config.assertions;
      matched = builtins.any (a: lib.hasInfix expectedText a.message) failing;
    in
    pkgs.runCommand "admin-assertion-${name}" { } ''
      ${
        if matched then
          ''echo "OK: ${name}: assertion containing '${expectedText}' fired"''
        else
          ''
            echo "FAIL: ${name}: expected a failing assertion containing '${expectedText}'" >&2
            exit 1
          ''
      }
      touch $out
    '';

  assertConsoleMode =
    name: expected: modules:
    let
      result = nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.operating-system
          {
            system.stateVersion = "25.05";
            boot.loader.systemd-boot.enable = true;
          }
        ]
        ++ modules;
      };
      actual = result.config.boot.loader.systemd-boot.consoleMode;
    in
    pkgs.runCommand "systemd-boot-console-mode-${name}" { } ''
      if [ "${actual}" != "${expected}" ]; then
        echo "FAIL: ${name}: expected consoleMode=${expected}, got ${actual}" >&2
        exit 1
      fi
      echo "OK: ${name}: consoleMode=${actual}"
      touch $out
    '';

  assertKernelPolicy =
    let
      result = nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.operating-system
          adminBase
          {
            system.stateVersion = "25.05";
            boot.loader.systemd-boot.enable = true;
          }
        ];
      };
      kernelPackages = result.config.boot.kernelPackages;
      zfsPackage = result.config.boot.zfs.package;
      zfsModule = kernelPackages.${zfsPackage.kernelModuleAttribute};
      valid =
        lib.versions.majorMinor kernelPackages.kernel.version == "7.1"
        && lib.versions.majorMinor zfsPackage.version == "2.4"
        && !(zfsModule.meta.broken or false);
    in
    pkgs.runCommand "linux-7-1-zfs-kernel-policy" { } ''
      ${lib.optionalString (!valid) ''
        echo 'FAIL: expected Linux 7.1 with a buildable OpenZFS 2.4 module' >&2
        echo 'kernel=${kernelPackages.kernel.version}' >&2
        echo 'zfs=${zfsPackage.version}' >&2
        echo 'module=${zfsModule.name}' >&2
        exit 1
      ''}
      echo 'OK: kernel=${kernelPackages.kernel.version} zfs=${zfsPackage.version} module=${zfsModule.name}'
      touch $out
    '';

  assertNixChannelPolicy =
    let
      result = nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.operating-system
          adminBase
          {
            system.stateVersion = "25.05";
            boot.loader.systemd-boot.enable = true;
          }
        ];
      };
      channelEnabled = result.config.nix.channel.enable;
      hasLegacyChannelPath = builtins.elem "/nix/var/nix/profiles/per-user/root/channels" result.config.nix.nixPath;
    in
    pkgs.runCommand "nix-channel-policy" { } ''
      ${lib.optionalString channelEnabled ''
        echo 'FAIL: legacy Nix channels are enabled' >&2
        exit 1
      ''}
      ${lib.optionalString hasLegacyChannelPath ''
        echo 'FAIL: NIX_PATH contains the legacy root channel path' >&2
        exit 1
      ''}
      echo 'OK: legacy Nix channels and their search path are disabled'
      touch $out
    '';

  assertPowerPolicy =
    name: hostKind: expectPolicy:
    let
      result = nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.operating-system
          {
            system.stateVersion = "25.05";
            boot.loader.systemd-boot.enable = true;
            keystone.os = {
              enable = true;
              inherit hostKind;
              power.suspendThenHibernate.enable = true;
              storage = {
                type = "lvm";
                devices = [ "/dev/vda" ];
                swap.size = "16G";
                hibernate.enable = true;
              };
              users.testuser = {
                fullName = "Test User";
                initialPassword = "testpass";
                admin = true;
              };
            };
            fileSystems."/" = {
              device = lib.mkForce "/dev/pool/root";
              fsType = lib.mkForce "ext4";
            };
          }
        ];
      };
      sleepSettings = result.config.systemd.sleep.settings.Sleep;
      hasPolicy = sleepSettings ? HibernateDelaySec;
      marker = result.config.environment.etc ? "keystone/suspend-then-hibernate";
      valid =
        hasPolicy == expectPolicy
        && marker == expectPolicy
        && (!expectPolicy || sleepSettings.HibernateDelaySec == "2h")
        && (!expectPolicy || sleepSettings.HibernateOnACPower == false);
    in
    pkgs.runCommand "power-policy-${name}" { } ''
      ${lib.optionalString (!valid) ''
        echo 'FAIL: ${name}: unexpected suspend-then-hibernate policy' >&2
        exit 1
      ''}
      echo "OK: ${name}: policy=${if expectPolicy then "enabled" else "disabled"}"
      touch $out
    '';

  assertLvmHibernateLayout =
    let
      result = (import "${pkgs.path}/nixos/lib/eval-config.nix") {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.operating-system
          {
            system.stateVersion = "25.05";
            boot.loader.systemd-boot.enable = true;
            keystone.os = {
              enable = true;
              storage = {
                type = "lvm";
                devices = [ "/dev/vda" ];
                swap.size = "16G";
                hibernate.enable = true;
              };
              users.testuser = {
                fullName = "Test User";
                initialPassword = "testpass";
                admin = true;
              };
            };
          }
        ];
      };
      luksNames = builtins.attrNames result.config.boot.initrd.luks.devices;
      resumeDevice = result.config.boot.resumeDevice;
    in
    pkgs.runCommand "lvm-hibernate-layout" { } ''
      ${lib.optionalString (luksNames != [ "cryptroot" ]) ''
        echo 'FAIL: expected one LUKS device named cryptroot, got ${builtins.toJSON luksNames}' >&2
        exit 1
      ''}
      ${lib.optionalString (resumeDevice != "/dev/pool/swap") ''
        echo 'FAIL: expected resume device /dev/pool/swap, got ${resumeDevice}' >&2
        exit 1
      ''}
      echo "OK: one LUKS device contains the root and resume LVs"
      touch $out
    '';

  # The recovery specialisation clears the unlock hints on every initrd LUKS
  # target, so assert it for both storage backends: each names its container
  # differently (lvm -> cryptroot, zfs -> credstore) and the module derives
  # the names from the initrd table rather than from the backend.
  assertPassphraseRecovery =
    let
      mkCase =
        {
          type,
          luksName,
        }:
        let
          config' =
            (nixosSystem {
              system = "x86_64-linux";
              modules = [
                self.nixosModules.operating-system
                {
                  system.stateVersion = "25.05";
                  keystone = {
                    os = {
                      enable = true;
                      storage = {
                        inherit type;
                        devices = [ "/dev/vda" ];
                      };
                      tpm.enable = true;
                    };
                    # Recorded enrollment state is what makes hardware-keys
                    # contribute fido2-device=auto, the cross-module hint the
                    # specialisation has to clear.
                    hardwareKeys.yubi-test = "12345";
                    hardwareKeyLuksTargets = [ luksName ];
                    hardwareKeyState.luks.${luksName} = {
                      uuid = "00000000-0000-0000-0000-000000000001";
                      enrollments.yubi-test.token = 1;
                    };
                  };
                }
              ];
            }).config;
          luksOptions = cfg: cfg.boot.initrd.luks.devices.${luksName}.crypttabExtraOpts;
          normalOptions = luksOptions config';
          recoveryOptions = luksOptions config'.specialisation.passphrase-recovery.configuration;
        in
        # Checking fido2-device=auto specifically: it comes from
        # modules/hardware-keys.nix via mkAfter, so it proves the recovery
        # entry clears hints contributed by other modules. The exact tpm2
        # options and their merge order are implementation detail.
        lib.optionalString (!lib.elem "fido2-device=auto" normalOptions) ''
          echo 'FAIL: ${type} normal boot lost its automatic unlock options: ${builtins.toJSON normalOptions}' >&2
          exit 1
        ''
        + lib.optionalString (recoveryOptions != [ ]) ''
          echo 'FAIL: ${type} recovery boot has automatic unlock options: ${builtins.toJSON recoveryOptions}' >&2
          exit 1
        '';
    in
    pkgs.runCommand "passphrase-recovery-specialisation" { } ''
      ${mkCase {
        type = "lvm";
        luksName = "cryptroot";
      }}
      ${mkCase {
        type = "zfs";
        luksName = "credstore";
      }}
      echo "OK: normal boot uses hardware unlock and recovery boot uses the passphrase"
      touch $out
    '';

  # Minimal storage + fs so the OS module evaluates far enough to populate
  # users and assertions. Shared by every admin-flag test below.
  adminBase = {
    keystone.os = {
      enable = true;
      storage = {
        type = "zfs";
        devices = [ "/dev/vda" ];
      };
    };
    networking.hostId = "deadbeef";
    fileSystems."/" = {
      device = lib.mkForce "rpool/crypt/system";
      fsType = lib.mkForce "zfs";
    };
  };

  # Evaluate a module set and assert the named user's group membership.
  # The assertion is scoped to the `includes`/`excludes` lists — the user
  # MUST have every group in `includes` and MUST NOT have any group in
  # `excludes`, but MAY have additional groups not listed in either.
  # Pins _autoUserGroups sink wiring from the capability modules.
  assertUserGroups =
    name: username: includes: excludes: modules:
    let
      result = (import "${pkgs.path}/nixos/lib/eval-config.nix") {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.operating-system
          {
            system.stateVersion = "25.05";
            boot.loader.systemd-boot.enable = true;
          }
        ]
        ++ modules;
      };
      userGroups = result.config.users.users.${username}.extraGroups;
      missing = builtins.filter (g: !(builtins.elem g userGroups)) includes;
      unexpected = builtins.filter (g: builtins.elem g userGroups) excludes;
      ok = missing == [ ] && unexpected == [ ];
      groupsJson = builtins.toJSON userGroups;
      missingJson = builtins.toJSON missing;
      unexpectedJson = builtins.toJSON unexpected;
    in
    pkgs.runCommand "user-groups-${name}" { } ''
      ${
        if ok then
          ''
            echo "OK: ${name}: ${username} groups = ${groupsJson}"
          ''
        else
          ''
            echo "FAIL: ${name}: ${username} groups = ${groupsJson}" >&2
            echo "  missing: ${missingJson}" >&2
            echo "  unexpected: ${unexpectedJson}" >&2
            exit 1
          ''
      }
      touch $out
    '';

  assertHypervisorMode =
    name:
    {
      server,
      client ? null,
      expectedClient,
      expectedLocalAutoconnect ? false,
    }:
    let
      result = (import "${pkgs.path}/nixos/lib/eval-config.nix") {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.operating-system
          self.nixosModules.desktop
          {
            system.stateVersion = "25.05";
            boot.loader.systemd-boot.enable = true;
            keystone.desktop.enable = true;
            keystone.os = {
              enable = true;
              storage = {
                type = "lvm";
                devices = [ "/dev/vda" ];
              };
              hypervisor = {
                enable = server;
                defaultUri = "qemu+ssh://admin@ocean/system";
                connections = [
                  "qemu:///system"
                  "qemu+ssh://admin@workstation/system"
                ];
              }
              // lib.optionalAttrs (client != null) { client.enable = client; };
              users.testuser = {
                fullName = "Test User";
                initialPassword = "testpass";
                admin = true;
                desktop.enable = true;
              };
            };
            fileSystems."/" = {
              device = lib.mkForce "/dev/pool/root";
              fsType = lib.mkForce "ext4";
            };
          }
        ];
      };
      serviceNames = builtins.attrNames result.config.systemd.services;
      socketNames = builtins.attrNames result.config.systemd.sockets;
      hasLibvirtUnits = builtins.any (unit: lib.hasPrefix "libvirt" unit) (serviceNames ++ socketNames);
      actualServer = result.config.virtualisation.libvirtd.enable;
      actualClient = result.config.programs.virt-manager.enable;
      connections =
        result.config.home-manager.users.testuser.dconf.settings."org/virt-manager/virt-manager/connections";
      actualAutoconnect = if expectedClient then toString connections.autoconnect else "";
      ok =
        actualServer == server
        && hasLibvirtUnits == server
        && actualClient == expectedClient
        && (!expectedClient || lib.hasInfix "qemu+ssh://admin@ocean/system" actualAutoconnect)
        && (!expectedClient || lib.hasInfix "qemu+ssh://admin@workstation/system" actualAutoconnect)
        && lib.hasInfix "qemu:///system" actualAutoconnect == expectedLocalAutoconnect;
    in
    pkgs.runCommand "hypervisor-${name}" { } ''
      ${lib.optionalString (!ok) ''
        echo "FAIL: hypervisor ${name} mode did not match its expected state" >&2
        echo 'server=${builtins.toJSON actualServer}' >&2
        echo 'client=${builtins.toJSON actualClient}' >&2
        echo 'libvirtUnits=${builtins.toJSON hasLibvirtUnits}' >&2
        echo 'autoconnect=${builtins.toJSON actualAutoconnect}' >&2
        exit 1
      ''}
      echo "OK: hypervisor ${name} mode"
      touch $out
    '';

  assertMdnsOwnership =
    name:
    {
      avahiEnable,
      resolvedEnable,
      networkManagerEnable,
    }:
    let
      result = nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.operating-system
          adminBase
          {
            system.stateVersion = "25.05";
            boot.loader.systemd-boot.enable = true;
            keystone.os.services = {
              avahi.enable = avahiEnable;
              resolved.enable = resolvedEnable;
            };
            networking.networkmanager.enable = networkManagerEnable;
          }
        ];
      };
      actualAvahi = result.config.services.avahi.enable;
      actualResolved = result.config.services.resolved.enable;
      actualResolvedMdns = result.config.services.resolved.settings.Resolve.MulticastDNS;
      actualNetworkManagerDns = result.config.networking.networkmanager.dns;
      expectedNetworkManagerDns = if resolvedEnable then "systemd-resolved" else "default";
      hasNetworkManagerConfig = builtins.hasAttr "NetworkManager/NetworkManager.conf" result.config.environment.etc;
      networkManagerConfig =
        if hasNetworkManagerConfig then
          result.config.environment.etc."NetworkManager/NetworkManager.conf".source
        else
          null;
      ok =
        actualAvahi == avahiEnable
        && actualResolved == resolvedEnable
        && actualResolvedMdns == false
        && actualNetworkManagerDns == expectedNetworkManagerDns
        && hasNetworkManagerConfig == networkManagerEnable;
    in
    pkgs.runCommand "mdns-ownership-${name}" { } ''
      ${lib.optionalString (!ok) ''
        echo "FAIL: mDNS ownership ${name} did not match its expected state" >&2
        echo 'avahi=${builtins.toJSON actualAvahi}' >&2
        echo 'resolved=${builtins.toJSON actualResolved}' >&2
        echo 'resolvedMdns=${builtins.toJSON actualResolvedMdns}' >&2
        echo 'networkManagerDns=${builtins.toJSON actualNetworkManagerDns}' >&2
        echo 'hasNetworkManagerConfig=${builtins.toJSON hasNetworkManagerConfig}' >&2
        exit 1
      ''}
      ${lib.optionalString networkManagerEnable ''
        if ! grep -Fqx 'connection.mdns=0' ${networkManagerConfig}; then
          echo 'FAIL: rendered NetworkManager [connection] policy lacks connection.mdns=0' >&2
          cat ${networkManagerConfig} >&2
          exit 1
        fi
        if grep -Fqx 'mdns=0' ${networkManagerConfig}; then
          echo 'FAIL: rendered NetworkManager policy contains the ineffective unqualified mdns key' >&2
          cat ${networkManagerConfig} >&2
          exit 1
        fi
      ''}
      echo "OK: mDNS ownership ${name}"
      touch $out
    '';

  assertReleaseBootstrap =
    name: enable:
    let
      result = nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.operating-system
          adminBase
          {
            system.stateVersion = "25.05";
            boot.loader.systemd-boot.enable = true;
            keystone.os.releaseBootstrap.enable = enable;
          }
        ];
      };
      root = result.config.users.users.root;
      ssh = result.config.services.openssh.settings;
      passwordIsBootstrap = (root.initialPassword or null) == "changeme";
      passwordSshEnabled = ssh.PermitRootLogin == "yes" && ssh.PasswordAuthentication;
      ok =
        if enable then
          passwordIsBootstrap && passwordSshEnabled
        else
          !passwordIsBootstrap && !passwordSshEnabled;
    in
    pkgs.runCommand "release-bootstrap-${name}" { } ''
      ${lib.optionalString (!ok) ''
        echo "FAIL: release bootstrap ${name} has the wrong root SSH policy" >&2
        exit 1
      ''}
      echo "OK: release bootstrap ${name}"
      touch $out
    '';

  tests = {
    release-bootstrap-enabled = assertReleaseBootstrap "enabled" true;
    release-bootstrap-disabled = assertReleaseBootstrap "disabled" false;
    systemd-boot-console-mode-default = assertConsoleMode "default" "max" [ adminBase ];
    systemd-boot-console-mode-override = assertConsoleMode "override" "keep" [
      adminBase
      { boot.loader.systemd-boot.consoleMode = "keep"; }
    ];
    laptop-power-policy = assertPowerPolicy "laptop" "laptop" true;
    workstation-power-policy = assertPowerPolicy "workstation" "workstation" false;
    server-power-policy = assertPowerPolicy "server" "server" false;
    mdns-ownership-enabled = assertMdnsOwnership "enabled" {
      avahiEnable = true;
      resolvedEnable = true;
      networkManagerEnable = true;
    };
    mdns-ownership-disabled = assertMdnsOwnership "disabled" {
      avahiEnable = false;
      resolvedEnable = false;
      networkManagerEnable = false;
    };
    zfs-power-policy-rejected =
      assertHasFailingAssertion "zfs-power-policy" "Suspend-then-hibernate requires non-ZFS LVM storage."
        [
          adminBase
          {
            keystone.os = {
              hostKind = "laptop";
              power.suspendThenHibernate.enable = true;
              users.alice = {
                fullName = "Alice";
                initialPassword = "pw";
                admin = true;
              };
            };
          }
        ];
    hypervisor-server = assertHypervisorMode "server" {
      server = true;
      expectedClient = true;
      expectedLocalAutoconnect = true;
    };

    hypervisor-client-only = assertHypervisorMode "client-only" {
      server = false;
      client = true;
      expectedClient = true;
    };

    hypervisor-disabled = assertHypervisorMode "disabled" {
      server = false;
      client = false;
      expectedClient = false;
    };

    minimal-zfs = eval "minimal-zfs" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "zfs";
            devices = [ "/dev/vda" ];
          };
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
            admin = true;
          };
        };
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    full-zfs = eval "full-zfs" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "zfs";
            devices = [
              "/dev/vda"
              "/dev/vdb"
            ];
            mode = "mirror";
            swap.size = "16G";
            zfs = {
              compression = "zstd";
              arcMax = "8G";
              autoScrub = true;
            };
          };
          secureBoot.enable = true;
          tpm = {
            enable = true;
            pcrs = [
              1
              7
            ];
          };
          remoteUnlock = {
            enable = true;
            authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest123 test@localhost" ];
            port = 2222;
          };
          ssh.enable = true;
          users.admin = {
            fullName = "Admin User";
            email = "admin@example.com";
            admin = true;
            initialPassword = "adminpass";
            terminal.enable = true;
            zfs.quota = "100G";
          };
        };
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    lvm-simple = eval "lvm-simple" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "lvm";
            devices = [ "/dev/vda" ];
          };
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
            admin = true;
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/pool/root";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    lvm-hibernate = eval "lvm-hibernate" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "lvm";
            devices = [ "/dev/vda" ];
            swap.size = "16G";
            hibernate.enable = true;
          };
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
            admin = true;
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/pool/root";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Experimental zram module: defaults pin zstd/50%/swappiness=150.
    zram-experimental =
      let
        evalZram =
          extraModule:
          (import "${pkgs.path}/nixos/lib/eval-config.nix") {
            system = "x86_64-linux";
            modules = [
              self.nixosModules.operating-system
              {
                system.stateVersion = "25.05";
                boot.loader.systemd-boot.enable = true;
                keystone.os = {
                  enable = true;
                  storage = {
                    type = "lvm";
                    devices = [ "/dev/vda" ];
                  };
                  users.testuser = {
                    fullName = "Test User";
                    initialPassword = "testpass";
                    admin = true;
                  };
                };
                fileSystems."/" = {
                  device = lib.mkForce "/dev/pool/root";
                  fsType = lib.mkForce "ext4";
                };
              }
            ]
            ++ [ extraModule ];
          };
        result = evalZram { keystone.os.zram.enable = true; };
        defaultResult = evalZram { keystone.experimental = true; };
        z = result.config.zramSwap;
        defaultZram = defaultResult.config.zramSwap;
        swappiness = result.config.boot.kernel.sysctl."vm.swappiness";
      in
      pkgs.runCommand "zram-experimental" { } ''
        fail=0
        ${lib.optionalString defaultZram.enable ''
          echo "FAIL: zramSwap.enable expected false by default" >&2
          fail=1
        ''}
        ${lib.optionalString (!z.enable) ''
          echo "FAIL: zramSwap.enable expected true" >&2
          fail=1
        ''}
        if [ "${z.algorithm}" != "zstd" ]; then
          echo "FAIL: zramSwap.algorithm expected zstd, got ${z.algorithm}" >&2
          fail=1
        fi
        if [ "${toString z.memoryPercent}" != "50" ]; then
          echo "FAIL: zramSwap.memoryPercent expected 50, got ${toString z.memoryPercent}" >&2
          fail=1
        fi
        if [ "${toString swappiness}" != "150" ]; then
          echo "FAIL: vm.swappiness expected 150, got ${toString swappiness}" >&2
          fail=1
        fi
        if [ "$fail" -ne 0 ]; then exit 1; fi
        echo "OK: zram defaults pinned (zstd, 50%, swappiness=150)"
        touch $out
      '';

    journal-remote-server = eval "journal-remote-server" [
      {
        keystone = {
          domain = "example.com";
          hosts.ocean = {
            hostname = "journal-server";
            role = "server";
            journalRemote = true;
          };
          os = {
            enable = true;
            storage = {
              type = "zfs";
              devices = [ "/dev/vda" ];
            };
            users.testuser = {
              fullName = "Test User";
              initialPassword = "testpass";
              admin = true;
            };
          };
        };
        networking.hostName = "journal-server";
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    journal-remote-client = eval "journal-remote-client" [
      {
        keystone = {
          domain = "example.com";
          hosts.ocean = {
            hostname = "ocean";
            role = "server";
            journalRemote = true;
          };
          os = {
            enable = true;
            storage = {
              type = "zfs";
              devices = [ "/dev/vda" ];
            };
            journalRemote.serverHost = "ocean";
            users.testuser = {
              fullName = "Test User";
              initialPassword = "testpass";
              admin = true;
            };
          };
        };
        networking.hostName = "workstation";
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    journal-remote-client-no-domain = eval "journal-remote-client-no-domain" [
      {
        keystone = {
          hosts.ocean = {
            hostname = "ocean";
            role = "server";
            journalRemote = true;
          };
          os = {
            enable = true;
            storage = {
              type = "zfs";
              devices = [ "/dev/vda" ];
            };
            journalRemote.serverHost = "ocean";
            users.testuser = {
              fullName = "Test User";
              initialPassword = "testpass";
              admin = true;
            };
          };
        };
        networking.hostName = "workstation";
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    # ZFS backup sender — host with backups declared in keystone.hosts
    zfs-backup-sender = eval "zfs-backup-sender" [
      {
        keystone.hosts = {
          workstation = {
            hostname = "workstation";
            role = "client";
            hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest123 workstation";
            zfs = {
              backups.rpool.targets = [
                "ocean:ocean"
                "maia:lake"
              ];
            };
          };
          ocean = {
            hostname = "ocean";
            role = "server";
            sshTarget = "ocean.ts";
            hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcean ocean";
          };
          maia = {
            hostname = "maia";
            role = "server";
            sshTarget = "maia.ts";
            hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMaia maia";
          };
        };
        keystone.os = {
          enable = true;
          storage = {
            type = "zfs";
            devices = [ "/dev/vda" ];
          };
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
            admin = true;
          };
        };
        networking.hostName = "workstation";
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    # ZFS backup receiver — host targeted by another host's backups
    zfs-backup-receiver = eval "zfs-backup-receiver" [
      {
        keystone.hosts = {
          workstation = {
            hostname = "workstation";
            role = "client";
            hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest123 workstation";
            zfs = {
              backups.rpool.targets = [
                "ocean:ocean"
              ];
            };
          };
          ocean = {
            hostname = "ocean";
            role = "server";
            hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcean ocean";
          };
        };
        keystone.os = {
          enable = true;
          storage = {
            type = "zfs";
            devices = [ "/dev/vda" ];
          };
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
            admin = true;
          };
        };
        networking.hostName = "ocean";
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/crypt/system";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    # Single admin flag → adminUsername derives to that user.
    admin-username-single-admin = assertAdminUsername "single-admin" "alice" [
      adminBase
      {
        keystone.os.users.alice = {
          fullName = "Alice";
          initialPassword = "pw";
          admin = true;
        };
        keystone.os.users.bob = {
          fullName = "Bob";
          initialPassword = "pw";
        };
      }
    ];

    # Explicit adminUsername matching the admin flag → valid.
    admin-username-explicit-matches = assertAdminUsername "explicit-matches" "alice" [
      adminBase
      {
        keystone.os.adminUsername = "alice";
        keystone.os.users.alice = {
          fullName = "Alice";
          initialPassword = "pw";
          admin = true;
        };
      }
    ];

    # No admin-flagged user → "requires an administrator" assertion fires.
    admin-username-no-admin-fails = assertHasFailingAssertion "no-admin" "requires an administrator" [
      adminBase
      {
        keystone.os.users.alice = {
          fullName = "Alice";
          initialPassword = "pw";
        };
      }
    ];

    # Two admin-flagged users → "Multiple users are flagged" assertion fires.
    admin-username-multi-admin-fails =
      assertHasFailingAssertion "multi-admin" "Multiple users are flagged"
        [
          adminBase
          {
            keystone.os.users.alice = {
              fullName = "Alice";
              initialPassword = "pw";
              admin = true;
            };
            keystone.os.users.bob = {
              fullName = "Bob";
              initialPassword = "pw";
              admin = true;
            };
          }
        ];

    # Explicit adminUsername disagreeing with the admin flag → mismatch assertion fires.
    admin-username-mismatch-fails = assertHasFailingAssertion "mismatch" "not flagged admin = true" [
      adminBase
      {
        keystone.os.adminUsername = "bob";
        keystone.os.users.alice = {
          fullName = "Alice";
          initialPassword = "pw";
          admin = true;
        };
      }
    ];

    # --- _autoUserGroups sink: capability-driven admin groups ---
    #
    # Admin with containers.enable (default on) gets podman. dialout and
    # media are admin-auto even with no capability flags, because they
    # land in adminOnly unconditionally.
    auto-groups-admin-containers =
      assertUserGroups "admin-containers" "alice"
        [
          "wheel"
          "podman"
          "dialout"
          "media"
          "zfs"
        ]
        [ ]
        [
          adminBase
          {
            keystone.os.users.alice = {
              fullName = "Alice";
              initialPassword = "pw";
              admin = true;
            };
          }
        ];

    # Admin with hypervisor.enable gets libvirtd in addition to the
    # unconditional admin groups.
    auto-groups-admin-hypervisor =
      assertUserGroups "admin-hypervisor" "alice"
        [
          "wheel"
          "libvirtd"
          "podman"
          "dialout"
          "media"
          "zfs"
        ]
        [ ]
        [
          adminBase
          {
            keystone.os.hypervisor.enable = true;
            keystone.os.users.alice = {
              fullName = "Alice";
              initialPassword = "pw";
              admin = true;
            };
          }
        ];

    # Non-admin wheel user does NOT inherit admin-scoped groups. They
    # get wheel (because they declared it) and zfs (allUsers when ZFS
    # storage is in use) — nothing else. Hardware/service access
    # follows admin = true, not sudo.
    auto-groups-non-admin-wheel =
      assertUserGroups "non-admin-wheel" "bob" [ "wheel" "zfs" ]
        [
          "podman"
          "libvirtd"
          "dialout"
          "media"
        ]
        [
          adminBase
          {
            keystone.os.hypervisor.enable = true;
            keystone.os.users.alice = {
              fullName = "Alice";
              initialPassword = "pw";
              admin = true;
            };
            keystone.os.users.bob = {
              fullName = "Bob";
              initialPassword = "pw";
              extraGroups = [ "wheel" ];
            };
          }
        ];

    # TODO: add a shadow-warning regression test. Reading
    # result.config.warnings from an eval-config result cascades into
    # full home-manager evaluation (systemd.services.home-manager-*
    # → claudeJsonConfig.data), which fails
    # under the local keystone-conventions derivation invalidation
    # issue. The shadow-warning code itself is simple and covered by
    # the sink wiring tests; wire the warning test once the cascade
    # is disentangled or once we can emit warnings via a narrower
    # option.

    # Containers disabled → admin does NOT get podman, but still gets
    # the unconditional admin groups (dialout, media).
    auto-groups-admin-no-containers =
      assertUserGroups "admin-no-containers" "alice"
        [
          "wheel"
          "dialout"
          "media"
          "zfs"
        ]
        [ "podman" ]
        [
          adminBase
          {
            keystone.os.containers.enable = false;
            keystone.os.users.alice = {
              fullName = "Alice";
              initialPassword = "pw";
              admin = true;
            };
          }
        ];
  };
in
pkgs.runCommand "test-os-evaluation"
  {
    nativeBuildInputs = (lib.attrValues tests) ++ [
      assertLvmHibernateLayout
      assertKernelPolicy
      assertNixChannelPolicy
      assertPassphraseRecovery
    ];
  }
  ''
    echo "OS module evaluation tests"
    echo "========================="
    echo ""
    echo "This test verifies that the OS module options are correctly defined"
    echo "and can be evaluated with various configurations."
    echo ""
    echo "Configurations tested:"
    echo "  - minimal-zfs: Minimal ZFS setup"
    echo "  - full-zfs: Full ZFS with all options"
    echo "  - lvm-simple: LVM-backed ext4 setup"
    echo "  - lvm-hibernate: LVM-backed ext4 with hibernation enabled"
    echo "  - kernel-policy: Linux 7.1 with a buildable OpenZFS 2.4 module"
    echo "  - nix-channel-policy: Legacy Nix channels and their search path are disabled"
    echo "  - passphrase-recovery: Recovery boot omits FIDO2 and TPM unlock options"
    echo "  - zram-experimental: experimental keystone.os.zram defaults"
    echo "  - journal-remote-server: Journal collection server (HTTPS via nginx)"
    echo "  - journal-remote-client: Journal upload client (HTTPS via nginx)"
    echo "  - journal-remote-client-no-domain: Journal upload client (HTTP fallback)"
    echo ""
    echo "All configurations evaluated successfully!"
    touch $out
  ''
