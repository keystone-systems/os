# REQ-002: Template Data Model

This document defines the input data model that drives config generation.
All inputs map to `keystone.os.*` NixOS module options.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Requirements

### System Identity

**REQ-002.1** The data model MUST include `hostname` (string, REQUIRED).
Maps to `networking.hostName`.

**REQ-002.2** The data model MUST include `hostId` (8-character hex string,
REQUIRED). Maps to `networking.hostId`. Required by ZFS; included for ext4
for consistency.

**REQ-002.3** The data model MUST include `stateVersion` (string, REQUIRED).
Maps to `system.stateVersion`. Defaults to the current NixOS release.

**REQ-002.4** The data model SHOULD include `timeZone` (string, OPTIONAL).
Maps to `time.timeZone`. Defaults to `"UTC"`.

### Storage Configuration

**REQ-002.5** The data model MUST include `storage.type` (enum: `"zfs"` |
`"ext4"`, REQUIRED). Maps to `keystone.os.storage.type`.

**REQ-002.6** The data model MUST include `storage.devices` (list of strings,
REQUIRED, at least one entry). Maps to `keystone.os.storage.devices`. Values
SHOULD be `/dev/disk/by-id/` paths.

**REQ-002.7** The data model SHOULD include `storage.mode` (enum: `"single"`
| `"mirror"` | `"stripe"` | `"raidz1"` | `"raidz2"` | `"raidz3"`, OPTIONAL).
Maps to `keystone.os.storage.mode`. Defaults to `"single"`.

**REQ-002.8** The data model SHOULD include `storage.swap.size` (string,
OPTIONAL). Maps to `keystone.os.storage.swap.size`. Defaults to `"16G"`.

**REQ-002.9** The data model MAY include `storage.hibernate.enable` (boolean,
OPTIONAL). Maps to `keystone.os.storage.hibernate.enable`. Only valid when
`storage.type` is `"ext4"`.

### Security

**REQ-002.10** The data model SHOULD include `secureBoot.enable` (boolean,
OPTIONAL). Maps to `keystone.os.secureBoot.enable`. Defaults to `true`.

**REQ-002.11** The data model SHOULD include `tpm.enable` (boolean,
OPTIONAL). Maps to `keystone.os.tpm.enable`. Defaults to `true`.

**REQ-002.12** The data model MAY include `remoteUnlock.enable` (boolean,
OPTIONAL). Maps to `keystone.os.remoteUnlock.enable`. Defaults to `false`.

**REQ-002.13** The data model MAY include `remoteUnlock.authorizedKeys`
(list of strings, OPTIONAL). Maps to
`keystone.os.remoteUnlock.authorizedKeys`.

### Users

**REQ-002.14** The data model MUST include `users` (attribute set, REQUIRED,
at least one entry). Each key is the username, mapping to
`keystone.os.users.<name>`.

**REQ-002.15** Each user MUST include `fullName` (string, REQUIRED).

**REQ-002.16** Each user SHOULD include `email` (string, OPTIONAL).

**REQ-002.17** Each user MUST include exactly one authentication method:
`initialPassword` (string) or `hashedPassword` (string).

**REQ-002.18** Each user SHOULD include `authorizedKeys` (list of strings,
OPTIONAL). Maps to SSH public keys for the user.

**REQ-002.19** Each user SHOULD include `extraGroups` (list of strings,
OPTIONAL). Defaults to `["wheel"]` for the first user.

**REQ-002.20** Each user MAY include `terminal.enable` (boolean, OPTIONAL).
Defaults to `true`.

**REQ-002.21** Each user MAY include `desktop.enable` (boolean, OPTIONAL).
Defaults to `false`.

**REQ-002.22** Each user MAY include `desktop.hyprland.modifierKey` (string,
OPTIONAL). Defaults to `"SUPER"`.
