---
title: GitHub PAT via sops
description: Avoid 60 req/hr anonymous rate limits by wiring a GitHub personal access token through sops
---

# GitHub PAT via sops

Companion to [`onboarding.md`](onboarding.md) Step 8. Optional but recommended.

## Why

GitHub limits anonymous API requests to **60 per hour per source IP**.
Authenticated requests get 5000/hr.

The 60/hr ceiling is easy to hit on a single host:

- Every `nix flake update keystone` triggers metadata + tarball fetches.
- `gh` CLI commands count against the same limit when unauthenticated.
- `ks update` queries GitHub for release info on each invocation.

Symptoms when you hit it:

```
error: unable to download '...': HTTP error 403
  message: API rate limit exceeded for 1.2.3.4. ...
```

Wiring a Personal Access Token (PAT) per host raises your ceiling to 5000/hr
*per token*. The token lives sops-encrypted in your `keystone-config` repo,
decrypted at runtime by the host's SSH host key (via ssh-to-age).

## Step A — Generate a fine-grained PAT

1. Go to <https://github.com/settings/personal-access-tokens>.
2. **Generate new token** → Fine-grained tokens.
3. **Resource owner**: yourself.
4. **Repository access**: "Only select repositories" → pick the repos you want
   to access (typically just `<you>/keystone-config` and any private repos
   you'll touch). "Public Repositories (read-only)" is *not* enough —
   read-only PATs aren't issued auth credit on the API, defeating the point.
5. **Repository permissions**:
   - `Contents`: **Read** (Read and write if `ks update` will push lock changes back)
   - `Pull requests`: **Read and write** (only if you'll open PRs from this host)
   - `Issues`: **Read** (only if you'll list/file issues from this host)
   - `Metadata`: Read (auto)
6. **Expiration**: max 366 days. Set a calendar reminder to rotate before it
   expires — the host will silently fall back to anonymous and you'll see
   403s again.
7. Click **Generate token**, copy the value (starts with `github_pat_`).

## Step B — Encrypt with sops

The template ships a `secrets/` directory and a `secrets/recipients.nix`
manifest (commented out by default). Uncomment the relevant lines.

1. Edit `secrets/recipients.nix`. Add your driver key under `admins` — either
   your `~/.ssh/id_ed25519.pub` line verbatim (converted via ssh-to-age at
   sync time) or an age recipient string. Host recipients are derived
   automatically from the flake's host inventory.

2. Regenerate `.sops.yaml` and encrypt the PAT. From the repo root:

   ```bash
   ks secrets sync
   ks secrets edit secrets/<host>.yaml
   ```

   An editor opens. Add a `<username>-github-token: github_pat_...` entry
   (no trailing whitespace). Save and exit.

3. Commit `secrets/recipients.nix`, `.sops.yaml`, and `secrets/<host>.yaml`.
   The YAML file is encrypted ciphertext — safe to commit.

## Step C — Wire the secret into your flake

Keystone's operating-system module already imports `sops-nix.nixosModules.sops`,
so you don't need to add a `sops-nix` input to your `flake.nix`.

1. Make sure `keystone.secrets.dir` points at the repo's `secrets/` directory.
   `mkSystemFlake` defaults it to `<repo>/secrets` when that directory exists
   (the template ships it), so normally there is nothing to do. If you moved
   the secrets directory or don't use `mkSystemFlake`, set it explicitly in
   your host's `configuration.nix`:

   ```nix
   keystone.secrets.dir = ../../secrets; # path from hosts/<host>/
   ```

   Without a non-null `keystone.secrets.dir`, `keystone.secrets.provided.*`
   declarations materialize nothing (the build emits a warning).

2. Uncomment the `keystone.secrets.provided` block and the shell-init hook in
   your host's `configuration.nix`:

```nix
programs.zsh.interactiveShellInit = ''
  if [ -f /run/secrets/<username>-github-token ]; then
    export GITHUB_TOKEN="$(tr -d '\n' < /run/secrets/<username>-github-token)"
  fi
'';
```

The host config is a NixOS module, so use `programs.zsh.interactiveShellInit`
(or `programs.bash.interactiveShellInit` for bash, or
`environment.interactiveShellInit` to cover both). Home Manager's
`programs.zsh.initExtra` is a different option and won't evaluate here.

## Step D — Rebuild

```bash
sudo nixos-rebuild switch --flake .#<host>
```

After activation, the secret is materialized at `/run/secrets/<username>-github-token`
owned by the user, mode `0400`.

## Step E — Verify

Open a fresh shell on the target (so the interactive shell init hook runs):

```bash
# GITHUB_TOKEN should be set
echo "${GITHUB_TOKEN:0:8}…"   # prints first 8 chars; safe to share

# gh CLI picks it up automatically
gh api /user --jq .login

# Should print your GitHub username
```

Run a flake update to confirm Nix's fetcher is authenticated:

```bash
nix flake update keystone
```

The first fetches go to `api.github.com`. They should not 403.

## Future enhancement: Nix's `access-tokens`

`gh` and `ks` read `GITHUB_TOKEN` from env naturally, so the shell-init export
is enough for them. Nix's flake fetcher reads from
`nix.settings.access-tokens` — but setting that statically embeds the token in
the Nix store, which violates the keystone convention against
store-embedding secrets.

The clean fix is a per-boot activation script that writes
`/etc/nix/access-tokens.conf` from the runtime sops file, plus
`nix.extraOptions = "!include /etc/nix/access-tokens.conf";`. This isn't
wired in the template yet — track in a future docs update. For now the shell
export covers ~all real cases (Nix's fetcher uses `gh auth` or the env var
when available, depending on flags).

## Rotating the PAT

When your PAT is near expiry:

1. Generate a new PAT in the GitHub UI (same scopes).
2. Re-encrypt: `ks secrets edit secrets/<host>.yaml`, paste the new value,
   save.
3. Commit the updated YAML file.
4. Rebuild on each consuming host: `sudo nixos-rebuild switch --flake .#<host>`.

The old PAT can be revoked in the GitHub UI immediately after the rebuild
lands.
