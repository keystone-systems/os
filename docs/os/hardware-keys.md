---
title: Hardware Keys (YubiKey/FIDO2)
description: Using hardware security keys for SSH authentication, GPG signing, and secrets management
---

# Hardware Keys (YubiKey/FIDO2)

This guide covers using hardware security keys (YubiKey, SoloKey, etc.) with Keystone for SSH authentication, GPG signing, and secrets management.

## Prerequisites

Enable each hardware key by its stable name and numeric serial:

```nix
keystone.hardwareKeys = {
  yubi-black = "36854515";
  yubi-green = "36862273";
};
```

This enables:

- `pcscd` for smart-card communication.
- FIDO2 device access.
- YubiKey management tools such as `ykman` and `age-plugin-yubikey`.

## Multi-Key Strategy (Carry + Deskside)

Use two YubiKeys: a **primary** for daily carry and a **second** that is always available — either stored securely off-site as a backup, or kept at the workstation as a deskside key. Pick deliberately; the two have different threat models (see the note under the table). Distinguish them with color stickers (YubiKey sells sticker packs) and use color names throughout your configuration.

| Key Name     | Role                   | Storage        | Color           | Serial     |
| ------------ | ---------------------- | -------------- | --------------- | ---------- |
| `yubi-black` | Primary - daily carry  | Keychain       | Black (default) | `36854515` |
| `yubi-green` | Deskside - stays put   | At workstation | Green sticker   | `36862273` |

`yubi-green` is a deskside key, not an off-site backup: it stays at the
workstation rather than living in a safe. That keeps a second key always within
reach for unlock and re-keying, but it means neither key is stored away from the
machine — an attacker with physical desk access has the deskside key too, so for
disk unlock it is closer to a convenience factor than an independent one. If you
want a true lost-both-keys recovery path, it has to be something other than
these two (recovery passphrase, or a third key stored elsewhere).

Both of ncrmro's keys are physically identical — YubiKey 5C NFC, firmware
5.7.4, form factor Keychain (USB-C), AAGUID
`d7781e5d-e353-46aa-afe2-3ca49f13332a` (verified 2026-08-02). The connector is
therefore useless for telling them apart: rely on the sticker physically and on
the serial in tooling. Note that USB does not expose the serial in its
descriptors, so `/sys/bus/usb/devices/*/serial` is empty for both and a
`hidraw` path cannot be mapped back to a serial — enroll one key at a time.

Both keys should be enrolled for SSH, age encryption, and authorized on all hosts. If the primary is lost, the second key can decrypt all secrets and re-key without downtime.

### Naming Convention

Use `yubi-<color>` as the key name everywhere:

- NixOS module: `keystone.hardwareKeys.yubi-black`, `keystone.hardwareKeys.yubi-green`
- SSH application: `-O application=ssh:ncrmro-yubi-black`, `-O application=ssh:ncrmro-yubi-green`
- SSH comment: `-C "ncrmro-yubi-black"`, `-C "ncrmro-yubi-green"`
- Age identity labels in config comments: `# Serial: XXXXX, yubi-black`

## New YubiKey Setup

Complete these steps on each new YubiKey before adding it to your NixOS configuration. All steps require the YubiKey to be physically plugged in.

### Step 1: Verify the YubiKey

```bash
ykman info
```

Note the **serial number** and **firmware version**. Firmware 5.2.3+ is required for ed25519-sk resident keys.

### Step 2: Set FIDO2 PIN

The FIDO2 PIN is required for SSH key generation and authentication.

```bash
ykman fido access change-pin
```

Choose a memorable PIN (minimum 4 characters). This PIN is entered when using FIDO2 SSH keys.

### Step 3: Set PIV PIN and PUK

The PIV PIN and PUK are used by `age-plugin-yubikey` for age encryption. The defaults are `123456` (PIN) and `12345678` (PUK) — change them immediately.

```bash
# Change PIV PIN (default: 123456)
ykman piv access change-pin

# Change PIV PUK (default: 12345678)
ykman piv access change-puk
```

The **PIN** is entered during age encrypt/decrypt operations. The **PUK** is used to reset the PIN if it gets locked out.

### Step 4: Set PIV Management Key

The PIV management key must use TDES and be protected (stored on the YubiKey itself, unlocked by PIN). This is required for `age-plugin-yubikey` to work.

```bash
ykman piv access change-management-key -a TDES --protect
```

If the key is factory-fresh, the default management key is:
`010203040506070801020304050607080102030405060708`

The `--protect` flag stores the management key on the YubiKey and gates it behind the PIV PIN, so you don't need to remember or store the management key separately.

### Step 5: Generate Resident SSH Key

Run these commands from the consumer configuration repository:

```bash
mkdir -p hardware-keys
ssh-keygen -t ed25519-sk -O resident \
  -O application=ssh:ncrmro-yubi-green \
  -C "ncrmro-yubi-green" \
  -f hardware-keys/yubi-green
```

