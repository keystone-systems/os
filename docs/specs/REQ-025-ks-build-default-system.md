# REQ-025: ks build — default to full system, add --home-only

`ks build` currently defaults to home-manager-only builds, requiring `--lock`
to get a full system build — but `--lock` also locks, commits, and pushes.
There is no way to do a full system evaluation without side effects. This spec
inverts the default so `ks build` does a full system build and adds
`--home-only` for the fast home-manager path.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## User Story

As a keystone operator, I want `ks build` to evaluate the full NixOS system
config by default so that I can verify system-level changes (like
`keystone.desktop.obs.gpuType`) without committing or pushing anything.

## Architecture

```
                      ks build [HOSTS]
                           │
              ┌────────────┼────────────┐
              │            │            │
         --home-only    (default)    --lock
              │            │            │
         HM profiles   System      System build
         only (fast)   toplevel    + lock + commit
                       (no side     + push
                        effects)
```

## Affected Modules

- `packages/ks/ks.sh` — restructure `cmd_build` flag parsing and build paths
- `docs/specs/REQ-019-ks-cli.md` — update REQ-019.3 and REQ-019.4

## Requirements

### Build Modes

**REQ-025.1** `ks build` without flags MUST build the full NixOS system
toplevel (`system.build.toplevel`) for all target hosts, using local overrides
(REQ-019.5) and `--no-link` (REQ-019.7).

**REQ-025.2** `ks build --home-only` MUST build only home-manager activation
packages (the current default behavior).

**REQ-025.3** `ks build --lock` MUST retain its current behavior: verify
clean repos, push keystone, lock flake inputs, full system build, commit
`flake.lock`, and push nixos-config.

**REQ-025.4** `--home-only` and `--lock` MUST NOT be combined. If both are
passed, `ks` MUST exit with an error.

### Backwards Compatibility

**REQ-025.5** The existing `--dev` flag (already a no-op) MAY be removed or
kept as an alias for `--home-only` during a transition period.

### REQ-019 Updates

**REQ-025.6** REQ-019.3 MUST be updated to reflect that `ks build` without
flags builds the full system, not just home-manager.

**REQ-025.7** REQ-019.4 MUST be updated to document `--home-only` as the
home-manager-only build path.

## Implementation Notes

The change is minimal — extract the system build from the `--lock` branch
into the default path, move home-manager build behind `--home-only`:

```bash
cmd_build() {
  local hosts_arg="" lock=false home_only=false
  while [[ $# -gt 0 ]]; do
    case $1 in
      --home-only) home_only=true; shift ;;
      --lock) lock=true; shift ;;
      -*) echo "Error: Unknown option '$1'" >&2; exit 1 ;;
      *) hosts_arg="$1"; shift ;;
    esac
  done

  if [[ "$lock" == true && "$home_only" == true ]]; then
    echo "Error: --lock and --home-only are mutually exclusive" >&2; exit 1
  fi

  # ... resolve hosts ...

  if [[ "$home_only" == true ]]; then
    build_home_manager_only "$repo_root" "${target_hosts[@]}"
  elif [[ "$lock" == true ]]; then
    # existing lock workflow
  else
    # NEW default: full system build, no side effects
    local override_args=()
    read -ra override_args <<< "$(local_override_args "$repo_root")"
    local build_targets=()
    for h in "${target_hosts[@]}"; do
      build_targets+=("$repo_root#nixosConfigurations.$h.config.system.build.toplevel")
    done
    echo "Building (full system): ${target_hosts[*]}..."
    nix build --no-link "${build_targets[@]}" "${override_args[@]}"
  fi
}
```
