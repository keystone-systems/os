# Keystone VM Configurations

This directory contains various VM configurations for testing Keystone.

## Overview

There are two types of VM testing workflows:

### 1. Fast Testing with `build-vm` (Recommended for Config Testing)

**Use for**: Rapid iteration on desktop and terminal configurations

**Configurations**:

- `build-vm-terminal/` - Terminal development environment only
- `build-vm-desktop/` - Full Hyprland desktop with terminal dev environment

**Usage**:

```bash
# Terminal dev environment - auto-SSH into VM
./bin/build-vm terminal

# Hyprland desktop - open graphical console
./bin/build-vm desktop

# Build only, don't connect
./bin/build-vm terminal --build-only
```

**Characteristics**:

- Uses `nixos-rebuild build-vm`
- **Automatic connection** - Terminal auto-SSHs, Desktop opens console
- Mounts host Nix store via 9P (read-only)
- No encryption, secure boot, or TPM
- Fast iteration (~minutes)
- Persistent qcow2 disk images
- Direct QEMU execution (no libvirt)
- Terminal: SSH forwarded to `localhost:2222`

### 2. Full Stack Testing with `test-deployment` (For Complete Testing)

**Use for**: Testing the complete security stack

**Configurations**:

- `test-server/` - Server configuration with ZFS encryption, secure boot, TPM
- `test-hyprland/` - Hyprland desktop with ZFS encryption, secure boot, TPM

**Usage**:

```bash
./bin/test-deployment
```

**Characteristics**:

- Uses `nixos-anywhere` for deployment
- Full ZFS encryption with credstore pattern
- Secure boot with custom key enrollment
- TPM2 automatic unlock
- Initrd SSH unlock
- Complete testing (~20-30 minutes)
- Libvirt VM management

## Configuration Details

### build-vm-terminal

**Flake Output**: `.#build-vm-terminal`

**Features**:

- Minimal NixOS system
- Terminal development environment (home-manager)
  - Helix editor
  - Zsh shell with utilities
  - Zellij terminal multiplexer
  - Ghostty terminal emulator
  - Git with UI tools
- Simple networking (DHCP)
- No encryption or secure boot

**Credentials**:

- User: `testuser` / Password: `testpass`
- Root: `root` / Password: `root`

**Build**:

```bash
nixos-rebuild build-vm --flake .#build-vm-terminal
./result/bin/run-build-vm-terminal-vm
```

### build-vm-desktop

**Flake Output**: `.#build-vm-desktop`

**Features**:

- Full Hyprland desktop environment
  - Hyprland Wayland compositor
  - Waybar status bar
  - Mako notifications
  - greetd login manager
  - PipeWire audio
- Terminal development environment
- Desktop applications (Firefox, VSCode, VLC)
- NetworkManager with Bluetooth
- No encryption or secure boot

**Credentials**:

- User: `testuser` / Password: `testpass`
- Root: `root` / Password: `root`

**Build**:

```bash
nixos-rebuild build-vm --flake .#build-vm-desktop
./result/bin/run-build-vm-desktop-vm
```

**VM Resources**:

- Memory: 4GB
- CPUs: 2 cores
- 3D acceleration enabled

### test-server

**Flake Output**: `.#test-server`

**Features**:

- ZFS encryption with credstore pattern
- Secure boot with lanzaboote
- TPM2 enrollment and automatic unlock
- Initrd SSH unlock
- Complete server security stack

**Deployment**:

```bash
./bin/test-deployment
```

### test-hyprland

**Flake Output**: `.#test-hyprland`

**Features**:

- Full Hyprland desktop environment
- ZFS encryption with credstore pattern
- Secure boot with lanzaboote
- TPM2 enrollment and automatic unlock
- Initrd SSH unlock
- Terminal development environment
- Complete client security stack

**Deployment**:

```bash
./bin/test-deployment
```

## Workflow Comparison

| Feature         | build-vm                 | test-deployment    |
| --------------- | ------------------------ | ------------------ |
| Build Time      | ~2-5 minutes             | ~20-30 minutes     |
| Disk Encryption | No                       | Yes (ZFS + LUKS)   |
| Secure Boot     | No                       | Yes                |
| TPM             | No                       | Yes                |
| Initrd SSH      | No                       | Yes                |
| Use Case        | Config testing           | Full stack testing |
| VM Type         | QEMU direct              | Libvirt            |
| Nix Store       | 9P mount                 | Copied             |
| Disk Image      | qcow2                    | qcow2              |
| Best For        | Desktop/terminal configs | Security features  |

## Common Tasks

### Quick Desktop Config Test

```bash
# Edit desktop configuration
vim modules/client/desktop/hyprland.nix

# Rebuild and auto-connect to graphical console
./bin/build-vm desktop
```

### Quick Terminal Config Test

```bash
# Edit home-manager config
vim home-manager/modules/terminal-dev-environment/default.nix

# Rebuild and auto-SSH into VM
./bin/build-vm terminal
```

### Full Security Stack Test

```bash
# Test complete deployment
./bin/test-deployment

# SSH to test VM
./bin/test-vm-ssh
```

### Clean VM Artifacts

```bash
# Clean build-vm artifacts
./bin/build-vm terminal --clean
./bin/build-vm desktop --clean
rm -f build-vm-*.qcow2

# Reset libvirt VM
./bin/virtual-machine --reset keystone-test-vm
```

## Tips

1. **Use build-vm for rapid iteration** - When working on desktop or terminal configs, use build-vm for much faster feedback
2. **Use test-deployment for verification** - Before committing security-related changes, test with the full stack
3. **Keep VMs separate** - build-vm and test-deployment use different VM systems and don't interfere
4. **Persistent disks** - Both types create persistent disks that survive reboots
5. **Clean regularly** - Remove old qcow2 images to save disk space

## Troubleshooting

### build-vm Issues

**Problem**: "module not found" errors

- Check flake.nix has the correct module imports
- Ensure you're in the keystone directory

**Problem**: VM won't start

- Check if `result/bin/run-build-vm-*-vm` exists
- Ensure KVM is available: `ls -la /dev/kvm`

**Problem**: SSH connection times out (terminal VM)

- Check if VM is running: `ps aux | grep qemu`
- Check if port 2222 is in use: `lsof -i :2222`
- Try manual connection: `ssh -p 2222 testuser@localhost`
- Check VM console: `./result/bin/run-build-vm-terminal-vm`

**Problem**: Display issues in desktop VM

- Ensure you have X11 or Wayland display available
- Check QEMU display options in configuration

**Problem**: Terminal VM still running after disconnect

- This is expected - VM runs in background
- Reconnect: `ssh -p 2222 testuser@localhost`
- Stop VM: `kill $(cat build-vm-terminal.pid)`
- Or find and kill: `ps aux | grep build-vm-terminal`

### test-deployment Issues

**Problem**: VM creation fails

- Check libvirt is running: `systemctl status libvirtd`
- Ensure keystone-net network exists

**Problem**: TPM enrollment fails

- This is expected on first deployment
- TPM enrollment happens in later test step

## See Also

- [../bin/build-vm](../bin/build-vm) - Fast VM testing script
- [../bin/test-deployment](../bin/test-deployment) - Full deployment test script
- [../bin/virtual-machine](../bin/virtual-machine) - Libvirt VM management
- [../CLAUDE.md](../CLAUDE.md) - Full project documentation
