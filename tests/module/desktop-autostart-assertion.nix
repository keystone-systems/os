# Desktop autostart assertion test
#
# Verifies the build-time assertion in autostart.nix catches a missing
# or misordered startup lock command. Pure evaluation test — no VM needed.
#
# Build: nix build .#test-desktop-autostart-assertion
#
{
  pkgs,
  lib,
  self,
  home-manager,
}:
let
  # Evaluate a home-manager configuration with the desktop module
  evalDesktop =
    extraModules:
    (home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        self.homeModules.terminal
        self.homeModules.desktop
        {
          home.username = "testuser";
          home.homeDirectory = "/home/testuser";
          home.stateVersion = "25.05";

          programs.ssh.enableDefaultConfig = false;

          keystone.terminal = {
            enable = true;
            git = {
              userName = "Test User";
              userEmail = "test@test";
            };
          };

          keystone.desktop.enable = true;

          # Hyprland requires a compositor to be enabled for settings to take effect
          wayland.windowManager.hyprland.enable = true;
        }
      ]
      ++ extraModules;
    }).config;
  boolString = value: if value then "true" else "false";

  # Test 1: Default config should have startup lock in exec-once
  defaultConfig = evalDesktop [ ];
  defaultExecOnce = defaultConfig.wayland.windowManager.hyprland.settings.exec-once;
  hasStartupLock = builtins.any (cmd: lib.hasPrefix "keystone-startup-lock" cmd) defaultExecOnce;

  # Test 2: Verify startup lock is the first user-visible entry (not just present)
  userVisible = builtins.filter (
    cmd:
    !(
      lib.hasPrefix "systemctl --user import-environment" cmd
      || lib.hasPrefix "dbus-update-activation-environment" cmd
    )
  ) defaultExecOnce;
  lockIsFirst =
    userVisible != [ ] && lib.hasPrefix "keystone-startup-lock" (builtins.head userVisible);

  # Test 3: Verify that mkAfter properly appends (doesn't replace)
  withMkAfterConfig = evalDesktop [
    {
      wayland.windowManager.hyprland.settings.exec-once = lib.mkAfter [
        "my-custom-app"
      ];
    }
  ];
  mkAfterExecOnce = withMkAfterConfig.wayland.windowManager.hyprland.settings.exec-once;
  mkAfterHasLock = builtins.any (cmd: lib.hasPrefix "keystone-startup-lock" cmd) mkAfterExecOnce;
  mkAfterHasCustom = builtins.any (cmd: cmd == "my-custom-app") mkAfterExecOnce;

  # Test 4: Verify assertion fires when lock is replaced via mkForce
  badConfigResult = builtins.tryEval (evalDesktop [
    {
      wayland.windowManager.hyprland.settings.exec-once = lib.mkForce [
        "some-other-app"
      ];
    }
  ]);
  assertionTripped = !badConfigResult.success;

  # Test 5: Custom startupLockCommand is used in exec-once
  customLockConfig = evalDesktop [
    { keystone.desktop.startupLockCommand = "my-custom-lock"; }
  ];
  customExecOnce = customLockConfig.wayland.windowManager.hyprland.settings.exec-once;
  hasCustomLock = builtins.any (cmd: lib.hasPrefix "my-custom-lock" cmd) customExecOnce;
in
pkgs.runCommand "test-desktop-autostart-assertion" { } ''
  set -euo pipefail
  errors=0

  check() {
    if [ "$1" = "true" ]; then
      echo "PASS: $2"
    else
      echo "FAIL: $2" >&2
      errors=$((errors + 1))
    fi
  }

  check "${boolString hasStartupLock}" \
    "default exec-once contains keystone-startup-lock"

  check "${boolString lockIsFirst}" \
    "startup lock is the first user-visible exec-once entry"

  check "${boolString mkAfterHasLock}" \
    "mkAfter preserves startup lock in exec-once"

  check "${boolString mkAfterHasCustom}" \
    "mkAfter appends custom entry to exec-once"

  check "${boolString assertionTripped}" \
    "assertion fires when exec-once is replaced without lock"

  check "${boolString hasCustomLock}" \
    "custom startupLockCommand appears in exec-once"

  if [ "$errors" -gt 0 ]; then
    echo "$errors test(s) failed" >&2
    exit 1
  fi

  echo "All desktop autostart assertion tests passed"
  touch "$out"
''
