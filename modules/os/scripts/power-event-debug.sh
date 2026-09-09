# writeShellApplication enables errexit before this body. Collection is
# best-effort and MUST always return success to systemd-sleep.
set +e
set -u
set -o pipefail

snapshot_timeout="${KEYSTONE_POWER_EVENT_TIMEOUT_SECONDS:-20}"
case "$snapshot_timeout" in
  "" | *[!0-9]*) snapshot_timeout=20 ;;
esac

# systemd waits for every system-sleep hook. Run the collector as a bounded
# worker so many individually slow kernel files cannot accumulate into a
# minutes-long delay. The parent always reports success and leaves any partial
# evidence in place.
if [ "${KEYSTONE_POWER_EVENT_WORKER:-false}" != true ]; then
  timeout --kill-after=2s "${snapshot_timeout}s" \
    env KEYSTONE_POWER_EVENT_WORKER=true "$0" "$@" || true
  exit 0
fi

state_root="${KEYSTONE_POWER_EVENT_ROOT:-/var/lib/keystone/power-events}"
run_root="${KEYSTONE_POWER_EVENT_RUN_ROOT:-/run/keystone/power-event-debug}"
sys_root="${KEYSTONE_POWER_EVENT_SYS_ROOT:-/sys}"
proc_root="${KEYSTONE_POWER_EVENT_PROC_ROOT:-/proc}"
debug_root="${KEYSTONE_POWER_EVENT_DEBUG_ROOT:-${sys_root}/kernel/debug}"
busctl_command="${KEYSTONE_POWER_EVENT_BUSCTL:-busctl}"

record_file() {
  source_path="$1"
  destination="$2"

  if [ -r "$source_path" ]; then
    timeout 5s cat "$source_path" > "$destination" 2>&1 || printf 'ERROR: timed out or could not read %s\n' "$source_path" > "$destination"
  else
    printf 'UNAVAILABLE: %s\n' "$source_path" > "$destination"
  fi
}

record_directory_values() {
  source_directory="$1"
  destination="$2"

  : > "$destination"
  if [ ! -d "$source_directory" ]; then
    printf 'UNAVAILABLE: %s\n' "$source_directory" > "$destination"
    return
  fi

  found=false
  while IFS= read -r source_path; do
    found=true
    printf '== %s ==\n' "${source_path#"$sys_root"}" >> "$destination"
    timeout 5s cat "$source_path" >> "$destination" 2>&1 || printf 'ERROR: timed out or could not read %s\n' "$source_path" >> "$destination"
  done < <(find "$source_directory" -mindepth 1 -maxdepth 1 -type f -print 2>/dev/null | sort)

  if [ "$found" = false ]; then
    printf 'EMPTY: %s\n' "$source_directory" > "$destination"
  fi
}

record_power_supplies() {
  destination="$1"
  : > "$destination"

  found=false
  for supply in "$sys_root"/class/power_supply/*; do
    [ -d "$supply" ] || continue
    found=true
    printf '== %s ==\n' "$(basename "$supply")" >> "$destination"
    if [ -r "$supply/uevent" ]; then
      timeout 5s cat "$supply/uevent" >> "$destination" 2>&1 || printf 'ERROR: timed out or could not read %s/uevent\n' "$supply" >> "$destination"
    else
      printf 'UNAVAILABLE: %s/uevent\n' "$supply" >> "$destination"
    fi
  done

  if [ "$found" = false ]; then
    printf 'EMPTY: %s/class/power_supply\n' "$sys_root" > "$destination"
  fi
}

record_lid_and_dock() {
  destination="$1"
  : > "$destination"

  printf '== login1 LidClosed ==\n' >> "$destination"
  timeout 5s "$busctl_command" --timeout=2s get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager LidClosed >> "$destination" 2>&1 || printf 'UNAVAILABLE\n' >> "$destination"
  printf '== login1 Docked ==\n' >> "$destination"
  timeout 5s "$busctl_command" --timeout=2s get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager Docked >> "$destination" 2>&1 || printf 'UNAVAILABLE\n' >> "$destination"

  for state_file in "$proc_root"/acpi/button/lid/*/state "$sys_root"/devices/platform/dock.*/docked; do
    [ -e "$state_file" ] || continue
    printf '== %s ==\n' "$state_file" >> "$destination"
    timeout 5s cat "$state_file" >> "$destination" 2>&1 || printf 'ERROR: timed out or could not read %s\n' "$state_file" >> "$destination"
  done
}

