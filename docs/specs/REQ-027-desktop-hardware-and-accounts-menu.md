# REQ-027: Desktop hardware and account menus

Requirements for the `Setup -> Hardware` and `Setup -> Accounts` desktop menu
flows. These menus extend the Keystone desktop setup surface with live hardware
security status, hardware-key disk-unlock enrollment, and multi-account mail
and calendar views backed by terminal-first tools.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Scope

This spec defines the contract for:

- the `Hardware` section under the desktop `Setup` menu,
- the `Accounts` section under the desktop `Setup` menu,
- terminal-first backend behavior for those menus, and
- declarative multi-account mail and calendar configuration used by the
  desktop account menu.

This spec does not redefine the general desktop menu framework from REQ-002
or Google Calendar OAuth2 support.

## Stories covered

- US-027-001: Inspect Secure Boot, TPM, and hardware-key disk-unlock state from
  the desktop
- US-027-002: Enroll a FIDO2 hardware key for disk unlock from the desktop
- US-027-003: Browse configured email accounts and recent inbox state from the
  desktop
- US-027-004: Browse configured calendar accounts and upcoming events from the
  desktop

## Normative dependencies

- REQ-002: Keystone Desktop
- REQ-018: Keystone Home Directory and Repo Management

## Functional requirements

### Hardware menu status (dhw-status-001)

The desktop MUST provide a hardware status menu under `Setup`.

- **dhw-status-001.1**: The `Hardware` menu MUST be reachable from the desktop
  `Setup` menu.
- **dhw-status-001.2**: The hardware menu MUST show live Secure Boot state
  sourced from the running system.
- **dhw-status-001.3**: The hardware menu MUST show live `sbctl` state,
  including whether the system is in setup mode or user mode.
- **dhw-status-001.4**: The hardware menu MUST show whether a TPM2 device is
  available on the current host.
- **dhw-status-001.5**: The hardware menu MUST show whether a FIDO2-compatible
  hardware key is currently available on the current host.
- **dhw-status-001.6**: The hardware menu MUST show the current disk-unlock
  enrollment state for TPM and FIDO2 tokens on the configured credstore or
  root LUKS device.
- **dhw-status-001.7**: If required tools, privileges, or devices are missing,
  the menu MUST show explicit blocked or degraded state entries rather than an
  empty list.

### Hardware-key disk-unlock enrollment (dhw-enroll-001)

The desktop MUST support starting a FIDO2 disk-unlock enrollment flow from the
hardware menu.

- **dhw-enroll-001.1**: The hardware menu MUST provide an action to enroll a
  FIDO2 hardware key for disk unlock on the configured credstore or root LUKS
  device.
- **dhw-enroll-001.2**: The enrollment flow MUST use `systemd-cryptenroll`
  rather than a custom token format.
- **dhw-enroll-001.3**: The enrollment flow MUST run in a detached terminal
  session so that PIN, touch, and confirmation prompts are visible to the user.
- **dhw-enroll-001.4**: Restarting `walker.service` or `elephant.service` MUST
  NOT close, interrupt, or invalidate the enrollment process once launched.
- **dhw-enroll-001.5**: The enrollment flow MUST perform preflight checks for
  the target LUKS device, Secure Boot state, TPM availability, and FIDO2 device
  availability before attempting enrollment.
- **dhw-enroll-001.6**: The enrollment flow MUST verify the new FIDO2 token
  state after enrollment completes.
- **dhw-enroll-001.7**: Root-only status inspection and enrollment logic MUST
  remain in terminal-first backend helpers rather than in Walker, Elephant, or
  Lua menu code.

### Account model and source of truth (dacct-model-001)

The desktop account menu MUST derive from declarative multi-account terminal
configuration.

- **dacct-model-001.1**: Keystone terminal mail configuration MUST support
  multiple named accounts.
- **dacct-model-001.2**: Keystone terminal calendar configuration MUST support
  multiple named accounts.
- **dacct-model-001.3**: Existing single-account mail and calendar options MUST
  remain supported through compatibility mapping to a default account.
- **dacct-model-001.4**: The desktop account menu MUST derive configured
  account metadata from declarative Keystone config rather than relying only on
  ad hoc parsing of generated client config files.
- **dacct-model-001.5**: The account menu backend SHOULD use the underlying
  configured CLI tools as the runtime source of live account state once
  declarative account metadata is known.

### Mail account menu behavior (dacct-mail-001)

