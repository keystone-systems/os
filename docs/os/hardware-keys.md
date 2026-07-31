---
title: Hardware Keys (YubiKey/FIDO2)
description: Using hardware security keys for SSH authentication, GPG signing, and secrets management
---

# Hardware Keys (YubiKey/FIDO2)

This guide covers using hardware security keys (YubiKey, SoloKey, etc.) with Keystone for SSH authentication, GPG signing, and secrets management.

## Prerequisites

Enable the hardware-key module in your NixOS configuration:

```nix
keystone.hardwareKey.enable = true;
```

This enables:

- `pcscd` service for smart card communication
- GPG agent with SSH support
- YubiKey management tools (`ykman`, `age-plugin-yubikey`, `pam_u2f`, etc.)

## Multi-Key Strategy (Primary + Backup)

Use two YubiKeys: a **primary** for daily carry and a **backup** stored securely. Distinguish them with color stickers (YubiKey sells sticker packs) and use color names throughout your configuration.

| Key Name     | Role                  | Storage             | Color           |
| ------------ | --------------------- | ------------------- | --------------- |
| `yubi-black` | Primary - daily carry | Keychain            | Black (default) |
| `yubi-green` | Backup - safe storage | Home safe / lockbox | Green sticker   |

Both keys should be enrolled for SSH, age encryption, and authorized on all hosts. If the primary is lost, the backup can decrypt all secrets and re-key without downtime.

### Naming Convention

Use `yubi-<color>` as the key name everywhere:

- NixOS module: `keystone.hardwareKey.keys.yubi-black`, `keystone.hardwareKey.keys.yubi-green`
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

```bash
ssh-keygen -t ed25519-sk -O resident \
  -O application=ssh:ncrmro-yubi-green \
  -C "ncrmro-yubi-green" \
  -f ~/.ssh/id_ed25519_sk_yubi_green
```

- `-O resident` — stores the key on the YubiKey (portable, no key files needed)
- `-O application=ssh:<name>` — namespaces the credential on the YubiKey
- `-C "<name>"` — sets the public key comment (instead of defaulting to `user@hostname`)
- `-f <path>` — where to save the local key handle

Touch the YubiKey and enter the FIDO2 PIN when prompted. You can skip the file passphrase (the YubiKey itself is the second factor).

Export the public key:

```bash
cat ~/.ssh/id_ed25519_sk_yubi_green.pub
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
ssh-keygen -lf ~/.ssh/id_ed25519_sk_yubi_green.pub

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
cat ~/.ssh/id_ed25519_sk_yubi_green.pub
```

For Keystone-side validation of the registered inventory and runtime wiring, run:

```bash
ks hardware-key doctor
ks hardware-key doctor ncrmro/yubi-green --json
```

## Adding a YubiKey to NixOS Configuration

After completing the YubiKey setup above, add the public keys to your NixOS configuration.

### 1. NixOS Module (hardware key declaration)

```nix
keystone.hardwareKey = {
  enable = true;
  keys.yubi-black = {
    description = "Primary YubiKey 5 NFC (USB-A, black)";
    sshPublicKey = "sk-ssh-ed25519@openssh.com AAAAGnNr... ncrmro-yubi-black";
  };
  keys.yubi-green = {
    description = "Backup YubiKey 5C NFC (USB-C, green sticker)";
    sshPublicKey = "sk-ssh-ed25519@openssh.com AAAAGnNr... ncrmro-yubi-green";
  };
  rootKeys = [ "yubi-black" "yubi-green" ];
};
```

### 2. Agenix secrets.nix (age encryption)

```nix
yubikeys = {
  ncrmro-yubi-black = "age1yubikey1q...";  # Serial: 36854515
  ncrmro-yubi-green = "age1yubikey1q...";  # Serial: 36862273
};

adminKeys = [
  users.ncrmro-laptop
  users.ncrmro-workstation
  yubikeys.ncrmro-yubi-black
  yubikeys.ncrmro-yubi-green
];
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

Use `hwrekey` to re-encrypt all secrets and handle the submodule workflow automatically:

```bash
cd agenix-secrets
hwrekey
```

This runs the full workflow:

1. `agenix --rekey` using your YubiKey identity (touch prompt per secret, no SSH password)
2. Commits and pushes the rekeyed secrets in the submodule
3. Runs `nix flake update <secretsFlakeInput>` in the parent repo
4. Commits the submodule pointer + `flake.lock` together in the parent repo

`hwrekey` is provided by `keystone.terminal.ageYubikey` — see the [Terminal Module](terminal.md#hwrekey---secrets-rekeying) docs for configuration.

If you prefer the manual workflow:

```bash
cd agenix-secrets
agenix -r
git add -A && git commit -m "chore: rekey secrets" && git push
cd ..
nix flake update agenix-secrets
git add agenix-secrets flake.lock
git commit -m "chore: update agenix-secrets (rekey)"
```

### 5. Commit and Rebuild

```bash
# In nixos-config (if not already committed by hwrekey)
git add modules/ home-manager/
git commit -m "enroll new YubiKey: <serial>"

