# OS Module — Editing Guide (`modules/os/`)

This guide covers conventions for editing the OS module. For the full user-facing
reference (option schemas, examples, deployment patterns), see `docs/os-agents.md`.

## Storage (`storage.nix`)

ZFS with LUKS credstore is the primary pattern. Pool is **always** named `rpool`.

```nix
keystone.os.storage = {
  type = "zfs";  # or "ext4"
  devices = [ "/dev/disk/by-id/nvme-..." ];
  mode = "single";  # single, mirror, stripe, raidz1, raidz2, raidz3
  esp.size = "1G";
  swap.size = "8G";
  credstore.size = "100M";  # LUKS volume for ZFS encryption keys
  zfs = { compression = "zstd"; atime = "off"; arcMax = "4G";
          autoSnapshot = true; autoScrub = true; };
};
```

**Boot sequence** (ZFS): Import pool → Unlock credstore (TPM or password) → Load ZFS key → Mount encrypted datasets.

**ext4 alternative**: LUKS-encrypted ext4 with optional hibernate. No snapshots/compression.

## Users (`users.nix`)

```nix
keystone.os.users.alice = {
  fullName = "Alice Smith";
  email = "alice@example.com";
  extraGroups = [ "wheel" "networkmanager" ];
  authorizedKeys = [ "ssh-ed25519 AAAAC3..." ];
  hardwareKeys = [ "yubi-black" ];    # References keystone.hardwareKey.keys
  hashedPassword = "$6$...";          # mkpasswd -m sha-512
  terminal.enable = true;             # Full keystone.terminal environment
  desktop.enable = false;
  zfs = { quota = "100G"; compression = "lz4"; };
};
```

Users with `terminal.enable` get the full home-manager terminal environment.
Users with `desktop.enable` additionally get Hyprland.

## Hypervisor (`hypervisor.nix`)

```nix
keystone.os.hypervisor = {
  enable = true;
  defaultUri = "qemu:///session";
};
```

Provides: OVMF (Secure Boot), swtpm (TPM 2.0 emulation), SPICE display, polkit rules
for `libvirtd` group. All `keystone.os.users` auto-added to `libvirtd` group.

## Hardware Keys (`hardware-key.nix`)

```nix
keystone.hardwareKey = {
  enable = true;
  keys.yubi-black = {
    description = "Primary YubiKey 5 NFC";
    sshPublicKey = "sk-ssh-ed25519@openssh.com AAAAC3...";
    ageIdentity = "AGE-PLUGIN-YUBIKEY-...";  # Optional, for agenix
  };
  rootKeys = [ "yubi-black" ];
  gpgAgent = { enable = true; enableSSHSupport = true; };
};
```

**Services enabled**: pcscd (smart card daemon), GPG agent with SSH support.
**Tools**: `ykman`, `age-plugin-yubikey`, `pam_u2f`, `yubico-piv-tool`.

See `docs/hardware-keys.md` for enrollment workflow.

## Other OS Services

| Service          | Option                                 | Key Detail                               |
| ---------------- | -------------------------------------- | ---------------------------------------- |
| SSH              | `keystone.os.ssh.enable`               | No password auth, no root password login |
| Eternal Terminal | `keystone.os.services.eternalTerminal` | Port 2022, Tailscale-only                |
| AirPlay          | `keystone.os.services.airplay`         | Shairport Sync                           |
| systemd-resolved | `keystone.os.services.resolved`        | Required for Tailscale MagicDNS          |
| Containers       | `keystone.os.containers.enable`        | Podman + fuse-overlayfs for ZFS          |
| Tailscale        | `keystone.os.tailscale`                | VPN client                               |
| iPhone Tether    | `keystone.os.iphoneTether.enable`      | libimobiledevice + usbmuxd               |
| Ollama           | `keystone.os.ollama`                   | LLM runtime                              |
| Mail             | `keystone.mail.host`                   | Stalwart (auto-enables on matching host) |
| Git Server       | `keystone.os.gitServer`                | Forgejo + agent repo provisioning        |
| Journal Remote   | `keystone.os.journalRemote`            | Port 19532, Tailscale-only               |

## Deployment Patterns

**Headless server**: `keystone.os.enable = true; keystone.server.enable = true;`

**Workstation**: `keystone.os.enable = true; keystone.os.users.alice.desktop.enable = true;`

**Multi-service server**: Set `keystone.domain`, `keystone.server.tailscaleIP`, enable services.

## Development and Testing

- `bash packages/ks/ks.sh doctor` — run `ks` directly without rebuilding (it's a plain shell script)
- `agentctl` uses `replaceVars` and **cannot** be tested without a rebuild
- `./bin/build-vm terminal` — fast VM with host Nix store mounted via 9P
- `./bin/virtual-machine --name keystone-test-vm --start` — full Libvirt VM with Secure Boot + TPM

See `docs/testing-vm.md` for full VM testing procedure.

## Agent Provisioning

For agent-specific options and provisioning, see `modules/os/agents/AGENTS.md`.
