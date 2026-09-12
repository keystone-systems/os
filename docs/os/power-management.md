# Power management

Keystone laptops can opt in to persistent suspend diagnostics:

```nix
keystone.os.power.debug.enable = true;
```

When enabled, Keystone MUST set `/sys/power/pm_debug_messages` to `1` after
boot. It MUST run a root-owned `systemd-sleep` hook before and after every
sleep operation. The hook MUST NOT prevent suspend, resume, or hibernation if
diagnostic collection fails.

Each operation creates a root-only directory below
`/var/lib/keystone/power-events/`. The pre-sleep snapshot is written before
the machine enters sleep, so it remains available after a forced reboot. A
normal resume adds an `after/` snapshot to the same directory.

Snapshots include:

- `pm_wakeup_irq` and its matching `/proc/interrupts` entry
- all `/sys/power/suspend_stats` values
- AMD PMC S0ix, firmware, and idle-mask diagnostics when available
- kernel wakeup sources and ACPI interrupt counters
- login1 and ACPI lid/dock state
- AC adapter and battery uevents
- PCI and USB devices whose `power/wakeup` value is `enabled`

This option records wake configuration. It MUST NOT enable or disable a PCI,
USB, or ACPI wake source. Event directories have no automatic retention
policy while an incident is under investigation.

## Closed-lid early wakes

On laptops with `keystone.os.power.suspendThenHibernate.enable`, Keystone MUST
re-check login1 after the complete suspend-then-hibernate operation finishes.
If the lid remains closed and the host is verifiably undocked, it MUST
immediately hibernate. An open lid, a docked host, or an unreadable lid/dock
state MUST remain awake.
