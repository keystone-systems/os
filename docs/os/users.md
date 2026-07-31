---
title: User Configuration
description: Configuring NixOS user accounts with Keystone
---

# User Configuration

## Basic Setup

```nix
keystone.users = {
  alice = {
    uid = 1000;
    fullName = "Alice Smith";
    extraGroups = [ "wheel" ];
    hashedPassword = "$6$...";  # mkpasswd -m sha-512
    zfsProperties = {
      quota = "500G";
      compression = "zstd";
    };
  };
};
```

Creates:

- System user with UID 1000
- ZFS dataset at `rpool/crypt/home/alice`
- Delegated ZFS permissions (snapshot, send, receive, properties)
- Member of zfs group (for /dev/zfs access)

## ZFS Integration

### Datasets

Home directory backed by dedicated ZFS dataset at `rpool/crypt/home/<username>`.

### Permissions

Users can:

- Create snapshots: `zfs snapshot rpool/crypt/home/alice@backup`
- Send/receive: `zfs send ... | ssh backup zfs receive ...`
- Set properties: `zfs set compression=lz4 ...`
- List datasets: `zfs list`

### Mount Limitation

**Linux kernel restricts mounting to root.** Use sudo for dataset creation and mounting:

```bash
# Create and mount child dataset (requires sudo)
sudo zfs create rpool/crypt/home/alice/documents
```

### Snapshot Exclusion

Common datasets auto-created by Keystone modules (future):

- `.cache` - Excluded from snapshots (auto-created by users module)
- `.local/share/containers` - Excluded from snapshots (docker-rootless module)

Users rarely need to manually create ZFS child datasets - most common use cases are snapshots and backups.

## Home Manager (Coming Soon)

### Two Deployment Modes

**System-wide** (NixOS integration):

```nix
# In system configuration
keystone.users.alice.homeManager = {
  programs.helix.enable = true;
  # ... other home-manager config
};
```

- Managed with `nixos-rebuild switch`
- Requires root/sudo
- Changes apply system-wide

**Standalone** (Rootless):

```nix
# In ~/.config/home-manager/home.nix
programs.helix.enable = true;
```

- Updated with `home-manager switch` (no sudo)
- Faster iteration (doesn't rebuild NixOS)
- User controls deployment timing

### Use Cases

**Replaces**: stow, .dotfiles repos, manual config syncing

**Enables**:

- Same shell/lazygit/helix themes on NixOS, macOS, Codespaces
- Corporate environments requiring GitHub Codespaces
- Cross-platform development consistency
- Declarative dotfile management

**Example**: Engineer works on company macOS laptop, uses Codespaces for containerized work, and personal NixOS desktop - all with identical shell/editor configuration managed through home-manager.

## References

- Module implementation: `modules/users/default.nix`
- Complete spec: the legacy `_archive/007-zfs-user-module/` (removed in v1 docs cleanup; see git history)
- ZFS delegation: `man zfs-allow`
- Linux mount limitation: https://github.com/openzfs/zfs/discussions/10648
