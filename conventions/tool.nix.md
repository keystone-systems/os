## Nix

## Flakes

1. All projects MUST use flakes (`flake.nix` at repo root).
2. `flake.lock` MUST be committed to the repository.
3. Flake inputs SHOULD be pinned to specific revisions or branches for reproducibility.
4. You MUST NOT run `nix flake update` (full update) when only specific inputs changed — use `nix flake update <input-name>` for targeted updates.

## Dev Shells

5. Every project MUST provide a `devShells.default` in its flake.
6. Dev shells MUST include all build, test, and development dependencies.
7. Shell hooks MAY set environment variables needed by the project.

## Packages & Modules

8. NixOS modules MUST follow the `{ config, lib, pkgs, ... }:` argument pattern.
9. Module options MUST use `lib.mkOption` with type, default, and description. For boolean enable options, see `process.enable-by-default` rule 1 regarding default values.
10. Package derivations SHOULD use `stdenv.mkDerivation` or appropriate builder. For shell script packaging, see `code.shell-scripts` rules 23-27.

## Style

11. Nix files MUST use 2-space indentation.
12. Attribute sets with more than 3 keys SHOULD be broken across multiple lines.
13. `let ... in` blocks SHOULD be used for local bindings — avoid deeply nested `with` scopes.
14. File-level comments MUST explain the module's purpose using `#` comment blocks.

## Testing

15. NixOS modules SHOULD have VM tests (`nixos/tests`) for non-trivial behavior.
16. Flake checks (`nix flake check`) MUST pass before pushing.

## NixOS System Activation

For NixOS `system.activationScripts` vs `systemd.services` oneshots, see
`os.systemd-over-activation`. Default to systemd; activation scripts are the
narrow exception.

## Home-Manager File Management

17. Config files that the managed tool modifies at runtime MUST NOT use `home.file` with `.text` or `.source`, because home-manager creates an immutable Nix store symlink that the tool cannot write to.
18. Runtime-writable config files MUST use `home.activation` to write or merge content as a regular file.
19. When a tool stores both Nix-managed keys (e.g., `mcpServers`) and runtime state (e.g., cached feature flags, account data) in the same file, the activation script MUST merge only the Nix-managed keys — preserving all other content the tool has written.
20. Activation scripts that merge into existing files SHOULD use `jq -s '.[0] * {key: .[1]}'` (or equivalent) to replace only the managed key.
21. Activation scripts MUST handle three cases: stale Nix store symlink (remove and create), existing regular file (merge), and missing file (create with defaults).
22. Keystone secret management MUST distinguish at least four classes of agenix secrets: os-level secrets, service secrets, user-home secrets, and custom secrets.
23. Os-level secrets SHOULD use stable host-oriented names and recipient sets derived from the machines or operating-system roles that need the secret at runtime.
24. Service secrets SHOULD use stable service-oriented names and recipient sets derived from the machines or services that actually need the secret at runtime.
25. User-home secrets MUST be modeled around the Home Manager principal that consumes them, not around a single machine, when that user profile is intentionally deployed on multiple hosts.
26. A user-home secret MUST include every system key for hosts where that Home Manager user is installed; otherwise the profile is not portable across that user's declared deployment surface.
27. The corresponding `age.secrets.<name>` runtime declaration MUST exist on every host where that Home Manager user is installed when the user-home profile expects `/run/agenix/<name>` to exist there.
28. User-home secrets SHOULD follow a shared naming convention rooted in the username so the ownership is obvious from the secret name, for example `${username}-github-token`, `${username}-forgejo-token`, or `${username}-immich-api-key`.
29. Secret-backed environment variables in Home Manager MUST NOT be set with `home.sessionVariables` when the value would be embedded in the Nix store. Non-secret values MAY use `home.sessionVariables`, but secret values MUST be read from runtime files such as `/run/agenix/<name>` in a shell init hook or another runtime-only execution path.
30. When a tool needs both a public endpoint and a secret credential, the public endpoint SHOULD be set declaratively with `home.sessionVariables`, while the secret credential SHOULD be exported from the agenix runtime file at shell startup.
31. Secret-management surfaces such as Walker menus or future `ks secrets` commands SHOULD expose os-level secrets, service secrets, user-home secrets, and custom secrets as first-class categories so users can discover the intended scope before editing recipients or values.

### Golden Example

Claude Code stores MCP server config alongside runtime state (feature flags, OAuth account cache, subscription data) in `~/.claude.json`. The Nix module must manage `mcpServers` without destroying runtime state:

```nix
# WRONG — creates immutable symlink, Claude Code hangs in infinite retry loop
home.file.".claude.json".text = builtins.toJSON { mcpServers = cfg.mcpServers; };

# RIGHT — merges mcpServers into existing file, preserves runtime state
claudeJsonMcpServers = pkgs.writeText "claude-mcp-servers.json"
  (builtins.toJSON cfg.mcpServers);

home.activation.claudeJsonConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  claudeJson="$HOME/.claude.json"

  if [ -L "$claudeJson" ]; then
    rm -f "$claudeJson"
  fi

  if [ -f "$claudeJson" ]; then
    ${pkgs.jq}/bin/jq -s '.[0] * {mcpServers: .[1]}' \
      "$claudeJson" ${claudeJsonMcpServers} > "$claudeJson.tmp" \
      && mv "$claudeJson.tmp" "$claudeJson"
  else
    ${pkgs.jq}/bin/jq -n --slurpfile s ${claudeJsonMcpServers} \
      '{mcpServers: $s[0]}' > "$claudeJson"
  fi
'';
```

