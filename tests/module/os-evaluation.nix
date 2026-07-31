# OS module evaluation test
#
# This test verifies that the OS module evaluates correctly with various
# configuration options. It doesn't boot a VM (which would require disko
# to actually partition disks), but validates the module's NixOS options
# and configuration generation.
#
# Build: nix build .#test-os-evaluation
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

  tests = {
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

    ext4-simple = eval "ext4-simple" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
          };
          users.testuser = {
            fullName = "Test User";
            initialPassword = "testpass";
            admin = true;
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    ext4-hibernate = eval "ext4-hibernate" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "ext4";
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
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Experimental zram module: defaults pin zstd/50%/swappiness=150.
    zram-experimental =
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
                  type = "ext4";
                  devices = [ "/dev/vda" ];
                };
                zram.enable = true;
                users.testuser = {
                  fullName = "Test User";
                  initialPassword = "testpass";
                  admin = true;
                };
              };
              fileSystems."/" = {
                device = lib.mkForce "/dev/vda2";
                fsType = lib.mkForce "ext4";
              };
            }
          ];
        };
        z = result.config.zramSwap;
        swappiness = result.config.boot.kernel.sysctl."vm.swappiness";
      in
      pkgs.runCommand "zram-experimental" { } ''
        fail=0
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
    # → claudeJsonConfig.data → deepwork-library-jobs), which fails
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
    nativeBuildInputs = lib.attrValues tests;
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
    echo "  - ext4-simple: Simple ext4 setup"
    echo "  - ext4-hibernate: ext4 with hibernation enabled"
    echo "  - zram-experimental: experimental keystone.os.zram defaults"
    echo "  - journal-remote-server: Journal collection server (HTTPS via nginx)"
    echo "  - journal-remote-client: Journal upload client (HTTPS via nginx)"
    echo "  - journal-remote-client-no-domain: Journal upload client (HTTP fallback)"
    echo ""
    echo "All configurations evaluated successfully!"
    touch $out
  ''
