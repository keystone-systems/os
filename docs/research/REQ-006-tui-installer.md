# Research: TUI Installer for Clusters

**Relates to**: REQ-006 (Clusters, FR-011)

## Decision

Use Charm's Bubbletea (Go) for TUI framework. Elm-inspired architecture with composable Bubbles components (spinner, textinput, list, progress, viewport, table).

## Wizard Steps

1. **Welcome** — Hardware detection (CPU, RAM, disks, TPM, Secure Boot)
2. **Disk Selection** — Choose disk, display size/model
3. **Disk Encryption** — LUKS + ZFS native encryption, TPM2 auto-unlock option, passphrase entry with strength indicator
4. **Network Config** — Static IP or DHCP, Headscale enrollment
5. **Cluster Config** — Generate CA/etcd/admin certs, set hostname
6. **Confirmation** — Review all choices
7. **Installing** — Progress bar + step indicators + log viewport
8. **Complete** — Reboot prompt

## Integration

Generates NixOS configuration files (`hardware-configuration.nix`, `disko-config.nix`, `configuration.nix`) under `/mnt/etc/nixos/`, then calls `nixos-install`.

## Error Handling

Recoverable errors show options: retry step, force (destroy existing), go back, view logs, quit. Fatal errors show diagnostic output.

## Testing

qcow2 VM workflow: build ISO → create empty disk → boot VM → run TUI → verify services post-reboot. Automated via keystroke injection and screen capture.

## Why Bubbletea over Alternatives

- tview: widget-based, less flexible for multi-step wizards
- ratatui (Rust): team expertise is in Go
- gocui: too low-level, would need to build everything
