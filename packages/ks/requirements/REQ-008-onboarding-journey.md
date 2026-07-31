# REQ-008: Onboarding Journey

This document defines the end-to-end onboarding flow that takes a new
user from zero to a fully deployed, secured NixOS system. The journey
spans multiple sessions and machines.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Overview

The onboarding journey has seven stages across two machines:

| Stage | Where | Section | Description |
|-------|-------|---------|-------------|
| 1 | Dev machine | Template | Generate NixOS config from user info |
| 2 | Dev machine | Publish | Git init + push to GitHub |
| 3 | Dev machine | Installer | Build ISO + burn to USB |
| 4 | Target machine | Install (ISO) | Disk setup + nixos-install + hardware capture + local commit |
| 5 | Target machine | First Boot | Secure Boot + TPM enrollment |
| 6 | Target machine | Security | SSH keys + push + secrets |
| 7 | Target machine | Services | Service placement + onboarding |

## Stage 1: Template

**REQ-008.1** When no repositories are configured, the TUI MUST present
the welcome screen with options to import an existing repo or create a
new config from the template.

**REQ-008.2** The template flow MUST collect at minimum: hostname, host
kind (server/workstation/laptop), username, and password.

**REQ-008.3** When a GitHub username is provided, the TUI MUST fetch the
user's display name and SSH public keys from the GitHub API and populate
the template `owner` and `authorizedKeys` fields automatically.

**REQ-008.4** The template MUST produce config version `1.0.0`
(`keystone.lib.mkSystemFlake` format) with the `hosts/<hostname>/`
directory layout.

## Stage 2: Publish

**REQ-008.5** After template generation, the TUI MUST initialize a git
repository and create an initial commit.

**REQ-008.6** The TUI SHOULD offer to create a private GitHub repository
via `gh repo create` and push the initial commit.

**REQ-008.7** The TUI MUST warn the user if `initialPassword` is present
in plaintext before pushing.

## Stage 3: Build + Burn ISO

**REQ-008.8** The Installer sidebar section MUST allow the user to select
a host and install profile (Desktop or Server).

**REQ-008.9** The ISO MUST bake in: the user's NixOS config (flake.nix +
hosts/ directory), SSH public keys for root access, NetworkManager for
wired and WiFi connectivity, the ks installer, and disko +
nixos-install tooling.

**REQ-008.10** The Installer SHOULD detect removable USB block devices
and allow the user to write the built ISO directly to a selected device.

**REQ-008.11** The Installer MAY support an airgapped mode that
pre-fetches all derivation closures into the ISO for offline installs.

## Stage 4: Install (target machine, booted from ISO)

**REQ-008.12** The TUI MUST auto-start on tty1 when booted from a
Keystone ISO and detect embedded config at `/etc/keystone/install-config/`.

**REQ-008.13** The install flow MUST treat
`/etc/keystone/install-config/` as immutable input and copy it into a
fresh writable staging directory before any mutation or installation
step begins.

**REQ-008.14** When deferred disk selection is used
(`__KEYSTONE_DISK__` placeholder), the selected disk MUST be written
only into that writable staged copy. The installer MUST NOT attempt to
edit the embedded `/etc/keystone/install-config/` tree in place.

**REQ-008.15** If the installer cannot create or write the staged config
copy, it MUST fail early with a clear error before partitioning begins.

**REQ-008.16** The install flow MUST: show config summary, allow disk
selection, confirm before erasing, run disko for partitioning, run
`nixos-generate-config --root /mnt --show-hardware-config`, record the
local install commit, and only then run `nixos-install` with the embedded
configuration.

**REQ-008.17** After `disko` mounts the target system and before
`nixos-install` begins, the TUI MUST run
`nixos-generate-config --root /mnt --show-hardware-config` to detect
actual hardware and update the host hardware config committed for the
install.

**REQ-008.18** The installer MUST stage and create a local git commit in
the writable install repo before `nixos-install`. That commit MUST
include the reconciled host hardware config and any install-time config
mutations required to boot and continue onboarding. The installer MUST
NOT attempt to push — the ISO does not contain private SSH keys.

**REQ-008.19** The installer MUST write a `.first-boot-pending` marker to
the installed system's config directory only after the pre-install
hardware reconciliation, local commit, `nixos-install`, and repo handoff
succeed, so the first-boot flow triggers on next login with a committed
baseline config.

## Stage 5: First Boot (target machine, installed system)

**REQ-008.20** On first boot, the TUI MUST detect the `.first-boot-pending`
marker and enter the first-boot wizard.

**REQ-008.21** The first-boot wizard MUST guide the user through Secure
Boot key enrollment via `sbctl enroll-keys --microsoft`.

**REQ-008.22** The first-boot wizard MUST guide the user through TPM2
enrollment for automatic disk unlock.

**REQ-008.23** After Secure Boot and TPM enrollment, the TUI SHOULD
prompt the user to reboot so the new security settings take effect.

## Stage 6: Security + Keys (target machine, after security reboot)

**REQ-008.24** The TUI MUST detect when Secure Boot and TPM are enrolled
and skip those steps on subsequent boots.

**REQ-008.25** The TUI MUST guide the user through SSH key setup. Options
MUST include: importing public keys from GitHub, generating a new
ed25519 key pair, or enrolling a FIDO2 hardware key (YubiKey) via
`ssh-keygen -t ed25519-sk`.

**REQ-008.26** Once SSH keys are configured, the TUI MUST prompt the user
to push the pending install commit from Stage 4 to the remote repository.

**REQ-008.27** The TUI SHOULD guide the user through initializing agenix
secrets for the system.

## Stage 7: Services + Onboarding (target machine)

**REQ-008.28** The TUI SHOULD present the Services screen showing which
`keystoneServices` are available and which host they are assigned to.

**REQ-008.29** The TUI SHOULD guide the user through creating secrets
required by enabled services.

**REQ-008.30** The TUI SHOULD present a brief onboarding tutorial or
next-steps summary after all setup is complete.

**REQ-008.31** After the full onboarding journey is complete, the TUI
MUST clear the `.first-boot-pending` marker and transition to the
normal hosts dashboard on subsequent launches.