- `-O resident` stores the credential on the YubiKey.
- `-O application=ssh:<name>` gives the credential a unique name.
- `-C "<name>"` sets the public-key description.
- `-f <path>` writes the local security-key handle and public key.

Touch the YubiKey and enter the FIDO2 PIN when prompted. You can omit the file
passphrase. The handle cannot sign without the physical YubiKey.

Export the public key:

```bash
cat hardware-keys/yubi-green.pub
```

Save this — it goes in your NixOS configuration.

### Step 6: Generate Age Identity

```bash
age-plugin-yubikey
```

When prompted:

- **Slot**: Choose `1`
- **PIN policy**: `once` (enter PIN once per session)
- **Touch policy**: `always` (touch YubiKey for each encrypt/decrypt)

It outputs two values:

- **Identity** (private): `AGE-PLUGIN-YUBIKEY-1...` — goes in home-manager config
- **Recipient** (public): `age1yubikey1q...` — goes in `secrets.nix`

Save both.

### Step 7: Record in Hardware Inventory

Update your hardware key inventory with:

```bash
# Serial number
ykman info

# SSH fingerprint
ssh-keygen -lf hardware-keys/yubi-green.pub

# Age public key
age-plugin-yubikey --list
```

### Verification

Confirm everything is set up:

```bash
# FIDO2 credentials
ykman fido credentials list

# PIV certificates (age identity)
ykman piv info

# SSH public key
cat hardware-keys/yubi-green.pub
```

For Keystone-side validation of the registered inventory and runtime wiring, run:

```bash
ks hardware-key doctor
ks hardware-key doctor ncrmro/yubi-green --json
```

## Adding a YubiKey to NixOS Configuration

After completing the YubiKey setup above, add the public keys to your NixOS configuration.

### 1. NixOS Module (hardware key declaration)

The serial enables the key. The public registration authorizes root access.
The key registry supplies the local OpenSSH handle.

```nix
keystone.hardwareKeys.yubi-green = "36862273";

keystone.hardwareKeyRegistrations.yubi-green = {
  owner = "ncrmro";
  sshPublicKeys = [
    "sk-ssh-ed25519@openssh.com AAAAGnNr... ncrmro-yubi-green"
  ];
};

# In modules/keys.nix:
keystone.keys.ncrmro.hardwareKeys.yubi-green = {
  description = "Deskside YubiKey 5C NFC, serial 36862273";
  publicKey = "sk-ssh-ed25519@openssh.com AAAAGnNr... ncrmro-yubi-green";
  handleSource = ../hardware-keys/yubi-green;
};
```

You MAY keep `hardware-keys/yubi-green.pub` as inventory evidence. Keystone
generates the installed `.pub` file from `publicKey`. You MUST NOT configure a
second public-key source for the handle.

### 2. Admin recipients (age encryption)

Admin recipients live in the consumer repo's `secrets/recipients.nix` (see
`conventions/secrets.md`); `ks secrets sync` folds them into the generated
`.sops.yaml`:

```nix
admins = {
  yubi-black = "age1yubikey1q...";  # Serial: 36854515
  yubi-green = "age1yubikey1q...";  # Serial: 36862273
  ncrmro-laptop = "ssh-ed25519 AAAA...";
  ncrmro-workstation = "ssh-ed25519 AAAA...";
};
```

### 3. Home Manager (age identity file)

```nix
keystone.terminal.ageYubikey = {
  enable = true;
  identities = [
    "AGE-PLUGIN-YUBIKEY-17DDRYQ..."  # Serial: 36854515, Slot: 1 (yubi-black)
    "AGE-PLUGIN-YUBIKEY-1A2B3C4..."  # Serial: 36862273, Slot: 1 (yubi-green)
  ];
};
```

### 4. Re-key All Secrets

Use `ks secrets rekey` from the consumer repo to regenerate `.sops.yaml` and
re-encrypt every sops file to the current recipient set (touch prompt per
file, no SSH password):

```bash
ks secrets rekey
git add .sops.yaml secrets/
git commit -m "chore: rekey secrets"
```