record_wakeup_devices() {
  destination="$1"
  : > "$destination"

  found=false
  for bus in pci usb; do
    for wakeup_file in "$sys_root"/bus/"$bus"/devices/*/power/wakeup; do
      [ -r "$wakeup_file" ] || continue
      [ "$(timeout 5s tr -d '[:space:]' < "$wakeup_file" 2>/dev/null)" = enabled ] || continue
      found=true
      device_directory="${wakeup_file%/power/wakeup}"
      printf '== %s:%s ==\n' "$bus" "$(basename "$device_directory")" >> "$destination"
      printf 'path=%s\n' "$(readlink -f "$device_directory" 2>/dev/null || printf '%s' "$device_directory")" >> "$destination"
      if [ -L "$device_directory/driver" ]; then
        printf 'driver=%s\n' "$(basename "$(readlink -f "$device_directory/driver")")" >> "$destination"
      else
        printf 'driver=UNAVAILABLE\n' >> "$destination"
      fi
      printf 'wakeup=enabled\n' >> "$destination"
      if [ -r "$device_directory/uevent" ]; then
        timeout 5s cat "$device_directory/uevent" >> "$destination" 2>&1 || printf 'ERROR: timed out or could not read %s/uevent\n' "$device_directory" >> "$destination"
      fi
    done
  done

  if [ "$found" = false ]; then
    printf 'NONE: no PCI or USB device has power/wakeup enabled\n' > "$destination"
  fi
}

record_wakeup_irq() {
  destination_directory="$1"
  wakeup_irq_file="$sys_root/power/pm_wakeup_irq"
  record_file "$wakeup_irq_file" "$destination_directory/pm_wakeup_irq.txt"

  wakeup_irq="$(timeout 5s tr -d '[:space:]' < "$wakeup_irq_file" 2>/dev/null || true)"
  : > "$destination_directory/pm_wakeup_irq_interrupt.txt"
  if [[ "$wakeup_irq" =~ ^[0-9]+$ ]] && [ -r "$proc_root/interrupts" ]; then
    grep -E "^[[:space:]]*${wakeup_irq}:" "$proc_root/interrupts" > "$destination_directory/pm_wakeup_irq_interrupt.txt" 2>&1 \
      || printf 'NO MATCH: IRQ %s in %s/interrupts\n' "$wakeup_irq" "$proc_root" > "$destination_directory/pm_wakeup_irq_interrupt.txt"
  else
    printf 'UNAVAILABLE: valid pm_wakeup_irq or %s/interrupts\n' "$proc_root" > "$destination_directory/pm_wakeup_irq_interrupt.txt"
  fi
}

record_snapshot() {
  destination_directory="$1"
  mkdir -p "$destination_directory"

  record_wakeup_irq "$destination_directory"
  record_directory_values "$sys_root/power/suspend_stats" "$destination_directory/suspend_stats.txt"
  record_file "$debug_root/amd_pmc/s0ix_stats" "$destination_directory/amd_pmc_s0ix_stats.txt"
  record_file "$debug_root/amd_pmc/smu_fw_info" "$destination_directory/amd_pmc_smu_fw_info.txt"
  record_file "$debug_root/amd_pmc/amd_pmc_idlemask" "$destination_directory/amd_pmc_idlemask.txt"
  record_file "$debug_root/wakeup_sources" "$destination_directory/wakeup_sources.txt"
  record_directory_values "$sys_root/firmware/acpi/interrupts" "$destination_directory/acpi_interrupts.txt"
  record_lid_and_dock "$destination_directory/lid_and_dock.txt"
  record_power_supplies "$destination_directory/power_supplies.txt"
  record_wakeup_devices "$destination_directory/enabled_wakeup_devices.txt"
}

new_event_directory() {
  action="$1"
  safe_action="$(printf '%s' "$action" | tr -c 'A-Za-z0-9._-' '_')"
  timestamp="$(date --utc +%Y%m%dT%H%M%S.%NZ)"
  event_directory="$state_root/${timestamp}-${safe_action}-$$"
  mkdir -p "$event_directory"
  chmod 0700 "$event_directory"
  printf '%s\n' "$event_directory"
}

record_metadata() {
  event_directory="$1"
  phase="$2"
  action="$3"
  {
    printf 'phase=%s\n' "$phase"
    printf 'action=%s\n' "$action"
    printf 'systemd_sleep_action=%s\n' "${SYSTEMD_SLEEP_ACTION:-}"
    printf 'captured_at=%s\n' "$(date --utc --iso-8601=ns)"
    printf 'boot_id='
    cat "$proc_root/sys/kernel/random/boot_id" 2>/dev/null || printf 'UNAVAILABLE\n'
    printf 'kernel=%s\n' "$(uname -srvo)"
  } >> "$event_directory/metadata.txt"
}

phase="${1:-}"
action="${2:-unknown}"
mkdir -p "$state_root" "$run_root"
chmod 0700 "$state_root" "$run_root"

case "$phase" in
  pre)
    event_directory="$(new_event_directory "$action")"
    printf '%s\n' "$event_directory" > "$run_root/current"
    record_metadata "$event_directory" pre "$action"
    record_snapshot "$event_directory/before"
    ;;
  post)
    event_directory=""
    if [ -r "$run_root/current" ]; then
      event_directory="$(head -n 1 "$run_root/current")"
    fi
    case "$event_directory" in
      "$state_root"/*) [ -d "$event_directory" ] || event_directory="" ;;
      *) event_directory="" ;;
    esac
    if [ -z "$event_directory" ]; then
      event_directory="$(new_event_directory "orphan-${action}")"
    fi
    record_metadata "$event_directory" post "$action"
    record_snapshot "$event_directory/after"
    rm -f "$run_root/current"
    ;;
  *)
    printf 'Usage: %s {pre|post} [suspend|hibernate|hybrid-sleep|suspend-then-hibernate]\n' "$0" >&2
    ;;
esac

# A diagnostic failure MUST NOT prevent systemd from entering or leaving sleep.
exit 0