When a user-level Home Manager profile needs reusable credentials across multiple hosts, the user PAT secret recipients and runtime exports must follow the user rather than a single machine. The keystone module that implements this (`keystone.terminal.github`) and the convention for naming, scope, and recipient discipline are documented in `tool.github-pats`. The adopter declares one `age.secrets.<name>` entry per host and enables the keystone module; do not write a bespoke `programs.zsh.initExtra` block.

## Os-level GitHub access tokens for the nix daemon

32. The nix daemon authenticating to GitHub for fetches (`nix flake update`, `ks update`, channel updates, builtin builders) MUST use an agenix secret materialized into a root-readable include file referenced from `nix.conf`. The daemon runs as root under `sudo nixos-rebuild` / `ks update`, so a user-only `mode 0400 owner=<user>` file is not sufficient.
33. `keystone.os.githubTokenNix` MUST be the wiring module. It writes `/etc/nix/access-tokens.conf` from the runtime file via a hardened systemd oneshot and appends `!include` to `nix.extraOptions`. The token value never enters the Nix store.
34. The module auto-discovers the secret at module-eval time when `tokenFile` is unset; explicit `tokenFile = "..."` always overrides. Discovery order:
    1. `/run/agenix/nix-github-token` — dedicated nix-daemon secret if `age.secrets."nix-github-token"` is declared.
    2. `/run/agenix/${adminUsername}-github-token` — user-home PAT shared at os-level if `age.secrets."${adminUsername}-github-token"` is declared.
    3. (nothing found) — module stays inert. No assertion failure, no systemd unit emitted.
35. The **preferred default** is shape (2): single PAT backing `gh` / `git` / nix-daemon. CLAUDE.md rule 26 already requires user-home secrets to include every relevant host's system key, so root on those hosts can already decrypt the same ciphertext. Adopters declare one `age.secrets."${username}-github-token"` with `owner = "root"; group = "users"; mode = "0440";` — root reads it for the nix-daemon include file, the `users` group reads it for the user shell env hook.
36. Shape (1) — dedicated `nix-github-token` — is the right call when the nix-daemon needs a narrower PAT scope than the user PAT (e.g. agents-only audit trail), or when the host has no human user installed. Dedicated secrets MUST set `owner = "root"; mode = "0400";`.
37. Accepted basename patterns (validated by the module's assertion):
    - `nix-github-token` — portable, dedicated shape (1).
    - `<hostname>-nix-github-token` — host-scoped dedicated.
    - `<username>-github-token` — user-PAT shared, shape (2).
    - `<hostname>-<username>-github-token` — host-scoped user-PAT.
    Any other basename ending in `-github-token` is also accepted; the assertion only rejects shapes that clearly aren't GitHub tokens.

### Golden example: shared user-PAT shape (preferred)

```nix
# agenix-secrets/secrets.nix
"secrets/ncrmro-github-token.age".publicKeys = adminKeys ++ [
  systems.ncrmro-workstation
  systems.ncrmro-laptop
];

# nixos host that runs `ks update` / `nix flake update`
age.secrets."ncrmro-github-token" = {
  file = "${inputs.agenix-secrets}/secrets/ncrmro-github-token.age";
  owner = "root";
  group = "users";
  mode = "0440";
};

keystone.os.githubTokenNix.enable = true;
# tokenFile auto-resolves to /run/agenix/ncrmro-github-token via the fallback chain
```

### Golden example: dedicated nix-daemon shape

```nix
# agenix-secrets/secrets.nix
"secrets/nix-github-token.age".publicKeys = adminKeys ++ [
  systems.shared-build-host
];

age.secrets."nix-github-token" = {
  file = "${inputs.agenix-secrets}/secrets/nix-github-token.age";
  owner = "root";
  mode = "0400";
};

keystone.os.githubTokenNix.enable = true;
# tokenFile auto-resolves to /run/agenix/nix-github-token (preferred over user-PAT when both declared)
```

### Darwin (per-user nix.conf)

On Darwin keystone hosts there is no nix-darwin system module — Darwin keystone hosts run standalone home-manager only, and `nix flake update` is always user-invoked (no `sudo nixos-rebuild`). Use `keystone.terminal.githubTokenNix` to materialize `~/.config/nix/access-tokens.conf` at home-manager activation. The default `source = "gh-auth"` shells out to `gh auth token` and requires no agenix wiring. For adopters using home-manager-agenix on Darwin, set `source = "tokenFile"; tokenFile = config.age.secrets."${username}-github-token".path;` to share the same PAT used elsewhere.

```nix
# Darwin default — uses gh CLI login
keystone.terminal.githubTokenNix.enable = true;

# Darwin with home-manager-agenix
keystone.terminal.githubTokenNix = {
  enable = true;
  source = "tokenFile";
  tokenFile = config.age.secrets."ncrmro-github-token".path;
};
```
