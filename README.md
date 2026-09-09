# Keystone OS

Keystone OS is a reproducible NixOS platform for encrypted laptops,
workstations, and servers, with support for autonomous agents. A single flake
in Git declares the fleet's hosts, users, storage, desktop, services, and
deployment policy.

**[Get started](docs/quickstart.md)** · [Documentation](docs/index.md) ·
[`ks` CLI](docs/ks.md) · [Contributing](CONTRIBUTOR.md)

## What it provides

- Declarative NixOS hosts with ZFS storage and LUKS encryption
- Secure Boot and TPM or FIDO2 enrollment paths
- Optional [Keystone Desktop](https://github.com/keystone-systems/desktop)
- [Keystone Terminal](https://github.com/keystone-systems/terminal) on desktop
  and headless hosts
- OS-level agent identities with isolated users, homes, and credentials
- A shared fleet model for physical machines, VMs, and installation tests

Start with the [ISO and Docker quickstart](docs/quickstart.md). The longer
[onboarding walkthrough](docs/keystone/onboarding.md) covers configuration and
post-install hardening. Build-from-source and contributor workflows live in the
[documentation index](docs/index.md).

## Development

Use the repository's Nix development shell and the smallest relevant check:

```bash
nix develop
nix flake check --no-build
```

See [CONTRIBUTOR.md](CONTRIBUTOR.md) for worktrees, validation, pull requests,
and deployment.

## License

[MIT](LICENSE)
