# Keystone repository contracts

This directory defines the high-level contracts for Keystone root storage,
configuration repositories, and secrets stores. They cover encrypted root
storage and credentials used for LUKS, SOPS/PIV, SSH, PAM/U2F, and WebAuthn.
`ks.systems/os` owns these interfaces; downstream repositories own their
implementation details.

Downstream repositories MUST maintain their own lower-level implementation
requirements and trace them to the applicable IDs here:

- `ks.systems/ks-config` implements [KSC-001](./KSC-001-configuration-repository.md).
- `ks.systems/secrets` implements [KSS-001](./KSS-001-secrets-repository.md).
- A configuration repository that embeds its secrets store implements both
  contracts and MUST trace its implementation requirements separately to each.
- Keystone's storage module and installer implement
  [KHW-001](./KHW-001-root-storage.md).

Tests pin machine-verifiable requirements with this marker:

```text
THIS TEST VALIDATES A HARD REQUIREMENT (<PREFIX>-NNN.M)
YOU MUST NOT MODIFY THIS TEST UNLESS THE REQUIREMENT CHANGES
```

## Register

| ID | Topic | Status |
| --- | --- | --- |
| KHW-001 | Root Storage Hardware | Draft |
| KSC-001 | Configuration Repository | Draft |
| KSS-001 | Secrets Repository | Draft |

## Amending requirements

Once a requirement is Accepted, its identifiers are permanent. Never renumber
or reassign an accepted requirement or section. Replace a withdrawn accepted
statement in place with
`REQUIREMENT REMOVED (YYYY-MM-DD): <rationale>` and append new statements
after the existing numbered statements. A Draft may be rewritten before
acceptance when its overview records the change and rationale.

When behavior and a requirement disagree:

1. Amend this contract first and add a dated rationale beneath the affected
   section heading.
2. Amend the traced downstream requirement.
3. Update pinned tests and implementation in the same reviewed change set.

Production secret values, production private identities, PINs, recovery
credentials, and decrypted output MUST NOT appear in requirements, committed
tests, plans, or evidence. Tests MAY generate synthetic values at runtime, but
MUST NOT commit, persist, or print them.

Contracts record authenticator-resident private keys through their public
metadata, role, custody, and proof. The private keys remain off-repository.