# Rebuild
sudo nixos-rebuild switch --flake .#<hostname>
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

Stored directly on the YubiKey — no key files to manage. Plug in your YubiKey on any machine and the key is available.

```bash
# Primary key (black)
ssh-keygen -t ed25519-sk -O resident -O application=ssh:ncrmro-yubi-black -C "ncrmro-yubi-black"

# Backup key (green) — swap YubiKeys and run again
ssh-keygen -t ed25519-sk -O resident -O application=ssh:ncrmro-yubi-green -C "ncrmro-yubi-green" -f ~/.ssh/id_ed25519_sk_yubi_green
```

The `-C` flag sets a descriptive comment (instead of defaulting to `user@hostname`), and `-O application=ssh:<name>` namespaces the credential on the YubiKey.

#### Load Resident Keys into SSH Agent

On any machine with your YubiKey plugged in:

```bash
ssh-add -K
```

This loads all resident SSH keys from the YubiKey into your agent. No key files needed.

#### Automate Key Loading on Shell Startup

Add to your shell configuration (e.g., `~/.zshrc` or via home-manager):

```bash
# Auto-load YubiKey SSH keys if available
if command -v ssh-add &> /dev/null && [ -n "$SSH_AUTH_SOCK" ]; then
  ssh-add -K 2>/dev/null
fi
```

Or with home-manager:

```nix
programs.zsh.initExtra = ''
  # Auto-load YubiKey SSH keys if available
  if command -v ssh-add &> /dev/null && [ -n "$SSH_AUTH_SOCK" ]; then
    ssh-add -K 2>/dev/null
  fi
'';
```

### Non-Resident Keys (Firmware 5.0+)

For older YubiKeys (firmware < 5.2.3) or backup keys. The "private key" file is just a handle — the actual secret never leaves the YubiKey. Safe to store in dotfiles/home-manager.

```bash
# Firmware 5.2.3+ (preferred)
ssh-keygen -t ed25519-sk -O application=ssh:ncrmro-yubi-black -C "ncrmro-yubi-black" -f ~/.ssh/id_ed25519_sk_yubi_black

# Firmware 5.0+ (use if ed25519-sk fails)
ssh-keygen -t ecdsa-sk -O application=ssh:ncrmro-yubi-black -C "ncrmro-yubi-black" -f ~/.ssh/id_ecdsa_sk_yubi_black
```

You'll need to copy the key files to other machines, or manage via home-manager (see below).

#### Managing Non-Resident Keys with Home Manager

For non-resident keys, you can distribute the key handle via home-manager. The "private key" is just a reference — useless without the physical YubiKey.

```nix
# In your home-manager config
home.file.".ssh/id_ed25519_sk_yubikey" = {
  source = ./keys/id_ed25519_sk_yubikey;
  mode = "0600";
};

home.file.".ssh/id_ed25519_sk_yubikey.pub" = {
  source = ./keys/id_ed25519_sk_yubikey.pub;
  mode = "0644";
};

# Add to SSH config
programs.ssh = {
  enable = true;
  matchBlocks."*".identityFile = "~/.ssh/id_ed25519_sk_yubikey";
};
```

Store the key files in your config repo (e.g., `home-manager/keys/`). They're safe to commit — the private key handle is useless without your YubiKey.

### List Keys on YubiKey

```bash
# List resident credentials
ykman fido credentials list

# List keys in SSH agent
ssh-add -L
```

## GPG with YubiKey

The hardware-key module enables GPG agent with SSH support. To use GPG keys stored on YubiKey:

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

### SSH agent not loading keys

```bash
# Check if SSH agent is running
echo $SSH_AUTH_SOCK

# Check agent keys
ssh-add -l

# Try loading manually with verbose output
ssh-add -K -v
```

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
