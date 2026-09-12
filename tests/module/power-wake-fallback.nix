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
      {
        system.stateVersion = "25.05";
        boot.loader.systemd-boot.enable = true;
        keystone.os = {
          enable = true;
          hostKind = "laptop";
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
  fallbackService = result.config.systemd.services.keystone-closed-lid-wake-hibernate;
  checker = fallbackService.serviceConfig.ExecStart;
  onSuccess = result.config.systemd.services.systemd-suspend-then-hibernate.unitConfig.OnSuccess;
in
pkgs.runCommand "power-wake-fallback" { } ''
  test '${onSuccess}' = 'keystone-closed-lid-wake-hibernate.service'

  test_root="$TMPDIR/power-wake-fallback"
  mkdir -p "$test_root/bin"
  power_log="$test_root/power.log"
  lid_state="$test_root/lid"
  docked_state="$test_root/docked"

  printf '#!${pkgs.bash}/bin/bash\nproperty="$7"\ncase "$property" in LidClosed) state="$FAKE_LID_STATE" ;; Docked) state="$FAKE_DOCKED_STATE" ;; *) exit 1 ;; esac\n[[ "$state" != fail ]] || exit 1\nprintf "b %%s\\n" "$state"\n' > "$test_root/bin/busctl"
  printf '#!${pkgs.bash}/bin/bash\nprintf "%%s\\n" "$*" >> "$FAKE_POWER_LOG"\n' > "$test_root/bin/systemctl"
  chmod +x "$test_root/bin/busctl" "$test_root/bin/systemctl"

  export KEYSTONE_POWER_BUSCTL="$test_root/bin/busctl"
  export KEYSTONE_POWER_SYSTEMCTL="$test_root/bin/systemctl"
  export KEYSTONE_POWER_SETTLE_SECONDS=0
  export FAKE_POWER_LOG="$power_log"

  run_case() {
    FAKE_LID_STATE="$1" FAKE_DOCKED_STATE="$2" ${checker}
  }

  run_case true false
  grep -qx 'hibernate' "$power_log"

  : > "$power_log"
  run_case false false
  test ! -s "$power_log"

  run_case true true
  test ! -s "$power_log"

  run_case true fail
  test ! -s "$power_log"

  run_case fail false
  test ! -s "$power_log"

  touch "$out"
''