The YubiKey identity file is provided by `keystone.terminal.ageYubikey` — see the [Terminal Module](terminal.md#secrets-rekeying-ks-secrets-rekey) docs for configuration.

### 5. Commit and Rebuild

```bash
# In the consumer repo
git add modules/keys.nix modules/hardware-keys.nix \
  hardware-keys/yubi-green hardware-keys/yubi-green.pub
git commit -m "enroll new YubiKey: <serial>"

# Deploy from the primary consumer clone
cd ~/repos/ncrmro/ks-config
ks-dev HOST
```

## SSH Key Details

### Firmware Requirements

| Feature                   | Firmware Required |
| ------------------------- | ----------------- |
| ECDSA-SK (non-resident)   | 5.0+              |
| Ed25519-SK (non-resident) | 5.2.3+            |
| Resident keys             | 5.2.3+            |

Check your firmware: `ykman info`

**Note:** YubiKey firmware cannot be updated. If you have firmware < 5.2.3, use `ecdsa-sk` instead of `ed25519-sk`.

### Resident Keys (Firmware 5.2.3+)

The signing key stays on the YubiKey. `ssh-keygen` also writes a small handle
file. The handle identifies the resident credential. The handle does not
contain the signing key.

Generate one handle at a time with the command in
[Step 5](#step-5-generate-resident-ssh-key). Remove the first YubiKey before
you generate a credential on the second YubiKey.

#### Select the Connected Key for Root SSH

Store each handle in the consumer configuration:

```nix
keystone.hardwareKeys.yubi-black = "12345";

keystone.hardwareKeyRegistrations.yubi-black = {
  owner = "alice";
  sshPublicKeys = [ "sk-ssh-ed25519@openssh.com AAAA..." ];
};

# In modules/keys.nix:
keystone.keys.alice.hardwareKeys.yubi-black = {
  publicKey = "sk-ssh-ed25519@openssh.com AAAA...";
  handleSource = ../hardware-keys/yubi-black;
};
```

Keystone installs the handle at
`~/.ssh/id_ed25519_sk_yubi-black`. Keystone also generates an OpenSSH
`Match exec` rule. The rule uses `ykman list --serials` to add the handle only
when that YubiKey is connected.

This selection applies to every destination when the remote user is `root`.
It includes raw IP addresses. It does not change non-root SSH. Root SSH ignores
the SSH agent and software identity files. The connection fails when no
registered YubiKey is present.

Do not add these handles to `ssh-agent` at session start. The generated
OpenSSH rules replace that loading step.

### Non-Resident Keys (Firmware 5.0+)

For older YubiKeys (firmware < 5.2.3) or backup keys. The "private key" file is just a handle — the actual secret never leaves the YubiKey. Safe to store in dotfiles/home-manager.

```bash
# Firmware 5.2.3+ (preferred)
ssh-keygen -t ed25519-sk -O application=ssh:ncrmro-yubi-black -C "ncrmro-yubi-black" -f hardware-keys/yubi-black

# Firmware 5.0+ (use if ed25519-sk fails)
ssh-keygen -t ecdsa-sk -O application=ssh:ncrmro-yubi-black -C "ncrmro-yubi-black" -f hardware-keys/yubi-black
```

Use the same `handleSource` option for a non-resident key. The signing secret
stays on the YubiKey.

### List Keys on YubiKey

```bash
# List resident credentials
ykman fido credentials list

# List the serials that OpenSSH selection uses
ykman list --serials
```

## GPG with YubiKey

To use GPG keys stored on a YubiKey:

```bash
# Check YubiKey GPG status
gpg --card-status

# Import public key (if not already in keyring)
gpg --import publickey.asc

# Trust the key
gpg --edit-key <KEY_ID>
> trust
> 5
> quit
```

### SSH via GPG Agent

If you have SSH keys on your YubiKey's GPG applet:

```bash
# Get SSH public key from GPG
gpg --export-ssh-key <KEY_ID>

# Add to ~/.ssh/authorized_keys on remote hosts
```

## Troubleshooting

### YubiKey not detected

```bash
# Check if pcscd is running
systemctl status pcscd

# Check USB devices
lsusb | grep -i yubi

# Restart pcscd
sudo systemctl restart pcscd
```

### Root SSH selects the wrong key

```bash
# List the connected YubiKey serials
ykman list --serials

# Show the effective root SSH identities
ssh -G root@192.0.2.1 | grep -E '^(identityfile|identityagent|identitiesonly) '

# Show key-selection details without changing the remote host
ssh -vvv root@192.0.2.1
```

The effective configuration MUST contain `identityfile none` and
`identityagent none`. It MUST list only the handles for connected registered
YubiKeys. Do not load these handles with `ssh-add`.

### GPG card not found

```bash
# Restart GPG agent
gpgconf --kill gpg-agent
gpg --card-status
```

### age-plugin-yubikey: "Custom unprotected non-TDES management keys are not supported"

The PIV management key needs to be TDES and protected. Fix with:

```bash
ykman piv access change-management-key -a TDES --protect
```

If the key is factory-fresh, the default management key is:
`010203040506070801020304050607080102030405060708`

Then retry `age-plugin-yubikey`.

## References

- [YubiKey SSH Guide](https://developers.yubico.com/SSH/)
- [FIDO2 Resident Keys](https://developers.yubico.com/WebAuthn/WebAuthn_Developer_Guide/Resident_Keys.html)
- [age-plugin-yubikey](https://github.com/str4d/age-plugin-yubikey)
