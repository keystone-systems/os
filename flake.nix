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
    omarchy = {
      url = "github:basecamp/omarchy/v3.0.2";
      flake = false;
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.crane.follows = "crane";
    };
    hyprland.url = "github:hyprwm/Hyprland";
    hyprpaper = {
      url = "github:hyprwm/hyprpaper";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.hyprlang.follows = "hyprland/hyprlang";
      inputs.hyprutils.follows = "hyprland/hyprutils";
      inputs.hyprgraphics.follows = "hyprland/hyprgraphics";
      inputs.hyprwayland-scanner.follows = "hyprland/hyprwayland-scanner";
    };
    himalaya = {
      url = "github:pimalaya/himalaya";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    calendula = {
      url = "github:pimalaya/calendula";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cardamum = {
      url = "github:pimalaya/cardamum";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    comodoro = {
      # Newer revisions export only a development shell, while the terminal
      # module consumes the packaged CLI.
      url = "github:pimalaya/comodoro/b70b3605acc358e0d9cb57525adba9c05fc53f3d";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # AI coding agents (claude-code, gemini-cli, codex, opencode).
    # Keystone keeps this input at nightly-latest. Contributors should follow
    # keystone's pin (llm-agents.follows = "keystone/llm-agents") so that
    # relocking keystone automatically bumps agent versions.
    # Consumers who prefer a stable pin can declare their own llm-agents input
    # and override keystone's with: keystone.inputs.llm-agents.follows = "llm-agents".
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
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
    walker = {
      url = "github:abenz1267/walker";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secret management
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # NixOS tools
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-flatpak.url = "github:gmodena/nix-flatpak";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Helix editor themes
    kinda-nvim-hx = {
      url = "github:strash/kinda_nvim.hx";
      flake = false;
    };

    deepwork = {
      url = "github:Unsupervisedcom/deepwork";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # MCP servers
    grafana-mcp-src = {
      url = "github:grafana/mcp-grafana";
      flake = false;
    };

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
      omarchy,
      lanzaboote,
      hyprland,
      hyprpaper,
      himalaya,
      calendula,
      cardamum,
      comodoro,
      llm-agents,
      browser-previews,
      ghostty,
      yazi,
      walker,
      agenix,
      nix-index-database,
      nix-flatpak,
      nixos-hardware,
      kinda-nvim-hx,
      deepwork,
      grafana-mcp-src,
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
          hyprland
          hyprpaper
          himalaya
          llm-agents
          browser-previews
          agenix
          walker
          nix-index-database
          nix-flatpak
          nixos-hardware
          kinda-nvim-hx
          omarchy
          ;
        self = self;
        deepwork = deepwork;
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
      overlays.default = import ./overlays/default.nix {
        inherit
          self
          crane
          himalaya
          calendula
          cardamum
          comodoro
          llm-agents
          browser-previews
          ghostty
          yazi
          agenix
          deepwork
          grafana-mcp-src
          lfs-s3-src
          ;
      };

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
        experimental = ./modules/shared/experimental.nix;

        # Update channel selector (keystone.update.channel) — stable | unstable
        update = ./modules/shared/update.nix;

        # Managed repo registry + development mode toggle (keystone.repos, keystone.development)
        repos = ./modules/shared/repos.nix;

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
            agenix.nixosModules.default
            ./modules/domain.nix
            ./modules/services.nix
            ./modules/hosts.nix
            ./modules/shared/experimental.nix
            ./modules/shared/repos.nix
            ./modules/shared/update.nix
            ./modules/os
            ./modules/installer.nix
          ];
          keystone.os.installer._keystoneInputs = keystoneInputs;
          # Auto-populate keystone.repos from flake inputs with discoverable URLs.
          # Only pass inputs that represent managed repos — not all upstream dependencies.
          keystone._repoInputs = {
            keystone = self;
            inherit deepwork;
          };
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            sharedModules = [
              self.homeModules.terminal
              self.homeModules.notes
            ];
          };
        };

        # Desktop module - Hyprland, audio, greetd (no disko/encryption dependencies)
        desktop = {
          imports = [
            keystoneInputs.nix-flatpak.nixosModules.nix-flatpak
            ./modules/desktop/nixos.nix
          ];
          _module.args.keystoneInputs = keystoneInputs;
          home-manager.sharedModules = [
            self.homeModules.desktop
          ];
        };

        # Server module - VPN, monitoring, mail, binary cache (optional services)
        server = {
          imports = [
            ./modules/domain.nix
            ./modules/services.nix
            ./modules/server
          ];
        };

        # Binary cache client - configures nix substituters for Attic cache
        binaryCacheClient = {
          imports = [
            ./modules/domain.nix
            ./modules/binary-cache-client.nix
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
        desktopHyprland = ./home-manager/modules/desktop/hyprland;
        # Keystone-specific home-manager modules
        terminal = {
          imports = [
            keystoneInputs.nix-index-database.homeModules.nix-index
            ./modules/terminal/default.nix
          ];
          _module.args.keystoneInputs = keystoneInputs;
        };
        desktop = {
          imports = [
            keystoneInputs.walker.homeManagerModules.default
            ./modules/desktop/home/default.nix
          ];
          # keystoneInputs is provided by homeModules.terminal (loaded as a
          # sharedModule by nixosModules.operating-system). Do not redeclare
          # _module.args here to avoid "defined multiple times" when both
          # terminal and desktop are active.
        };
        notes = ./modules/notes/default.nix;
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
          ksRustTests = ks.passthru.tests.cargo-test;
          ksRustClippy = ks.passthru.tests.cargo-clippy;
          ksRustFmt = ks.passthru.tests.cargo-fmt;
          ksHelp = import ./tests/module/ks-help.nix {
            pkgs = ksPkgs;
            inherit ks;
          };
          ksPhotos = import ./tests/module/keystone-photos.nix {
            pkgs = ksPkgs;
            inherit lib ks;
          };
          ksApprove = import ./tests/module/ks-approve.nix {
            pkgs = ksPkgs;
            inherit ks;
          };
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
          # --- Individual checks (available for local builds) ---

          osEvaluation = import ./tests/module/os-evaluation.nix {
            inherit pkgs lib;
            self = self;
          };
          agentEvaluation = import ./tests/module/agent-evaluation.nix {
            inherit
              pkgs
              lib
              nixpkgs
              agenix
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
          keystoneSecretsMenu = import ./tests/module/keystone-secrets-menu.nix {
            inherit pkgs lib;
          };
          keystoneFingerprintMenu = import ./tests/module/keystone-fingerprint-menu.nix {
            inherit pkgs lib;
          };
          keystoneUpdateMenuWiring = import ./tests/module/keystone-update-menu-wiring.nix {
            inherit pkgs lib;
          };
          keystoneUpdateApproveFlow = import ./tests/module/keystone-update-approve-flow.nix {
            pkgs = ksPkgs;
            inherit lib ks;
          };
          hyprlandBindingsAgentConflict = import ./tests/module/hyprland-bindings-agent-conflict.nix {
            inherit pkgs;
          };
          desktopWalkerSurfaces = import ./tests/module/desktop-walker-surfaces.nix {
            inherit pkgs;
          };
          hyprlandConfigSmoke = import ./tests/module/hyprland-config-smoke.nix {
            pkgs = ksPkgs;
            lib = ksPkgs.lib;
            inherit home-manager;
            self = self;
          };
          desktopFprintd = import ./tests/module/desktop-fprintd.nix {
            pkgs = ksPkgs;
            lib = ksPkgs.lib;
            inherit nixpkgs;
            self = self;
          };
          agentctlRegression = import ./tests/module/agentctl-regression.nix {
            inherit pkgs;
          };
          binaryCacheClientMerge = import ./tests/module/binary-cache-client-merge.nix {
            inherit pkgs lib self;
          };
          terminalZide = import ./tests/module/terminal-zide.nix {
            inherit
              pkgs
              self
              home-manager
              ;
          };
          agentTaskLoopHashRegression = import ./tests/module/agent-task-loop-hash-regression.nix {
            inherit pkgs lib;
          };
          agentTaskLoopPingPong = import ./tests/module/agent-task-loop-ping-pong.nix {
            inherit pkgs lib;
          };
          agentRuntimeCoherence = import ./tests/module/agent-runtime-coherence.nix {
            inherit pkgs lib;
          };
          agentQueueMigration = import ./tests/module/agent-queue-migration.nix {
            inherit pkgs lib;
          };
        in
        {
          # Individual checks — for local debugging (nix build .#checks.x86_64-linux.<name>)
          os-evaluation = osEvaluation;
          agent-evaluation = agentEvaluation;
          template-evaluation = templateEvaluation;
          notes-evaluation = notesEvaluation;
          template-update-channel = templateUpdateChannel;
          template-special-args = templateSpecialArgs;
          server-evaluation = serverEvaluation;
          ks-help = ksHelp;
          keystone-photos = ksPhotos;
          keystone-secrets-menu = keystoneSecretsMenu;
          keystone-fingerprint-menu = keystoneFingerprintMenu;
          keystone-update-menu-wiring = keystoneUpdateMenuWiring;
          keystone-update-approve-flow = keystoneUpdateApproveFlow;
          hyprland-bindings-agent-conflict = hyprlandBindingsAgentConflict;
          desktop-walker-surfaces = desktopWalkerSurfaces;
          hyprland-config-smoke = hyprlandConfigSmoke;
          desktop-fprintd = desktopFprintd;
          ks-approve = ksApprove;
          approve-exec-script = approveExecScript;
          polkit-keystone-approve-cache = polkitKeystoneApproveCache;
          polkit-update-session-inhibit = polkitUpdateSessionInhibit;
          ks-rust-tests = ksRustTests;
          ks-rust-clippy = ksRustClippy;
          ks-rust-fmt = ksRustFmt;
          agentctl-regression = agentctlRegression;
          binary-cache-client-merge = binaryCacheClientMerge;
          terminal-zide = terminalZide;
          agent-task-loop-hash-regression = agentTaskLoopHashRegression;
          agent-task-loop-ping-pong = agentTaskLoopPingPong;
          agent-runtime-coherence = agentRuntimeCoherence;
          agent-queue-migration = agentQueueMigration;

          # --- CI groups — parallel matrix jobs via nix-github-actions ---

          # Heavy NixOS module evaluation (single-threaded eval dominates wall time)
          check-eval = pkgs.runCommand "check-eval" { } ''
            mkdir -p "$out"
            ln -s ${osEvaluation} "$out/os-evaluation"
            ln -s ${agentEvaluation} "$out/agent-evaluation"
            ln -s ${templateEvaluation} "$out/template-evaluation"
            ln -s ${notesEvaluation} "$out/notes-evaluation"
            ln -s ${templateUpdateChannel} "$out/template-update-channel"
            ln -s ${templateSpecialArgs} "$out/template-special-args"
            ln -s ${serverEvaluation} "$out/server-evaluation"
          '';

          # ks CLI: Rust build, lint, format, and integration tests
          check-ks = pkgs.runCommand "check-ks" { } ''
            mkdir -p "$out"
            ln -s ${ksRustTests} "$out/rust-tests"
            ln -s ${ksRustClippy} "$out/rust-clippy"
            ln -s ${ksRustFmt} "$out/rust-fmt"
            ln -s ${ksHelp} "$out/help"
            ln -s ${ksPhotos} "$out/photos"
            ln -s ${ksApprove} "$out/approve"
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
            ln -s ${keystoneUpdateMenuWiring} "$out/keystone-update-menu-wiring"
            ln -s ${keystoneUpdateApproveFlow} "$out/keystone-update-approve-flow"
          '';

          # Desktop config serialization and startup regressions
          check-desktop = pkgs.runCommand "check-desktop" { } ''
            mkdir -p "$out"
            ln -s ${hyprlandBindingsAgentConflict} "$out/hyprland-bindings-agent-conflict"
            ln -s ${desktopWalkerSurfaces} "$out/desktop-walker-surfaces"
            ln -s ${hyprlandConfigSmoke} "$out/hyprland-config-smoke"
            ln -s ${desktopFprintd} "$out/desktop-fprintd"
          '';

          # Agent runtime and miscellaneous module tests
          check-agents = pkgs.runCommand "check-agents" { } ''
            mkdir -p "$out"
            ln -s ${agentTaskLoopHashRegression} "$out/agent-task-loop-hash-regression"
            ln -s ${agentTaskLoopPingPong} "$out/agent-task-loop-ping-pong"
            ln -s ${agentRuntimeCoherence} "$out/agent-runtime-coherence"
            ln -s ${agentQueueMigration} "$out/agent-queue-migration"
            ln -s ${binaryCacheClientMerge} "$out/binary-cache-client-merge"
            ln -s ${terminalZide} "$out/terminal-zide"
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
        in
        (
          {
            iso = self.lib.mkInstallerIso { inherit nixpkgs; };
            inherit (pkgs.keystone)
              zesh
              agents-e2e
              agent-coding-agent
              agent-mail
              fetch-email-source
              fetch-forgejo-sources
              forgejo-cli-ex
              forgejo-project
              fetch-github-sources
              repo-sync
              podman-agent
              ks
              cfait
              zide
              zellij-tab-name
              write-polkit-theme
              chrome-devtools-mcp
              grafana-mcp
              lfs-s3
              deepwork-library-jobs
              keystone-deepwork-jobs
              keystone-conventions
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
              deepwork.packages.${pkgs.stdenv.hostPlatform.system}.default
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
              echo "Rust packages:  packages/keystone-ha/, packages/ks/"

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
            secureboot + TPM + agenix.

            README.md has the file layout reference.
          '';
        };
      };
    };
}
