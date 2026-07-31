# Demo: Keystone OS FDE deployment

## Goal

Record a full bare-metal Keystone install that starts from the installer USB
and ends with a bootable system using custom Secure Boot keys, durable manual
full-disk-encryption unlock, and TPM2 automatic unlock.

The demo should show the core promise before agentic workflows: Keystone can
turn real hardware into a secure, encrypted, reproducible operating system.

## Capture setup

Use an HDMI capture path instead of screen recording from the target machine:

- Connect the target laptop's HDMI output to an HDMI capture device.
- Connect the capture device to the recording workstation over USB-C.
- Record the capture feed from the workstation.
- Keep a microphone available for narration during manual BIOS and enrollment
  steps.

This matters because the most important parts of the demo happen before the
installed OS is available: firmware setup, installer boot, disk unlock, and
first reboot validation.

## Demo flow

1. Boot the Keystone installer USB on the target hardware.
2. Show the firmware Secure Boot state before enrollment.
3. Install Keystone OS to encrypted storage.
4. Reboot into the installed system.
5. Enter firmware setup when required.
6. Enable Secure Boot custom mode so Keystone's own keys can be enrolled.
7. Enroll Keystone Secure Boot keys.
8. Enroll a hardware-key or recovery-key based manual FDE unlock path.
9. Reboot-test the manual unlock path.
10. Enroll TPM2 automatic unlock only after manual unlock is trusted.
11. Reboot again and show TPM2 automatic unlock under the expected Secure Boot
    state.
12. Run `ks hardware report` and explain the final state.

## Narration points

Explain the unlock methods in this order:

- Hardware key: preferred manual unlock when available. It gives strong
  physical security with better ergonomics than typing a long recovery key.
- Recovery key: high-entropy disaster recovery. It is intentionally random,
  hard to type, and should be stored off-host.
- Custom LUKS password: acceptable manual fallback, but should differ from the
  login password and should ideally be unique per host.
- TPM2: normal day-to-day automatic unlock. It is not a backup credential and
  should come last.

Explain the boot-integrity chain:

- Secure Boot custom keys protect the bootloader and initrd from tampering.
- TPM2 unlock is only meaningful after the expected Secure Boot state is in
  place.
- If the boot state changes unexpectedly, TPM2 unlock should fail closed and a
  tested manual unlock method should still recover the machine.

Explain why the order matters:

- Keystone should prove a durable manual unlock path before trusting automatic
  unlock.
- A LUKS keyslot existing is not enough; the user should reboot-test it.
- The final state should be ergonomic for daily use while still recoverable
  when firmware, hardware, or TPM state changes.

## Final acceptance shot

End the recording with:

- The machine booted into the installed Keystone OS.
- Secure Boot enabled with Keystone-controlled keys.
- At least one tested manual FDE unlock method.
- TPM2 automatic unlock working after manual fallback validation.
- `ks hardware report` showing the expected Secure Boot, FDE, and TPM state.