The desktop MUST provide mail account visibility through the `Accounts` menu.

- **dacct-mail-001.1**: The `Accounts` menu MUST list all configured mail
  accounts.
- **dacct-mail-001.2**: The system MUST support Gmail, work Gmail, and Stalwart
  accounts in the mail account list when configured.
- **dacct-mail-001.3**: Mail account actions MUST remain terminal-first and
  wrap `himalaya` rather than duplicating mail logic in desktop code.
- **dacct-mail-001.4**: The desktop mail menu MUST support showing recent inbox
  envelopes for a selected account.
- **dacct-mail-001.5**: The desktop mail menu MUST support searching mail for a
  selected account.
- **dacct-mail-001.6**: If a configured account cannot be reached or
  authenticated, the menu MUST show an explicit degraded or blocked state rather
  than silently omitting the account.

### Calendar account menu behavior (dacct-calendar-001)

The desktop MUST provide calendar visibility for compatible CalDAV accounts.

- **dacct-calendar-001.1**: The `Accounts` menu MUST show calendar actions only
  for accounts backed by providers compatible with the current Pimalaya CalDAV
  tooling.
- **dacct-calendar-001.2**: Under the current implementation constraints,
  Stalwart calendar accounts MUST be supported when configured.
- **dacct-calendar-001.3**: Calendar account actions MUST remain terminal-first
  and wrap `calendula` rather than duplicating calendar logic in desktop code.
- **dacct-calendar-001.4**: The desktop calendar menu MUST support listing the
  configured calendars for a selected supported account.
- **dacct-calendar-001.5**: The desktop calendar menu MUST support showing
  upcoming events for a selected supported account.
- **dacct-calendar-001.6**: Gmail and work Gmail MUST be treated as mail-only
  accounts in this requirement set and MUST NOT claim calendar support until a
  separate Google OAuth2-capable implementation exists.

### Launcher and process-lifecycle behavior (dacct-launch-001)

The hardware and account menus MUST preserve Keystone's launcher independence
rules.

- **dacct-launch-001.1**: Walker and Elephant MUST remain presentation-layer
  launchers only for these menus.
- **dacct-launch-001.2**: Long-lived terminal, editor, browser, or enrollment
  flows started from `Hardware` or `Accounts` MUST be detached from the Walker
  or Elephant process tree before the target process begins running.
- **dacct-launch-001.3**: Business logic for hardware inspection, hardware-key
  enrollment, and account access MUST live in terminal-first backend commands,
  not in Lua menu files.

### Generated state and personal config repo behavior (dacct-state-001)

Persistent user-specific state generated by these flows MUST follow Keystone's
personal config repo convention.

- **dacct-state-001.1**: If a desktop control in `Hardware` or `Accounts`
  generates persistent user-specific state that does not belong in the keystone
  source repo, that state MUST be written into the user's personal
  `nixos-config` repository or equivalent personal keystone config repo.
- **dacct-state-001.2**: Persisted generated state written by these flows MUST
  remain reviewable and committable from the personal config repo.
- **dacct-state-001.3**: This spec does not require automatic commit or push
  behavior, only the source-of-truth location and reviewability of generated
  state.

## Acceptance criteria

1. `Setup` contains `Hardware` and `Accounts`.
2. `Setup -> Hardware` shows live Secure Boot, `sbctl`, TPM, FIDO2, and
   disk-unlock token state.
3. Starting hardware-key disk-unlock enrollment opens a detached terminal flow.
4. Restarting `walker.service` or `elephant.service` after starting hardware
   enrollment does not stop the enrollment process.
5. Multi-account terminal config supports at least one Stalwart account, one
   Gmail account, and one work Gmail account without breaking compatibility for
   existing single-account config.
6. `Setup -> Accounts` lists all configured mail accounts and supports inbox
   visibility plus search through `himalaya`.
7. `Setup -> Accounts` lists supported calendars and upcoming events through
   `calendula` for compatible accounts such as Stalwart.
8. Gmail and work Gmail are shown as mail-only accounts in this version.

## Affected modules

- `modules/desktop/home/scripts/default.nix`
- `modules/desktop/home/scripts/keystone-setup-menu.sh`
- `modules/desktop/home/components/launcher.nix`
- `modules/terminal/mail.nix`
- `modules/terminal/calendar.nix`
- `modules/os/tpm.nix`
- `modules/os/hardware-key.nix`
