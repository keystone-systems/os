# REQ-006: Remote Connection

This document defines requirements for network discovery and remote
deployment of Keystone ISO installer instances.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Requirements

### mDNS / Avahi Discovery

**REQ-006.1** The Keystone ISO MUST broadcast an Avahi/mDNS service
(`_keystone-iso._tcp.local`) so the dev machine TUI can discover booted
installer instances on the local network.

**REQ-006.2** The dev machine TUI SHOULD monitor for Keystone ISO mDNS
broadcasts and display discovered instances in the Installer section.

**REQ-006.3** The TUI MUST accept a target IP address for manual
connection when mDNS auto-detection is unavailable.

### Remote Deployment

**REQ-006.4** The TUI MUST deploy the generated configuration to the
target machine via `nixos-anywhere --flake .#<hostname> root@<ip>`.

**REQ-006.5** The TUI SHOULD auto-detect local SSH keys and offer them
for the deployment connection.

**REQ-006.6** The TUI MUST display deployment progress and surface
errors from `nixos-anywhere` to the user.

### Remote Hardware Detection

**REQ-006.7** When deploying remotely, the TUI SHOULD retrieve the
target machine's hardware configuration via SSH
(`nixos-generate-config --show-hardware-config`) and update the local
`hosts/<hostname>/hardware.nix` before running the full install.

**REQ-006.8** After retrieving remote hardware config, the TUI MUST
commit and push the hardware changes to the config repository before
proceeding with the nixos-anywhere deployment.
