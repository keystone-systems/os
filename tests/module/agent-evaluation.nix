# Agent module evaluation test
#
# Verifies that the OS agents module evaluates correctly with various
# configuration options. Forces NixOS module evaluation at build time
# to catch option errors, type mismatches, and assertion failures.
#
# Build: nix build .#agent-evaluation
#
{
  pkgs,
  lib,
  self,
  nixpkgs ? null,
  agenix,
  home-manager,
}:
let
  nixosSystem =
    if nixpkgs != null then
      nixpkgs.lib.nixosSystem
    else
      import "${pkgs.path}/nixos/lib/eval-config.nix";

  # Helper: evaluate a NixOS config and serialize a config value to prove evaluation.
  # Uses builtins.toJSON on users.users to force module evaluation of agent user
  # creation without pulling in the full system build (which needs lanzaboote/cargo).
  eval =
    name: modules:
    let
      result = nixosSystem {
        system = "x86_64-linux";
        modules = [
          {
            # Apply keystone overlay so pkgs.keystone.* is available
            nixpkgs.overlays = [ self.overlays.default ];
          }
          agenix.nixosModules.default
          self.nixosModules.operating-system
          {
            # Minimal required config for evaluation
            system.stateVersion = "25.05";
            boot.loader.systemd-boot.enable = true;
            networking.hostName = "test-host";

            # Override shared Home Manager defaults added by operating-system.
            home-manager.sharedModules = [
              {
                # Disable sandbox during evaluation tests to avoid external
                # dependency issues (like electron_40 being missing in nixpkgs)
                keystone.terminal.sandbox.enable = false;
              }
            ];
          }
        ]
        ++ modules;
      };
      # Serialize user config to force evaluation of agent user creation
      usersJson = builtins.toJSON (builtins.attrNames result.config.users.users);
      groupsJson = builtins.toJSON (builtins.attrNames result.config.users.groups);
      servicesJson = builtins.toJSON (builtins.attrNames result.config.systemd.services);
      timersJson = builtins.toJSON (builtins.attrNames result.config.systemd.timers);
      userServicesJson = builtins.toJSON (builtins.attrNames result.config.systemd.user.services);
      userTimersJson = builtins.toJSON (builtins.attrNames result.config.systemd.user.timers);
      hmUsersJson =
        if result.config ? home-manager then
          builtins.toJSON (builtins.attrNames result.config.home-manager.users)
        else
          "[]";

      # Check for session variables in home-manager if terminal is enabled for testuser
      sessionVarsJson =
        if result.config ? home-manager && result.config.home-manager.users ? testuser then
          builtins.toJSON result.config.home-manager.users.testuser.home.sessionVariables
        else
          "{}";
      deepworkMcpJson =
        if result.config ? home-manager && result.config.home-manager.users ? testuser then
          builtins.toJSON (
            result.config.home-manager.users.testuser.keystone.terminal.cliCodingAgents.generatedMcpServers.codex.deepwork
              or { }
          )
        else
          "{}";
      resolvedCapabilitiesJson =
        if result.config ? home-manager && result.config.home-manager.users ? testuser then
          builtins.toJSON (
            result.config.home-manager.users.testuser.keystone.terminal.aiExtensions.resolvedCapabilities or [ ]
          )
        else
          "[]";
      publishedCommandsJson =
        if result.config ? home-manager && result.config.home-manager.users ? testuser then
          builtins.toJSON (
            result.config.home-manager.users.testuser.keystone.terminal.aiExtensions.publishedCommands or [ ]
          )
        else
          "[]";
      homeFilesJson =
        if result.config ? home-manager && result.config.home-manager.users ? testuser then
          builtins.toJSON (builtins.attrNames result.config.home-manager.users.testuser.home.file)
        else
          "[]";
      canonicalAgentsTextJson =
        if result.config ? home-manager && result.config.home-manager.users ? testuser then
          lib.escapeShellArg (
            builtins.toJSON (
              result.config.home-manager.users.testuser.home.file.".keystone/AGENTS.md".text or ""
            )
          )
        else
          "''";
      dragoCapabilitiesJson =
        if result.config ? home-manager && result.config.home-manager.users ? "agent-drago" then
          builtins.toJSON (
            result.config.home-manager.users."agent-drago".keystone.terminal.aiExtensions.resolvedCapabilities
              or [ ]
          )
        else
          "[]";
      luceCapabilitiesJson =
        if result.config ? home-manager && result.config.home-manager.users ? "agent-luce" then
          builtins.toJSON (
            result.config.home-manager.users."agent-luce".keystone.terminal.aiExtensions.resolvedCapabilities
              or [ ]
          )
        else
          "[]";
    in
    pkgs.runCommand "eval-${name}" { } ''
      echo "Evaluating ${name}..."
      echo "  Users: ${usersJson}"
      echo "  Groups: ${groupsJson}"
      echo "  Services: ${servicesJson}"
      echo "  Timers: ${timersJson}"
      echo "  User Services: ${userServicesJson}"
      echo "  User Timers: ${userTimersJson}"

      if [ "${name}" = "locked-mode" ]; then
        echo "Verifying DeepWork MCP env in locked mode..."
        if echo '${deepworkMcpJson}' | grep -q '"DEEPWORK_ADDITIONAL_JOBS_FOLDERS"'; then
          echo "  ✓ Found DeepWork MCP env key"
        else
          echo "  ✗ Missing DeepWork MCP env key"
          echo "  Actual DeepWork MCP config: ${deepworkMcpJson}"
          exit 1
        fi
        if echo '${deepworkMcpJson}' | grep -q 'deepwork-library-jobs'; then
          echo "  ✓ Found locked deepwork jobs store path"
        else
          echo "  ✗ Missing locked deepwork jobs store path"
          echo "  Actual DeepWork MCP config: ${deepworkMcpJson}"
          exit 1
        fi
        if echo '${deepworkMcpJson}' | grep -q 'keystone-deepwork-jobs'; then
          echo "  ✓ Found locked keystone jobs store path"
        else
          echo "  ✗ Missing locked keystone jobs store path"
          echo "  Actual DeepWork MCP config: ${deepworkMcpJson}"
          exit 1
        fi
        if echo '${resolvedCapabilitiesJson}' | grep -q '"ks"'; then
          echo "  ✓ Found default ks capability"
        else
          echo "  ✗ Missing default ks capability"
          echo "  Actual capabilities: ${resolvedCapabilitiesJson}"
          exit 1
        fi
        if echo '${publishedCommandsJson}' | grep -q '"ks.system"' && ! echo '${publishedCommandsJson}' | grep -q '"ks.dev"'; then
          echo "  ✓ Published /ks.system in locked mode (no /ks.dev)"
        else
          echo "  ✗ Unexpected locked-mode command surface"
          echo "  Actual commands: ${publishedCommandsJson}"
          exit 1
        fi
        if echo '${homeFilesJson}' | grep -q '".keystone/AGENTS.md"'; then
          echo "  ✓ Found canonical ~/.keystone/AGENTS.md"
        else
          echo "  ✗ Missing canonical ~/.keystone/AGENTS.md"
          echo "  Actual home files: ${homeFilesJson}"
          exit 1
        fi
        if echo ${canonicalAgentsTextJson} | grep -q 'process.privileged-approval'; then
          echo "  ✓ Found privileged approval guidance in ~/.keystone/AGENTS.md"
        else
          echo "  ✗ Missing privileged approval guidance in ~/.keystone/AGENTS.md"
          exit 1
        fi
        if echo ${canonicalAgentsTextJson} | grep -q 'Shared-surface tracking'; then
          echo "  ✓ Found shared-surface tracking guidance in ~/.keystone/AGENTS.md"
        else
          echo "  ✗ Missing shared-surface tracking guidance in ~/.keystone/AGENTS.md"
          exit 1
        fi
      fi

      if [ "${name}" = "agent-home-manager-host-filtering" ]; then
        echo "Verifying host-aware agent home-manager filtering..."
        if echo '${hmUsersJson}' | grep -q '"agent-drago"'; then
          echo "  ✓ Found local agent home-manager user"
        else
          echo "  ✗ Missing local agent home-manager user"
          echo "  Actual home-manager users: ${hmUsersJson}"
          exit 1
        fi
        if echo '${hmUsersJson}' | grep -q '"agent-luce"'; then
          echo "  ✗ Remote agent home-manager user leaked onto this host"
          echo "  Actual home-manager users: ${hmUsersJson}"
          exit 1
        else
          echo "  ✓ Remote agent home-manager user excluded from this host"
        fi
      fi

      # Verify DEEPWORK_ADDITIONAL_JOBS_FOLDERS for development-mode test
      if [ "${name}" = "development-mode" ]; then
        echo "Verifying DEEPWORK_ADDITIONAL_JOBS_FOLDERS in development-mode..."
        if echo '${sessionVarsJson}' | grep -q "/home/testuser/repos/Unsupervisedcom/deepwork/library/jobs"; then
          echo "  ✓ Found local deepwork jobs path"
        else
          echo "  ✗ Missing local deepwork jobs path"
          echo "  Actual Session Vars: ${sessionVarsJson}"
          exit 1
        fi
        # We expect /home/testuser/repos/ncrmro/keystone/.deepwork/jobs
        # because ncrmro/keystone is the guessed name for the keystone input.
        # Anchor on a trailing colon/quote so we don't match `.deepwork/jobs-internal`
        # as a substring — otherwise dropping the published path would still pass.
        if echo '${sessionVarsJson}' | grep -qE "/home/testuser/repos/ncrmro/keystone/\.deepwork/jobs(:|\")"; then
          echo "  ✓ Found local keystone jobs path"
        else
          echo "  ✗ Missing local keystone jobs path"
          echo "  Actual Session Vars: ${sessionVarsJson}"
          exit 1
        fi
        # Internal jobs path is appended only in dev mode and is intentionally
        # absent from the published keystone-deepwork-jobs package.
        if echo '${sessionVarsJson}' | grep -qE "/home/testuser/repos/ncrmro/keystone/\.deepwork/jobs-internal(:|\")"; then
          echo "  ✓ Found local keystone internal jobs path"
        else
          echo "  ✗ Missing local keystone internal jobs path"
          echo "  Actual Session Vars: ${sessionVarsJson}"
          exit 1
        fi
        if echo '${deepworkMcpJson}' | grep -q '"/home/testuser/repos/Unsupervisedcom/deepwork/library/jobs:/home/testuser/repos/ncrmro/keystone/.deepwork/jobs:/home/testuser/repos/ncrmro/keystone/.deepwork/jobs-internal"'; then
          echo "  ✓ Found development-mode DeepWork MCP env value"
        else
          echo "  ✗ Missing development-mode DeepWork MCP env value"
          echo "  Actual DeepWork MCP config: ${deepworkMcpJson}"
          exit 1
        fi
        if echo '${resolvedCapabilitiesJson}' | grep -q '"ks-dev"'; then
          echo "  ✓ Found ks-dev capability in development mode"
        else
          echo "  ✗ Missing ks-dev capability in development mode"
          echo "  Actual capabilities: ${resolvedCapabilitiesJson}"
          exit 1
        fi
        if echo '${publishedCommandsJson}' | grep -q '"ks.dev"'; then
          echo "  ✓ Published /ks.dev in development mode"
        else
          echo "  ✗ Missing /ks.dev in development mode"
          echo "  Actual commands: ${publishedCommandsJson}"
          exit 1
        fi
      fi

      if [ "${name}" = "agent-capabilities" ]; then
        if echo '${dragoCapabilitiesJson}' | grep -q '"engineer"' && ! echo '${dragoCapabilitiesJson}' | grep -q '"executive-assistant"'; then
          echo "  ✓ Drago resolved engineer capability without executive-assistant"
        else
          echo "  ✗ Drago capability resolution is wrong"
          echo "  Actual Drago capabilities: ${dragoCapabilitiesJson}"
          exit 1
        fi
        if echo '${luceCapabilitiesJson}' | grep -q '"executive-assistant"' && ! echo '${luceCapabilitiesJson}' | grep -q '"engineer"'; then
          echo "  ✓ Luce resolved executive-assistant capability without engineer"
        else
          echo "  ✗ Luce capability resolution is wrong"
          echo "  Actual Luce capabilities: ${luceCapabilitiesJson}"
          exit 1
        fi
        if echo '${dragoCapabilitiesJson}' | grep -q '"notes"' && echo '${luceCapabilitiesJson}' | grep -q '"notes"'; then
          echo "  ✓ Both agents keep notes capability"
        else
          echo "  ✗ Missing notes capability on one or both agents"
          echo "  Drago: ${dragoCapabilitiesJson}"
          echo "  Luce: ${luceCapabilitiesJson}"
          exit 1
        fi
      fi

      if [ "${name}" = "user-screenshot-sync" ]; then
        if echo '${userServicesJson}' | grep -q '"keystone-testuser-screenshot-sync"'; then
          echo "  ✓ Found desktop user screenshot sync service"
        else
          echo "  ✗ Missing desktop user screenshot sync service"
          echo "  Actual user services: ${userServicesJson}"
          exit 1
        fi
        if echo '${userTimersJson}' | grep -q '"keystone-testuser-screenshot-sync"'; then
          echo "  ✓ Found desktop user screenshot sync timer"
        else
          echo "  ✗ Missing desktop user screenshot sync timer"
          echo "  Actual user timers: ${userTimersJson}"
          exit 1
        fi
      fi

      if [ "${name}" = "agent-screenshot-sync" ]; then
        if echo '${userServicesJson}' | grep -q '"agent-vision-screenshot-sync"'; then
          echo "  ✓ Found agent screenshot sync service"
        else
          echo "  ✗ Missing agent screenshot sync service"
          echo "  Actual user services: ${userServicesJson}"
          exit 1
        fi
        if echo '${userTimersJson}' | grep -q '"agent-vision-screenshot-sync"'; then
          echo "  ✓ Found agent screenshot sync timer"
        else
          echo "  ✗ Missing agent screenshot sync timer"
          echo "  Actual user timers: ${userTimersJson}"
          exit 1
        fi
      fi

      touch $out
    '';

  # Test configurations
  tests = {
    # No agents configured (default)
    no-agents = eval "no-agents" [
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

    # Locked mode verification
    locked-mode = eval "locked-mode" [
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
            terminal.enable = true;
            email = "testuser@example.com";
            capabilities = [ "ks" ];
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Development mode verification
    development-mode = eval "development-mode" [
      {
        keystone.development = true;
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
            terminal.enable = true;
            email = "testuser@example.com";
            capabilities = [ "ks" ];
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    agent-capabilities = eval "agent-capabilities" [
      {
        keystone.development = true;
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
          agents.drago = {
            fullName = "Drago";
            email = "drago@example.com";
            archetype = "engineer";
            capabilities = [
              "engineer"
              "notes"
            ];
            notes.repo = "git@example.com:drago/notes.git";
          };
          agents.luce = {
            fullName = "Luce";
            email = "luce@example.com";
            archetype = "product";
            capabilities = [
              "notes"
              "executive-assistant"
            ];
            notes.repo = "git@example.com:luce/notes.git";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    agent-home-manager-host-filtering = eval "agent-home-manager-host-filtering" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
          };
          agents.drago = {
            fullName = "Drago";
            email = "drago@example.com";
            host = "test-host";
            notes.repo = "git@example.com:drago/notes.git";
          };
          agents.luce = {
            fullName = "Luce";
            email = "luce@example.com";
            host = "ocean";
            notes.repo = "git@example.com:luce/notes.git";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Single agent on ext4
    single-agent-ext4 = eval "single-agent-ext4" [
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
          agents.researcher = {
            fullName = "Research Agent";
            email = "researcher@ks.systems";
            notes.repo = "git@example.com:researcher/notes.git";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Multiple agents on ZFS
    multi-agent-zfs = eval "multi-agent-zfs" [
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
          agents = {
            researcher = {
              fullName = "Research Agent";
              email = "researcher@ks.systems";
              notes.repo = "git@example.com:researcher/notes.git";
            };
            coder = {
              fullName = "Coding Agent";
              email = "coder@ks.systems";
              notes.repo = "git@example.com:coder/notes.git";
            };
          };
        };
        networking.hostId = "deadbeef";
        fileSystems."/" = {
          device = lib.mkForce "rpool/root";
          fsType = lib.mkForce "zfs";
        };
      }
    ];

    # Agent with explicit UID
    agent-explicit-uid = eval "agent-explicit-uid" [
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
          agents.researcher = {
            uid = 4050;
            fullName = "Research Agent";
            notes.repo = "git@example.com:researcher/notes.git";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with desktop enabled (labwc + wayvnc)
    agent-desktop = eval "agent-desktop" [
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
          agents.researcher = {
            fullName = "Research Agent";
            notes.repo = "git@example.com:researcher/notes.git";
          };
          agents.coder = {
            fullName = "Coding Agent";
            notes.repo = "git@example.com:coder/notes.git";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with desktop and custom resolution + explicit VNC port
    agent-desktop-custom = eval "agent-desktop-custom" [
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
          agents.researcher = {
            fullName = "Research Agent";
            notes.repo = "git@example.com:researcher/notes.git";
            desktop = {
              enable = true;
              resolution = "2560x1440";
              vncPort = 5910;
            };
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with chrome enabled (auto-assigned debug port)
    agent-chrome = eval "agent-chrome" [
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
          agents.researcher = {
            fullName = "Research Agent";
            notes.repo = "git@example.com:researcher/notes.git";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with chrome and explicit debug port
    agent-chrome-custom-port = eval "agent-chrome-custom-port" [
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
          agents.researcher = {
            fullName = "Research Agent";
            notes.repo = "git@example.com:researcher/notes.git";
            chrome = {
              enable = true;
              debugPort = 9300;
            };
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with notes.repo configured (sync user service)
    agent-notes = eval "agent-notes" [
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
          agents.drago = {
            fullName = "Drago";
            notes.repo = "git@git.ncrmro.com:drago/notes.git";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with notes and SSH
    agent-notes-ssh = eval "agent-notes-ssh" [
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
          agents.drago = {
            fullName = "Drago";
            notes.repo = "git@git.ncrmro.com:drago/notes.git";
            # SSH public key now set via keystone.keys."agent-drago"
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with custom sync interval
    agent-notes-sync = eval "agent-notes-sync" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
          };
          agents.tester = {
            fullName = "Test Agent";
            # SSH public key now set via keystone.keys."agent-tester"
            notes.repo = "git@example.com:test/notes.git";
            notes.syncOnCalendar = "*:0/15";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with task loop and scheduler
    agent-notes-task-loop = eval "agent-notes-task-loop" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
          };
          agents.drago = {
            fullName = "Drago";
            # SSH public key now set via keystone.keys."agent-drago"
            notes.repo = "git@git.example.com:drago/notes.git";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with custom task loop and scheduler schedules
    agent-notes-task-loop-custom = eval "agent-notes-task-loop-custom" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
          };
          agents.tester = {
            fullName = "Test Agent";
            # SSH public key now set via keystone.keys."agent-tester"
            notes.repo = "git@example.com:test/notes.git";
            notes.taskLoop = {
              defaults = {
                provider = "claude";
                profile = "medium";
                fallbackModel = "opus";
                effort = "medium";
              };
              profiles = {
                max = {
                  claude = {
                    model = "opus";
                    effort = "max";
                  };
                  gemini.model = "auto-gemini-3";
                };
              };
              ingest = {
                profile = "fast";
                provider = "gemini";
              };
              onCalendar = "*:0/15";
              maxTasks = 3;
              prioritize = {
                profile = "fast";
                model = "gemini-3-flash-preview";
              };
              execute = {
                profile = "max";
                provider = "claude";
                fallbackModel = "sonnet";
              };
            };
            notes.scheduler = {
              onCalendar = "*-*-* 06:00:00";
            };
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Multiple agents with chrome (non-conflicting auto-assigned ports)
    multi-agent-chrome = eval "multi-agent-chrome" [
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
          agents.researcher = {
            fullName = "Research Agent";
            notes.repo = "git@example.com:researcher/notes.git";
          };
          agents.coder = {
            fullName = "Coding Agent";
            notes.repo = "git@example.com:coder/notes.git";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with chrome MCP enabled — verifies evaluation succeeds and the
    # chrome-devtools-mcp package path is resolvable (home.packages added in
    # home-manager.nix when chrome.mcp.enable = true).
    agent-chrome-mcp = eval "agent-chrome-mcp" [
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
          agents.researcher = {
            fullName = "Research Agent";
            notes.repo = "git@example.com:researcher/notes.git";
            chrome = {
              enable = true;
              mcp.enable = true;
            };
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with GitHub and Forgejo source usernames
    # forgejo.username defaults to agent name; github.username must be set explicitly
    agent-source-usernames = eval "agent-source-usernames" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
          };
          # Both set: github explicit, forgejo defaults to "luce"
          agents.luce = {
            fullName = "Luce";
            notes.repo = "git@example.com:luce/notes.git";
            github.username = "luce-gh";
          };
          # GitHub set, forgejo defaults to "solo"
          agents.solo = {
            fullName = "Solo";
            notes.repo = "git@example.com:solo/notes.git";
            github.username = "solo-gh";
          };
          # No github username (null), forgejo defaults to "quiet"
          agents.quiet = {
            fullName = "Quiet";
            notes.repo = "git@example.com:quiet/notes.git";
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with calendar team events
    agent-calendar-team-events = eval "agent-calendar-team-events" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
          };
          agents.planner = {
            fullName = "Planning Agent";
            notes.repo = "git@example.com:planner/notes.git";
            calendar.teamEvents = [
              {
                summary = "Weekly Retrospective";
                schedule = "weekly:friday";
                time = "20:00";
                workflow = "retrospective/run";
              }
              {
                summary = "Monthly Review";
                schedule = "monthly:1";
                time = "10:00";
              }
            ];
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    # Agent with perception layer enabled (REQ-023.34)
    agent-perception = eval "agent-perception" [
      {
        keystone.os = {
          enable = true;
          storage = {
            type = "ext4";
            devices = [ "/dev/vda" ];
          };
          agents.vision = {
            fullName = "Vision Agent";
            notes.repo = "git@example.com:vision/notes.git";
            perception = {
              enable = true;
              voice.model = "small";
              processor = {
                enable = true;
                useOllama = true;
                onCalendar = "*:0/15";
              };
            };
          };
        };
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    user-screenshot-sync = eval "user-screenshot-sync" [
      {
        keystone = {
          domain = "example.com";
          hosts.ocean = {
            hostname = "ocean";
            role = "server";
            tailscaleIP = "100.64.0.10";
          };
          services.immich.host = "ocean";
          os = {
            enable = true;
            storage = {
              type = "ext4";
              devices = [ "/dev/vda" ];
            };
            users.testuser = {
              fullName = "Test User";
              initialPassword = "testpass";
              admin = true;
              desktop = {
                enable = true;
                screenshotSync.enable = true;
              };
            };
          };
        };
        age.secrets."testuser-immich-api-key".file = builtins.toFile "testuser-immich-api-key.age" "dummy";
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];

    agent-screenshot-sync = eval "agent-screenshot-sync" [
      {
        keystone = {
          domain = "example.com";
          hosts.ocean = {
            hostname = "ocean";
            role = "server";
            tailscaleIP = "100.64.0.10";
          };
          services.immich.host = "ocean";
          os = {
            enable = true;
            storage = {
              type = "ext4";
              devices = [ "/dev/vda" ];
            };
            agents.vision = {
              fullName = "Vision Agent";
              notes.repo = "git@example.com:vision/notes.git";
              host = "test-host";
              desktop.enable = true;
              perception.enable = true;
            };
          };
        };
        age.secrets."agent-vision-immich-api-key".file =
          builtins.toFile "agent-vision-immich-api-key.age" "dummy";
        fileSystems."/" = {
          device = lib.mkForce "/dev/vda2";
          fsType = lib.mkForce "ext4";
        };
      }
    ];
  };
in
pkgs.runCommand "test-agent-evaluation"
  {
    # Depend on all eval derivations so they get built
    buildInputs = builtins.attrValues tests;
  }
  ''
    echo "Agent module evaluation tests"
    echo "============================="
    echo ""
    echo "All agent module configurations evaluated successfully!"
    touch $out
  ''
