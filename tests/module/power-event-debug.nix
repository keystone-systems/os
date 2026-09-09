{
  pkgs,
  lib,
  self,
}:
let
  nixosSystem = import "${pkgs.path}/nixos/lib/eval-config.nix";
  baseModule = {
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
  };
  evaluate =
    extraModule:
    nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.operating-system
        baseModule
        extraModule
      ];
    };
  disabled = evaluate { };
  enabled = evaluate {
    keystone.os.power.debug.enable = true;
  };
  hookName = "systemd/system-sleep/keystone-power-event-debug";
  hook = enabled.config.environment.etc.${hookName}.source;
  wiringIsValid =
    !(builtins.hasAttr hookName disabled.config.environment.etc)
    && !(disabled.config.systemd.services ? keystone-power-debug-messages)
    && builtins.hasAttr hookName enabled.config.environment.etc
    && enabled.config.systemd.services ? keystone-power-debug-messages
    && builtins.elem "d /var/lib/keystone/power-events 0700 root root - -" enabled.config.systemd.tmpfiles.rules;
in
pkgs.runCommand "power-event-debug"
  {
    nativeBuildInputs = [ pkgs.gnugrep ];
  }
  ''
    ${lib.optionalString (!wiringIsValid) ''
      echo 'FAIL: unexpected power debug module wiring' >&2
      exit 1
    ''}

    fixture="$TMPDIR/fixture"
    state="$TMPDIR/state"
    run="$TMPDIR/run"
    mkdir -p \
      "$fixture/sys/power/suspend_stats" \
      "$fixture/sys/kernel/debug/amd_pmc" \
      "$fixture/sys/firmware/acpi/interrupts" \
      "$fixture/sys/class/power_supply/AC" \
      "$fixture/sys/class/power_supply/BAT0" \
      "$fixture/sys/bus/pci/devices/0000:00:08.1/power" \
      "$fixture/sys/bus/usb/devices/1-1/power" \
      "$fixture/proc/acpi/button/lid/LID0" \
      "$fixture/proc/sys/kernel/random"

    printf '9\n' > "$fixture/sys/power/pm_wakeup_irq"
    printf '1813532317\n' > "$fixture/sys/power/suspend_stats/last_hw_sleep"
    printf 'success: 4\n' > "$fixture/sys/power/suspend_stats/success"
    printf 'S0ix Residency: 100\n' > "$fixture/sys/kernel/debug/amd_pmc/s0ix_stats"
    printf 'SMU FW: test\n' > "$fixture/sys/kernel/debug/amd_pmc/smu_fw_info"
    printf 'Idle Mask: 0xff\n' > "$fixture/sys/kernel/debug/amd_pmc/amd_pmc_idlemask"
    printf 'before-wakeup-source\n' > "$fixture/sys/kernel/debug/wakeup_sources"
    printf '1\n' > "$fixture/sys/firmware/acpi/interrupts/gpe00"
    printf 'POWER_SUPPLY_NAME=AC\nPOWER_SUPPLY_ONLINE=0\n' > "$fixture/sys/class/power_supply/AC/uevent"
    printf 'POWER_SUPPLY_NAME=BAT0\nPOWER_SUPPLY_STATUS=Discharging\nPOWER_SUPPLY_CAPACITY=72\n' > "$fixture/sys/class/power_supply/BAT0/uevent"
    printf 'enabled\n' > "$fixture/sys/bus/pci/devices/0000:00:08.1/power/wakeup"
    printf 'PCI_SLOT_NAME=0000:00:08.1\nDRIVER=pcieport\n' > "$fixture/sys/bus/pci/devices/0000:00:08.1/uevent"
    printf 'disabled\n' > "$fixture/sys/bus/usb/devices/1-1/power/wakeup"
    printf 'PRODUCT=1d6b/2/614\n' > "$fixture/sys/bus/usb/devices/1-1/uevent"
    printf 'state: closed\n' > "$fixture/proc/acpi/button/lid/LID0/state"
    printf 'test-boot-id\n' > "$fixture/proc/sys/kernel/random/boot_id"
    printf '           9: 1 2 3 4 IR-IO-APIC 9-fasteoi acpi\n' > "$fixture/proc/interrupts"

    busctl="$TMPDIR/busctl"
    printf '#!/bin/sh\ncase "$*" in *LidClosed) echo "b true" ;; *Docked) echo "b false" ;; esac\n' > "$busctl"
    chmod +x "$busctl"

    export KEYSTONE_POWER_EVENT_ROOT="$state"
    export KEYSTONE_POWER_EVENT_RUN_ROOT="$run"
    export KEYSTONE_POWER_EVENT_SYS_ROOT="$fixture/sys"
    export KEYSTONE_POWER_EVENT_PROC_ROOT="$fixture/proc"
    export KEYSTONE_POWER_EVENT_DEBUG_ROOT="$fixture/sys/kernel/debug"
    export KEYSTONE_POWER_EVENT_BUSCTL="$busctl"

    ${hook} pre suspend
    event="$(find "$state" -mindepth 1 -maxdepth 1 -type d -print -quit)"
    test -n "$event"
    grep -Fx '9' "$event/before/pm_wakeup_irq.txt"
    grep -F '9-fasteoi acpi' "$event/before/pm_wakeup_irq_interrupt.txt"
    grep -F 'last_hw_sleep' "$event/before/suspend_stats.txt"
    grep -Fx '1813532317' "$event/before/suspend_stats.txt"
    grep -Fx 'before-wakeup-source' "$event/before/wakeup_sources.txt"
    grep -F 'gpe00' "$event/before/acpi_interrupts.txt"
    grep -F 'state: closed' "$event/before/lid_and_dock.txt"
    grep -F 'POWER_SUPPLY_ONLINE=0' "$event/before/power_supplies.txt"
    grep -F 'POWER_SUPPLY_CAPACITY=72' "$event/before/power_supplies.txt"
    grep -F 'pci:0000:00:08.1' "$event/before/enabled_wakeup_devices.txt"
    ! grep -F 'usb:1-1' "$event/before/enabled_wakeup_devices.txt"

    printf '42\n' > "$fixture/sys/power/pm_wakeup_irq"
    printf '          42: 5 6 7 8 PCI-MSI 42-edge xhci_hcd\n' >> "$fixture/proc/interrupts"
    printf 'after-wakeup-source\n' > "$fixture/sys/kernel/debug/wakeup_sources"
    printf '7\n' > "$fixture/sys/firmware/acpi/interrupts/gpe00"
    ${hook} post suspend

    test "$(find "$state" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1
    grep -Fx '42' "$event/after/pm_wakeup_irq.txt"
    grep -F 'xhci_hcd' "$event/after/pm_wakeup_irq_interrupt.txt"
    grep -Fx 'after-wakeup-source' "$event/after/wakeup_sources.txt"
    grep -Fx '7' "$event/after/acpi_interrupts.txt"
    grep -F 'S0ix Residency: 100' "$event/after/amd_pmc_s0ix_stats.txt"
    grep -F 'phase=pre' "$event/metadata.txt"
    grep -F 'phase=post' "$event/metadata.txt"
    test ! -e "$run/current"

    # Diagnostic I/O failures must not block a sleep transition. A regular
    # file cannot contain event directories, forcing the recorder's writes to
    # fail while its systemd-sleep exit status remains successful.
    blocked="$TMPDIR/blocked-state-root"
    touch "$blocked"
    KEYSTONE_POWER_EVENT_ROOT="$blocked" ${hook} pre suspend 2>/dev/null

    # A hung source cannot accumulate per-file timeouts and hold up sleep.
    slow_busctl="$TMPDIR/slow-busctl"
    printf '#!${pkgs.bash}/bin/bash\nsleep 30\n' > "$slow_busctl"
    chmod +x "$slow_busctl"
    started="$(date +%s)"
    KEYSTONE_POWER_EVENT_ROOT="$TMPDIR/slow-state" \
      KEYSTONE_POWER_EVENT_RUN_ROOT="$TMPDIR/slow-run" \
      KEYSTONE_POWER_EVENT_BUSCTL="$slow_busctl" \
      KEYSTONE_POWER_EVENT_TIMEOUT_SECONDS=1 \
      ${hook} pre suspend
    elapsed="$(( $(date +%s) - started ))"
    test "$elapsed" -le 3

    touch "$out"
  ''
