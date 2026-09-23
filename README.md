# Keystone OS

Keystone OS uses a Git repository to define a reproducible NixOS laptop,
workstation, or server. One configuration specifies users, encrypted storage,
terminal and desktop environments, services, and deployment settings.

**[Get started](docs/quickstart.md)** · [Documentation](docs/index.md) ·
[`ks` CLI](docs/ks.md) · [Contributing](CONTRIBUTOR.md)

> **Release candidate:** `v0.13.0-rc.2` is available for spare hardware and
> virtual-machine testing. The installer still uses public bootstrap
> credentials. The full desktop install-and-reboot acceptance test has not
> passed.

## What it provides

- Declarative NixOS hosts with LUKS-encrypted ZFS storage
- Post-install setup for Secure Boot and TPM or FIDO2 enrollment
- Optional [Keystone Desktop](https://github.com/keystone-systems/desktop)
- [Keystone Terminal](https://github.com/keystone-systems/terminal) on desktop
  and headless hosts
- One configuration model for physical machines, VMs, and installation tests

The quickstart requires Docker, but not Nix, on the second computer. The
[onboarding walkthrough](docs/keystone/onboarding.md) covers configuration and
post-install hardening.

## Development

Enter the repository's Nix development shell, then run the relevant checks:

```bash
nix develop
nix flake check --no-build
```

See [CONTRIBUTOR.md](CONTRIBUTOR.md) for worktrees, validation, pull requests,
and deployment.
