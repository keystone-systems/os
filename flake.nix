{
  description = "Self-sovereign NixOS infrastructure platform";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    terminal = {
      url = "git+ssh://forgejo@git.ncrmro.com:2222/ks.systems/terminal.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.crane.follows = "crane";
    };
    # Desktop environments (Hyprland session wiring, scripts, menus, theming,
    # dotfile templates). The desktop flake is the single owner of the
    # compositor source and package — deliberately no Hyprland input here.
    desktop = {
      url = "git+ssh://forgejo@git.ncrmro.com:2222/ks.systems/desktop.git";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.terminal.follows = "terminal";
    };
    browser-previews = {
      url = "github:nix-community/browser-previews";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Desktop tools
    # Pinned to stable release tag — tracking `main` ships dev builds
    # which have segfaulted in real use (2026-06-05 SIGSEGV killed all surfaces).
    ghostty.url = "github:ghostty-org/ghostty?ref=v1.3.1";
    yazi = {
      url = "github:sxyazi/yazi";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secret management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NixOS tools
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    lfs-s3-src = {
      url = "github:nicolas-graves/lfs-s3/0.2.1";
      flake = false;
    };

    # Rust build tooling — splits dependency builds for fast incremental rebuilds
    crane.url = "github:ipetkov/crane";

  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
      disko,
      home-manager,
      lanzaboote,
      terminal,
      desktop,
      browser-previews,
      ghostty,
      yazi,
      sops-nix,
      nix-index-database,
      nixos-hardware,
      lfs-s3-src,
      ...
    }:
    let
      # Create inputs attrset for keystone modules (named keystoneInputs to avoid
      # shadowing when consumed by other flakes that pass their own `inputs`)
      keystoneInputs = {
        inherit
          nixpkgs
          disko
          lanzaboote
          home-manager
          terminal
          browser-previews
          sops-nix
          nix-index-database
          nixos-hardware
          ;
        self = self;
        keystoneOverlay = self.overlays.default;
      };

      # Shared ISO installer module list — used by both nixosConfigurations.keystoneIso
      # and lib.mkInstallerIso to avoid maintaining parallel module wiring.
      installerModules = system: [
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        ./modules/iso-installer.nix
        {
          # Force kernel 6.12 — must be set here to override minimal CD default
          boot.kernelPackages = nixpkgs.lib.mkForce nixpkgs.legacyPackages.${system}.linuxPackages_6_12;
          # Apply keystone overlay so crane-built packages resolve inside the installer
          nixpkgs.overlays = [ self.overlays.default ];
        }
      ];

      templateLib = import ./lib/templates.nix {
        inherit
          self
          nixpkgs
          home-manager
          terminal
          ;
        lib = nixpkgs.lib;
      };

      fleetSystem = "x86_64-linux";
      fleetPkgs = nixpkgs.legacyPackages.${fleetSystem};
      mkFleet = import ./lib/mk-fleet.nix { inherit nixpkgs; };
      exampleFleet = mkFleet {
        hostsDir = ./examples/hosts;
        baseModules = [ disko.nixosModules.disko ];
        targets = {
          ks-demo-b.machine = {
            sshTarget = "192.168.1.64";
            user = "ncrmro";
          };
          ks-demo-luks.install = { };
        };
      };
    in
    {
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt;

      lib = templateLib // {
        inherit mkFleet;

        # Build an installer ISO with the given SSH keys baked in.
        # Consumer flakes call this instead of duplicating the module wiring.
        mkInstallerIso =
          {
            nixpkgs,
            sshKeys ? [ ],
            system ? "x86_64-linux",
          }:
          (nixpkgs.lib.nixosSystem {
            inherit system;
            modules = installerModules system ++ [
              {
                keystone.installer.sshKeys = sshKeys;
              }
            ];
          }).config.system.build.isoImage;
      };

      # ISO configuration without SSH keys (use lib.mkInstallerIso for keys)
      # Note: Test/dev configurations are in ./tests/flake.nix
      nixosConfigurations = {
        keystoneIso = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = installerModules "x86_64-linux";
        };
      }
      // exampleFleet.nixosConfigurations;

      # Overlay that provides keystone packages
      overlays.default = nixpkgs.lib.composeManyExtensions [
        terminal.overlays.default
        # Desktop packages (write-polkit-theme, hyprpolkitagent,
        # keystone-dpms-wake) moved to ks.systems/desktop; compose its overlay
        # so pkgs.keystone-desktop.* resolves wherever keystone's overlay is
        # applied.
        desktop.overlays.default
        (import ./overlays/default.nix {
          inherit
            self
            crane
            browser-previews
            ghostty
            yazi
            lfs-s3-src
            ;
        })
        # Name-stability aliases: keystone's packages export (flake.nix
        # packages.x86_64-linux) and downstream pkgs.keystone.* references
        # keep resolving after the move to ks.systems/desktop.
        (final: prev: {
          keystone = prev.keystone // {
            write-polkit-theme = final.keystone-desktop.write-polkit-theme;
            hyprpolkitagent = final.keystone-desktop.hyprpolkitagent;
          };
        })
      ];

      # Export Keystone modules for use in other flakes
      nixosModules = {
        # Fleet/bootstrap modules from the KS OS v1 rebuild.
        default = ./modules/default.nix;
        diskoVmToolsCompat = ./modules/disko-vm-tools-compat.nix;

        # Shared domain option (keystone.domain) — used by OS agents and server services
        domain = ./modules/domain.nix;

        # Shared service registry (keystone.services.*) — declares which host runs each service
        services = ./modules/services.nix;

        # Shared host registry (keystone.hosts) — host identity and connection metadata
        hosts = ./modules/hosts.nix;

        # Experimental feature flag (keystone.experimental)
        experimental = terminal.lib.sharedModules.experimental;

        # Update channel selector (keystone.update.channel) — stable | unstable
        update = terminal.lib.sharedModules.update;

        # Managed repo registry + development mode toggle (keystone.repos, keystone.development)
        repos = terminal.lib.sharedModules.repos;

        # Core OS module - storage, secure boot, TPM, remote unlock, users, services
        # Pass flake inputs to installer via dedicated option — NOT _module.args,
        # which would conflict with the desktop module's identical definition.
        # Only installer.nix needs keystoneInputs at the NixOS level; all other
        # consumers are in the desktop tree or inside the installer's nested eval.
        operating-system = {
          imports = [
            home-manager.nixosModules.home-manager
            disko.nixosModules.disko
            lanzaboote.nixosModules.lanzaboote
            sops-nix.nixosModules.sops
            ./modules/domain.nix
            ./modules/services.nix
            ./modules/hosts.nix
            terminal.lib.sharedModules.experimental
            terminal.lib.sharedModules.repos
            terminal.lib.sharedModules.update
            terminal.lib.sharedModules.system-flake
            ./modules/os
            ./modules/installer.nix
          ];
          keystone.os.installer._keystoneInputs = keystoneInputs;
          _module.args.terminalSharedModules = terminal.lib.sharedModules;
          # Auto-populate keystone.repos from flake inputs with discoverable URLs.
          # Only pass inputs that represent managed repos — not all upstream dependencies.
          keystone._repoInputs = {
            keystone = self;
            inherit terminal desktop;
          };
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            sharedModules = [
              terminal.homeModules.default
              ./modules/notes/core.nix
            ];
          };
        };

        # Desktop module - re-export of ks.systems/desktop plus keystone glue
        # (which-user default, resolved routing, terminal/experimental wiring).
        # The keystone.desktop.* option paths are preserved verbatim by the
        # desktop flake.
        desktop = {
          imports = [
            desktop.nixosModules.default
            ./modules/desktop/keystone-glue.nix
          ];
        };

        # Server module - VPN, monitoring, mail, and optional services
        server = {
          imports = [
            ./modules/domain.nix
            ./modules/services.nix
            # Secrets interface — server services resolve credential paths
            # through keystone.secrets.provided (its backend defines sops.*,
            # so the sops-nix module must come along).
            sops-nix.nixosModules.sops
            ./modules/secrets.nix
            ./modules/server
          ];
        };

        # ISO installer module
        isoInstaller = ./modules/iso-installer.nix;

        # SSH public key registry — single source of truth for all keys
        keys = ./modules/keys.nix;

        # Hardware key module - FIDO2/YubiKey for GPG/SSH agent
        # Imports keys.nix since rootKeys references keystone.keys
        hardwareKey = {
          imports = [
            ./modules/keys.nix
            ./modules/os/hardware-key.nix
          ];
        };

        # Headscale DNS import — consume server DNS records on headscale host
        headscale-dns = ./modules/server/headscale/dns-import.nix;
        headscale-acl = ./modules/server/headscale/acl-import.nix;
      };

      # Export home-manager modules (homeModules is the standard flake output name)
      homeModules = {
        # Plain re-export of ks.systems/desktop's HM module. That flake's
        # wrapper is the SOLE importer of walker's HM module — do not import
        # walker here or downstream, or `programs.walker.elephant` is declared
        # twice.
        desktop = desktop.homeModules.default;
        notes = {
          imports = [
            terminal.lib.sharedModules.experimental
            ./modules/notes/core.nix
          ];
        };
      };

      # Focused flake checks — run via `nix flake check` and CI.
      # Repo-wide nixfmt and shellcheck live in pre-commit and dedicated CI jobs.
      #
      # CI runs check-* groups as parallel matrix jobs with per-group path
      # filtering. Individual checks remain available for local use:
      #   nix build .#checks.x86_64-linux.agent-evaluation
      checks.x86_64-linux =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          lib = pkgs.lib;
          ksPkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = [ self.overlays.default ];
          };
          ks = ksPkgs.keystone.ks;
          approveExecScript = import ./tests/module/approve-exec-script.nix {
            pkgs = ksPkgs;
            lib = ksPkgs.lib;
          };
          polkitKeystoneApproveCache = import ./tests/module/polkit-keystone-approve-cache.nix {
            inherit pkgs lib;
            self = self;
          };
          polkitUpdateSessionInhibit = import ./tests/module/polkit-update-session-inhibit.nix {
            inherit pkgs lib;
            self = self;
          };
          ksHardwareKeyRegister = import ./tests/module/ks-hardware-key-register.nix {
            pkgs = ksPkgs;
          };
          ksAgeIdentity = import ./tests/module/ks-age-identity.nix {
            pkgs = ksPkgs;
          };
          # --- Individual checks (available for local builds) ---

          osEvaluation = import ./tests/module/os-evaluation.nix {
            inherit pkgs lib;
            self = self;
          };
          espPermissionsEvaluation = import ./tests/module/esp-permissions-evaluation.nix {
            inherit pkgs lib;
            self = self;
          };
          zfsDatasetRegistry = import ./tests/module/zfs-dataset-registry.nix {
            inherit pkgs lib;
            self = self;
          };
          zvolStorageEvaluation = import ./tests/module/zvol-storage-evaluation.nix {
            inherit pkgs lib;
            self = self;
          };
          virtualMachineUnit = import ./tests/unit/virtual-machine.nix { inherit pkgs; };
          ollamaZfsDataset = import ./tests/module/ollama-zfs-dataset.nix {
            inherit pkgs lib;
            self = self;
          };
          zfsDatasetMigration = import ./tests/integration/zfs-dataset-migration.nix {
            inherit pkgs;
            self = self;
          };
          zreplBackupEvaluation = import ./tests/module/zrepl-backup-evaluation.nix {
            inherit pkgs lib;
            self = self;
          };
          deviceBackupsEvaluation = import ./tests/module/device-backups-evaluation.nix {
            inherit pkgs lib;
            self = self;
          };
          cachedUserShareEvaluation = import ./tests/module/cached-user-share-evaluation.nix {
            inherit pkgs lib;
            self = self;
          };
          agentEvaluation = import ./tests/module/agent-evaluation.nix {
            inherit
              pkgs
              lib
              nixpkgs
              sops-nix
              home-manager
              ;
            self = self;
          };
          templateEvaluation = import ./tests/module/template-evaluation.nix {
            inherit
              pkgs
              lib
              nixpkgs
              home-manager
              ;
            self = self;
          };
          notesEvaluation = import ./tests/module/notes-evaluation.nix {
            inherit
              pkgs
              home-manager
              ;
            self = self;
          };
          templateUpdateChannel = import ./tests/module/template-update-channel.nix {
            inherit pkgs lib;
            self = self;
          };
          templateSpecialArgs = import ./tests/module/template-special-args.nix {
            inherit pkgs lib;
            self = self;
          };
          serverEvaluation = import ./tests/module/server-evaluation.nix {
            inherit pkgs lib nixpkgs;
            self = self;
          };
          # Menu shell scripts moved to ks.systems/desktop; these wiring tests
          # exercise the desktop input's copy against keystone's ks CLI and
          # shared modules (cross-repo coupling stays covered here).
          keystoneSecretsMenu = import ./tests/module/keystone-secrets-menu.nix {
            inherit pkgs lib;
            desktopSrc = desktop;
          };
          keystoneFingerprintMenu = import ./tests/module/keystone-fingerprint-menu.nix {
            inherit pkgs lib;
            desktopSrc = desktop;
          };
          keystoneUpdateApproveFlow = import ./tests/module/keystone-update-approve-flow.nix {
            pkgs = ksPkgs;
            inherit lib ks;
          };
          agentctlRegression = import ./tests/module/agentctl-regression.nix {
            inherit pkgs;
          };
          binaryCacheMerge = import ./tests/module/binary-cache-merge.nix {
            inherit pkgs lib self;
          };
          terminalSandboxBinaryCaches = import ./tests/module/terminal-sandbox-binary-caches.nix {
            inherit
              pkgs
              self
              home-manager
              ;
          };
          alloyGracefulShutdown = import ./tests/module/alloy-graceful-shutdown.nix {
            inherit pkgs lib self;
          };
          themeHookTransaction = import ./tests/module/theme-hook-transaction.nix {
            inherit
              pkgs
              lib
              terminal
              home-manager
              ;
          };
          agentTaskLoopHashRegression = import ./tests/module/agent-task-loop-hash-regression.nix {
            inherit pkgs lib;
          };
          agentTaskLoopPingPong = import ./tests/module/agent-task-loop-ping-pong.nix {
            inherit pkgs lib;
          };
          agentTaskLoopInvalidPendingTask = import ./tests/module/agent-task-loop-invalid-pending-task.nix {
            inherit pkgs lib;
          };
          agentRuntimeCoherence = import ./tests/module/agent-runtime-coherence.nix {
            inherit pkgs lib;
          };
          agentQueueMigration = import ./tests/module/agent-queue-migration.nix {
            inherit pkgs lib;
          };
          deepworkRemoval =
            assert !(keystoneInputs ? deepwork);
            assert !(self.packages.x86_64-linux ? deepwork-library-jobs);
            assert !(self.packages.x86_64-linux ? keystone-deepwork-jobs);
            pkgs.runCommand "deepwork-removal" { } ''
              touch "$out"
            '';
        in
        {
          # Individual checks — for local debugging (nix build .#checks.x86_64-linux.<name>)
          os-evaluation = osEvaluation;
          esp-permissions-evaluation = espPermissionsEvaluation;
          zfs-dataset-registry = zfsDatasetRegistry;
          zvol-storage-evaluation = zvolStorageEvaluation;
          virtual-machine-unit = virtualMachineUnit;
          ollama-zfs-dataset = ollamaZfsDataset;
          zfs-dataset-migration = zfsDatasetMigration;
          zrepl-backup-evaluation = zreplBackupEvaluation;
          device-backups-evaluation = deviceBackupsEvaluation;
          cached-user-share-evaluation = cachedUserShareEvaluation;
          agent-evaluation = agentEvaluation;
          template-evaluation = templateEvaluation;
          notes-evaluation = notesEvaluation;
          template-update-channel = templateUpdateChannel;
          template-special-args = templateSpecialArgs;
          server-evaluation = serverEvaluation;
          keystone-secrets-menu = keystoneSecretsMenu;
          keystone-fingerprint-menu = keystoneFingerprintMenu;
          keystone-update-approve-flow = keystoneUpdateApproveFlow;
          approve-exec-script = approveExecScript;
          polkit-keystone-approve-cache = polkitKeystoneApproveCache;
          polkit-update-session-inhibit = polkitUpdateSessionInhibit;
          agentctl-regression = agentctlRegression;
          alloy-graceful-shutdown = alloyGracefulShutdown;
          theme-hook-transaction = themeHookTransaction;
          agent-task-loop-hash-regression = agentTaskLoopHashRegression;
          agent-task-loop-ping-pong = agentTaskLoopPingPong;
          agent-task-loop-invalid-pending-task = agentTaskLoopInvalidPendingTask;
          agent-runtime-coherence = agentRuntimeCoherence;
          agent-queue-migration = agentQueueMigration;
          deepwork-removal = deepworkRemoval;
          ks-hardware-key-register = ksHardwareKeyRegister;
          ks-age-identity = ksAgeIdentity;

          # --- CI groups — parallel matrix jobs via nix-github-actions ---

          # Heavy NixOS module evaluation (single-threaded eval dominates wall time)
          check-eval = pkgs.runCommand "check-eval" { } ''
            mkdir -p "$out"
            ln -s ${osEvaluation} "$out/os-evaluation"
            ln -s ${espPermissionsEvaluation} "$out/esp-permissions-evaluation"
            ln -s ${zvolStorageEvaluation} "$out/zvol-storage-evaluation"
            ln -s ${zfsDatasetRegistry} "$out/zfs-dataset-registry"
            ln -s ${deviceBackupsEvaluation} "$out/device-backups-evaluation"
            ln -s ${ollamaZfsDataset} "$out/ollama-zfs-dataset"
            ln -s ${cachedUserShareEvaluation} "$out/cached-user-share-evaluation"
            ln -s ${agentEvaluation} "$out/agent-evaluation"
            ln -s ${templateEvaluation} "$out/template-evaluation"
            ln -s ${notesEvaluation} "$out/notes-evaluation"
            ln -s ${templateUpdateChannel} "$out/template-update-channel"
            ln -s ${templateSpecialArgs} "$out/template-special-args"
            ln -s ${serverEvaluation} "$out/server-evaluation"
            ln -s ${alloyGracefulShutdown} "$out/alloy-graceful-shutdown"
          '';

          # ks CLI and the privileged-approval path it drives. The CLI itself
          # is a shell script now, so building `ks` runs shellcheck over it.
          check-ks = pkgs.runCommand "check-ks" { } ''
            mkdir -p "$out"
            ln -s ${ks} "$out/ks"
            ln -s ${ksHardwareKeyRegister} "$out/ks-hardware-key-register"
            ln -s ${ksAgeIdentity} "$out/ks-age-identity"
            ln -s ${approveExecScript} "$out/approve-exec-script"
            ln -s ${polkitKeystoneApproveCache} "$out/polkit-keystone-approve-cache"
            ln -s ${polkitUpdateSessionInhibit} "$out/polkit-update-session-inhibit"
          '';

          # Lightweight shell script tests (runCommand, no heavy deps)
          check-scripts = pkgs.runCommand "check-scripts" { } ''
            mkdir -p "$out"
            ln -s ${agentctlRegression} "$out/agentctl-regression"
            ln -s ${keystoneSecretsMenu} "$out/keystone-secrets-menu"
            ln -s ${keystoneFingerprintMenu} "$out/keystone-fingerprint-menu"
            ln -s ${keystoneUpdateApproveFlow} "$out/keystone-update-approve-flow"
            ln -s ${virtualMachineUnit} "$out/virtual-machine-unit"
          '';

          # Agent runtime and miscellaneous module tests
          check-agents = pkgs.runCommand "check-agents" { } ''
            mkdir -p "$out"
            ln -s ${agentTaskLoopHashRegression} "$out/agent-task-loop-hash-regression"
            ln -s ${agentTaskLoopPingPong} "$out/agent-task-loop-ping-pong"
            ln -s ${agentTaskLoopInvalidPendingTask} "$out/agent-task-loop-invalid-pending-task"
            ln -s ${agentRuntimeCoherence} "$out/agent-runtime-coherence"
            ln -s ${agentQueueMigration} "$out/agent-queue-migration"
            ln -s ${deepworkRemoval} "$out/deepwork-removal"
          '';
        }
        // {
          hardware-keys = import ./tests/hardware-keys.nix {
            inherit nixpkgs;
            pkgs = fleetPkgs;
          };
          hardware-key-audit = import ./tests/hardware-key-audit.nix {
            pkgs = fleetPkgs;
          };
        };

      # Packages exported for consumption — sourced from the overlay (single source of truth)
      # Note: Integration/VM tests are in ./tests/flake.nix (separate flake to avoid IFD issues)
      packages.x86_64-linux =
        let
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = [ self.overlays.default ];
          };
          # nixos-anywhere copies the system closure over the legacy `ssh://`
          # store, which handshakes once per path. Measured installing
          # ks-test-delltop over a wired gigabit link, that left the wire ~90%
          # idle: 200 paths/min at 9 MiB/s. Switching the closure copy to
          # `ssh-ng://` gave 678 paths/min at 131 MiB/s -- 3.4x the paths, and
          # enough throughput that the network is finally the bottleneck.
          #
          # The scheme is hardcoded upstream and `--ssh-store-setting` cannot
          # change it, hence the patch. `--no-check-sigs` is not optional:
          # ssh-ng goes through the target's nix daemon, which enforces
          # require-sigs, so a closure containing locally-built paths dies with
          # "cannot add path ... lacks a signature by a trusted key". The
          # legacy path writes directly and never checks.
          #
          # --replace-fail so a nixos-anywhere bump that moves these lines
          # breaks this build loudly, rather than silently reverting to the
          # slow path.
          nixos-anywhere-fast = pkgs.nixos-anywhere.overrideAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              substituteInPlace src/nixos-anywhere.sh \
                --replace-fail 'nixCopy --to "ssh://$sshConnection?remote-store=' \
                               'nixCopy --to "ssh-ng://$sshConnection?remote-store=' \
                --replace-fail '  NIX_SSHOPTS="''${sshArgs[*]}" nix copy \' \
                               '  NIX_SSHOPTS="''${sshArgs[*]}" nix copy --no-check-sigs \'
            '';
          });
          keystone-installer = pkgs.writeShellApplication {
            name = "keystone-installer";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.git
              pkgs.jq
              pkgs.nix
              pkgs.openssh
              pkgs.sshpass
              nixos-anywhere-fast
            ];
            text = builtins.readFile ./bin/keystone-installer;
          };
          keystone-installer-image = pkgs.dockerTools.buildLayeredImage {
            name = "ghcr.io/ncrmro/keystone-installer";
            tag = "v1.0.0-rc.5";
            contents = [
              pkgs.bashInteractive
              pkgs.cacert
              pkgs.coreutils
              pkgs.git
              pkgs.gnugrep
              pkgs.gnused
              pkgs.jq
              pkgs.nix
              pkgs.openssh
              pkgs.sshpass
              keystone-installer
              nixos-anywhere-fast
            ];
            extraCommands = ''
              mkdir -p etc/nix root state tmp workspace
              chmod 1777 tmp
              cat > etc/nix/nix.conf <<'EOF'
              experimental-features = nix-command flakes
              sandbox = false
              extra-substituters = https://ks-systems.cachix.org
              extra-trusted-public-keys = ks-systems.cachix.org-1:Abbd38auzcLIfJUtX7kSD6zdGUU4v831Sb2KfajR5Mo=
              EOF
            '';
            config = {
              Entrypoint = [ "${keystone-installer}/bin/keystone-installer" ];
              WorkingDir = "/workspace";
              Env = [
                "HOME=/root"
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              ];
              Labels = {
                "org.opencontainers.image.source" = "https://github.com/ncrmro/keystone";
                "org.opencontainers.image.version" = "v1.0.0-rc.5";
              };
            };
          };
        in
        (
          {
            inherit
              keystone-installer
              keystone-installer-image
              nixos-anywhere-fast
              ;
            iso = self.lib.mkInstallerIso { inherit nixpkgs; };
            inherit (pkgs.keystone)
              agents-e2e
              repo-sync
              ks
              zellij-tab-name
              write-polkit-theme
              lfs-s3
              slidev
              ;
            keystone-ha-tui-client = pkgs.callPackage ./packages/keystone-ha/tui { };
            hardware-key-audit = pkgs.callPackage ./packages/hardware-key-audit.nix { };
            ks-fleet = pkgs.writeShellApplication {
              name = "ks-fleet";
              runtimeInputs = [
                pkgs.jq
                pkgs.openssh
                pkgs.nixos-rebuild
                # `install` shells out to nixos-anywhere for metal reinstalls.
                nixos-anywhere-fast
                # `install` clones the fleet's seed checkouts into a staging
                # tree handed to nixos-anywhere as --extra-files.
                pkgs.git
              ];
              text = builtins.readFile ./bin/ks-fleet;
            };
          }
          // exampleFleet.packages.${fleetSystem}
        );

      fleetMeta = exampleFleet.fleetMeta;
      apps.${fleetSystem} = exampleFleet.apps.${fleetSystem};

      # Development shell
      devShells.x86_64-linux =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in
        {
          default = pkgs.mkShell {
            name = "keystone-dev";

            # Rust development
            nativeBuildInputs = with pkgs; [
              cargo
              rustc
              rust-analyzer
              clippy
              rustfmt
              pkg-config
            ];

            buildInputs = with pkgs; [
              openssl
            ];

            packages = with pkgs; [
              # Nix tools
              nixfmt
              nil # Nix LSP
              nix-tree
              nvd # Nix version diff

              # VM and deployment tools
              qemu
              libvirt
              virt-viewer
              swtpm
              nix-serve # local binary cache for e2e VM installs

              # General utilities
              jq
              yq-go
              gettext
              bash
              shellcheck
              gh # GitHub CLI
              python3
            ];

            shellHook = ''
              repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
              if [ -n "$repo_root" ]; then
                hook_file="$(git rev-parse --git-path hooks/pre-commit)"
                expected_hook="$repo_root/bin/pre-commit"
                current_hook="$(readlink "$hook_file" 2>/dev/null || true)"

                if [ "$current_hook" != "$expected_hook" ] && [ -x "$expected_hook" ]; then
                  "$expected_hook" --install >/dev/null
                fi
              fi

              echo "🔑 Keystone development shell"
              echo ""
              echo "Available commands:"
              echo "  ./bin/build-iso        - Build installer ISO"
              echo "  ./bin/build-vm         - Fast VM testing (terminal/desktop)"
              echo "  ./bin/virtual-machine  - Full stack VM with libvirt"
              echo "  ./bin/pre-commit       - Install or run the pre-commit hook"
              echo "  ci                     - Run nix flake check"
              echo ""
              echo "Rust packages:  packages/keystone-ha/"

              alias ci='nix flake check'
            '';

            # Rust environment variables
            RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";
          };
        };

      # Flake templates for users to scaffold new projects
      templates = {
        default = {
          path = ./templates/default;
          description = "Keystone infrastructure starter with OS module and home-manager";
          welcomeText = ''
            # keystone-config

            Your Keystone config repo has been initialized.

            ## Next step

            Open the onboarding walkthrough and follow the numbered steps:

               $EDITOR docs/keystone/onboarding.md

            Each step builds on the last and ends with a quick verification.
            You can stop after Step 2 if you only need a configured flake,
            after Step 5 once a host is up, or carry on through Step 8 for
            secureboot + TPM + sops secrets.

            README.md has the file layout reference.
          '';
        };
      };
    };
}
