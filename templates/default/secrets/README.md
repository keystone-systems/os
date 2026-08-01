# secrets/

sops-encrypted secrets live here. The directory ships empty because secrets
are specific to your fleet — there's nothing meaningful for the template to
encrypt up front.

You start populating this directory at **Step 8** of
[`../docs/keystone/onboarding.md`](../docs/keystone/onboarding.md). The first
secret most users add is a GitHub PAT — see
[`../docs/keystone/github-token.md`](../docs/keystone/github-token.md) for the
full walkthrough.

## How it works

- Secrets are keys inside sops-encrypted YAML files, scoped by file:
  `secrets/<hostname>.yaml` (one host), `secrets/shared.yaml` (all hosts),
  `secrets/services/<name>.yaml` (hosts running a service).
- `secrets/recipients.nix` lists admin recipients (your editing keys) and
  per-file host lists. `ks secrets sync` turns it — plus the host keys from
  the flake — into the generated `.sops.yaml`; never edit `.sops.yaml` by
  hand. After recipient changes, run `ks secrets rekey`.
- `ks secrets edit secrets/<file>.yaml` opens an editor and re-encrypts on
  save. The encrypted YAML files are safe to commit.
- On each consuming host, declare
  `keystone.secrets.provided.<name> = { owner = "..."; scope = "host"; }`
  (in `flake.nix` or `hosts/<name>/configuration.nix`). Keystone's
  operating-system module already imports `sops-nix.nixosModules.sops`, so
  no extra plumbing is needed.
- At activation time, sops-nix decrypts each declared secret into
  `/run/secrets/<name>` with the owner and mode you specified — read the
  path from `config.keystone.secrets.provided.<name>.path`. Never bake the
  cleartext into `home.sessionVariables` or `nix.settings.access-tokens`,
  both of which embed the value in the Nix store.

## Don't

- **Don't commit cleartext secrets.** If you accidentally do, rotate the
  underlying credential before relying on `git rm` — git history keeps the
  cleartext until the history is rewritten and force-pushed.
- **Don't add a `.gitignore` that ignores `secrets/*.yaml`.** The whole point
  of sops is that the ciphertext is safe to track in git.
- **Don't share a single secret across recipients who shouldn't all see it.**
  Move it to a narrower-scoped file (per-host or per-service) instead.

## Secret naming

The convention is `<consumer>-<purpose>` for the YAML key. Examples:

- `<username>-github-token` — per-user GitHub PAT
- `<username>-ssh-passphrase` — per-user SSH key passphrase (per-host file)
- `mail-relay-password` — service-scoped credential

Match the YAML key to the `keystone.secrets.provided.<name>` declaration so
the wiring stays grep-able.
