# secrets/

Agenix-encrypted secrets live here. The directory ships empty because secrets
are specific to your fleet — there's nothing meaningful for the template to
encrypt up front.

You start populating this directory at **Step 8** of
[`../docs/keystone/onboarding.md`](../docs/keystone/onboarding.md). The first
secret most users add is a GitHub PAT — see
[`../docs/keystone/github-token.md`](../docs/keystone/github-token.md) for the
full walkthrough.

## How it works

- `../secrets.nix` lists recipients — which age public keys can decrypt each
  file. Both your driver (so you can edit secrets later) and every host that
  consumes the secret at runtime need to be in the `publicKeys` list.
- `agenix -e secrets/<name>.age` opens an editor, encrypts your input to
  every listed recipient, and writes the ciphertext as `<name>.age`. The
  `.age` files are safe to commit.
- On each consuming host, `age.secrets.<name>.file = ../../secrets/<name>.age`
  (declared in `flake.nix` or `hosts/<name>/configuration.nix`) wires the
  runtime decryption. Keystone's operating-system module already imports
  `agenix.nixosModules.default`, so no extra plumbing is needed.
- At activation time, agenix decrypts each declared secret into
  `/run/agenix/<name>` with the owner and mode you specified. Read from there
  at runtime — never bake the cleartext into `home.sessionVariables` or
  `nix.settings.access-tokens`, both of which embed the value in the Nix
  store.

## Don't

- **Don't commit cleartext secrets.** If you accidentally do, rotate the
  underlying credential before relying on `git rm` — git history keeps the
  cleartext until the history is rewritten and force-pushed.
- **Don't add a `.gitignore` that ignores `*.age`.** The whole point of the
  `.age` extension is that the ciphertext is safe to track in git.
- **Don't share a single secret across recipients who shouldn't all see it.**
  Re-encrypt with a narrower `publicKeys` list instead.

## File naming

The convention is `<consumer>-<purpose>.age`. Examples:

- `<username>-github-token.age` — per-user GitHub PAT
- `server-tailscale-authkey.age` — host-scoped Tailscale auth key
- `mail-relay-password.age` — service-scoped credential

Match the file basename to the `age.secrets.<name>` declaration so the wiring
stays grep-able.
