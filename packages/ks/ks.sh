# shellcheck shell=bash
#
# ks — Keystone CLI.
#
# A thin front end over the tools that do the real work: nixos-rebuild for
# the local host, ks-fleet for every other host, keystone-approve-exec for
# privileged execution, and ykman/ssh-keygen for hardware-key enrollment.
#
# Scope rule: a subcommand belongs here only when a Keystone module, a
# desktop menu, or the documented contributor workflow invokes it. Anything
# else belongs in its own script under bin/.

usage() {
  cat <<'EOF'
usage: ks <command> [flags] [HOSTS]

commands:
  build [HOSTS]              build the system closure for each host
  switch [--boot] [HOSTS]    build and activate the current local state
  update [--dev] [--boot] [HOSTS]
                             pull, relock, build, and deploy (lock mode is
                             the default; --dev skips pull and relock)
  activate <STORE_PATH>      activate a pre-built system closure
  approve --reason R -- CMD [ARG ...]
                             run an allowlisted privileged command
  kube sudo [--user U] -- ARG [ARG ...]
                             re-run one kubectl command with RBAC impersonation
  secrets edit FILE          open a sops-encrypted file
  secrets sync               regenerate .sops.yaml from hosts.nix and
                             secrets/recipients.nix
  secrets rekey              sync, then re-encrypt every file under secrets/
                             for the new recipient set (needs an admin key)
  menu update entries|dispatch
                             Walker update provider (inert: emits no entries)
  hardware-key doctor [--host H] [--strict] [--json]
                             audit committed hardware-key state against a host
  hardware-key register NAME [--serial S] [--owner U] [--repo DIR]
                             enroll a connected token and print its registration

global flags:
  --flake PATH               consumer flake (default: the path recorded at
                             /run/current-system/keystone-system-flake)
  -h, --help                 show this help

HOSTS is a comma-separated list. When omitted, ks uses the current host.
EOF
}

die() {
  printf 'ks: %s\n' "$*" >&2
  exit 1
}

note() {
  printf 'ks: %s\n' "$*" >&2
}

FLAKE=
SYSTEM_FLAKE_FILE=/run/current-system/keystone-system-flake

# modules/shared/system-flake.nix declares the runtime pointer the single
# source of truth, with `--flake` as the only accepted override. Resolve once.
resolve_flake() {
  if [ -z "$FLAKE" ]; then
    [ -r "$SYSTEM_FLAKE_FILE" ] ||
      die "no consumer flake found. Pass --flake PATH."
    read -r FLAKE <"$SYSTEM_FLAKE_FILE"
  fi
  printf '%s\n' "$FLAKE"
}

# Split a comma-separated host list into HOSTS, defaulting to this host.
# Bash splits natively; no fork, and the caller keeps its own shell so `die`
# inside the loop aborts ks rather than a subshell.
read_hosts() {
  IFS=, read -r -a HOSTS <<<"${1:-$HOSTNAME}"
}

# ks-fleet owns every host that is not this one. Keep one deploy path.
deploy_remote() {
  local host="$1" flake="$2"
  command -v ks-fleet >/dev/null 2>&1 ||
    die "ks-fleet is not on PATH; it deploys hosts other than $HOSTNAME."
  note "delegating $host to ks-fleet deploy"
  ks-fleet deploy "$host" --flake "$flake" --durable
}

cmd_build() {
  local flake host
  local -a HOSTS installables=()
  read_hosts "${1:-}"
  flake=$(resolve_flake)
  for host in "${HOSTS[@]}"; do
    installables+=("${flake}#nixosConfigurations.${host}.config.system.build.toplevel")
  done
  note "building ${HOSTS[*]}"
  # One invocation: nix evaluates the shared flake once and schedules the
  # builds together, instead of a cold eval per host.
  nix build --print-out-paths "${installables[@]}"
}

cmd_switch() {
  local action=switch flake host
  local -a HOSTS
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --boot)
      action=boot
      shift
      ;;
    --) shift ;;
    -*) die "unknown flag for switch: $1" ;;
    *) break ;;
    esac
  done
  read_hosts "${1:-}"
  flake=$(resolve_flake)
  for host in "${HOSTS[@]}"; do
    if [ "$host" = "$HOSTNAME" ]; then
      note "nixos-rebuild $action on $host"
      sudo nixos-rebuild "$action" --flake "${flake}#${host}"
    else
      [ "$action" = switch ] ||
        die "ks-fleet deploy has no --boot mode; $host cannot take --boot."
      deploy_remote "$host" "$flake"
    fi
  done
}

cmd_update() {
  local mode=lock boot='' hosts flake
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --dev)
      mode=dev
      shift
      ;;
    --lock)
      mode=lock
      shift
      ;;
    --boot)
      boot=--boot
      shift
      ;;
    --) shift ;;
    -*) die "unknown flag for update: $1" ;;
    *) break ;;
    esac
  done
  hosts="${1:-}"

  if [ "$mode" = lock ]; then
    flake=$(resolve_flake)
    note "pulling $flake"
    git -C "$flake" pull --ff-only
    note "relocking flake inputs"
    nix flake update --flake "$flake"
    if ! git -C "$flake" diff --quiet -- flake.lock; then
      git -C "$flake" commit -m "chore(flake): relock inputs" -- flake.lock
    fi
  fi

  if [ -n "$boot" ]; then
    cmd_switch --boot "$hosts"
  else
    cmd_switch "$hosts"
  fi

  if [ "$mode" = lock ] && [ -n "$(git -C "$flake" log '@{u}..' --oneline 2>/dev/null || true)" ]; then
    note "pushing $flake"
    git -C "$flake" push
  fi
}

cmd_activate() {
  local closure="${1:-}" resolved
  [ -n "$closure" ] || die "activate needs a store path"
  # Canonicalize first: a plain prefix test accepts /nix/store/../tmp/evil,
  # and this runs as root inside the pkexec child, so an attacker who can
  # write under /tmp could otherwise land a fake switch-to-configuration.
  resolved=$(realpath -e -- "$closure" 2>/dev/null) ||
    die "no such path: $closure"
  case "$resolved" in
  /nix/store/*) ;;
  *) die "refusing to activate a path outside /nix/store: $resolved" ;;
  esac
  [ -x "${resolved}/bin/switch-to-configuration" ] ||
    die "not a system closure: $resolved"
  # Register the generation in the system profile before switching, so the
  # boot menu and `nix-env --list-generations` agree with what is running.
  nix-env --profile /nix/var/nix/profiles/system --set "$resolved"
  "${resolved}/bin/switch-to-configuration" switch
}

cmd_approve() {
  local reason='' helper
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --reason)
      reason="${2:-}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *) die "unknown flag for approve: $1" ;;
    esac
  done
  [ -n "$reason" ] || die "--reason is required"
  [ "$#" -gt 0 ] || die "missing command after --"

  helper=$(command -v keystone-approve-exec || true)
  if [ -z "$helper" ] && [ -x /run/current-system/sw/bin/keystone-approve-exec ]; then
    helper=/run/current-system/sw/bin/keystone-approve-exec
  fi
  [ -n "$helper" ] ||
    die "keystone-approve-exec is not available. Enable keystone.security.privilegedApproval on this host first."

  # The helper owns allowlist matching. Ask it first so a rejected request
  # never raises an authentication prompt.
  "$helper" --validate --reason "$reason" -- "$@" >/dev/null ||
    die "approval request rejected by policy"

  if [ "$(id -u)" = 0 ] || [ -n "${KS_APPROVE_EXECUTING:-}" ]; then
    exec "$helper" --reason "$reason" -- "$@"
  fi
  if [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] && command -v pkexec >/dev/null 2>&1; then
    exec pkexec "$helper" --reason "$reason" -- "$@"
  fi
  exec sudo "$helper" --reason "$reason" -- "$@"
}

cmd_kube() {
  local user="${USER:-}" subcommand="${1:-}"
  [ "$subcommand" = sudo ] || die "usage: ks kube sudo [--user U] -- ARG ..."
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --user)
      user="${2:-}"
      shift 2
      ;;
    --cluster)
      # Reserved: kubectl resolves the cluster from the kubeconfig context.
      # Say so rather than accepting a flag that changes nothing.
      note "--cluster is not implemented; using the current kubeconfig context"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *) die "unknown flag for kube sudo: $1" ;;
    esac
  done
  [ "$#" -gt 0 ] || die "missing kubectl arguments after --"
  [ -n "$user" ] || die "--user is required when \$USER is unset"
  case "$user" in
  system:*) die "refusing to impersonate a system: identity" ;;
  esac
  note "impersonating ${user} in group keystone:sudoers"
  exec kubectl --as="$user" --as-group=keystone:sudoers "$@"
}

# The Walker update provider calls `ks menu update entries` on every menu
# open and `ks menu update dispatch <token>` on activation. Its backend was
# the Rust update-menu; nothing replaced it. Emit no entries rather than
# leaving the provider to parse an error, so the rest of the menu still
# works. Deploy from a terminal with `ks update`.
cmd_menu() {
  [ "${1:-}" = update ] || die "usage: ks menu update {entries|dispatch TOKEN}"
  case "${2:-}" in
  entries) printf '[]\n' ;;
  dispatch)
    note "the update menu is not available; run 'ks update' from a terminal"
    ;;
  *) die "usage: ks menu update {entries|dispatch TOKEN}" ;;
  esac
}

# .sops.yaml is derived, never authored. Its inputs are hosts.nix (each host's
# hostPublicKey) and secrets/recipients.nix (admin identities, plus which hosts
# may read the shared and per-service files). ssh-ed25519 keys become age
# recipients via ssh-to-age; age1... values pass through untouched.
#
# Rule order is part of the contract, because a regenerated file must be
# byte-identical when the inputs have not changed: per-host files first,
# alphabetically, then secrets/services/*, then everything else -- each group
# sorted by pattern, and every rule carrying all admin recipients.
SOPS_YAML_HEADER="# GENERATED by 'ks secrets sync' — do not edit by hand."

# Prefer the YubiKey age identity when the caller has not chosen one, so
# `sync`, `rekey` and `edit` cannot drift apart on which key they use.
sops_age_identity() {
  local identity="$HOME/.age/yubikey-identity.txt"
  if [ -z "${SOPS_AGE_KEY_FILE:-}" ] && [ -f "$identity" ]; then
    export SOPS_AGE_KEY_FILE="$identity"
  fi
}

age_recipient() {
  local value="$1"
  case "$value" in
  age1*) printf '%s\n' "$value" ;;
  ssh-ed25519\ *)
    printf '%s\n' "$value" | ssh-to-age 2>/dev/null ||
      die "ssh-to-age failed for: $value"
    ;;
  *) die "unsupported recipient (want age1... or ssh-ed25519 ...): $value" ;;
  esac
}

secrets_repo_root() {
  local root
  root="$(resolve_flake)"
  [ -f "$root/hosts.nix" ] || die "no hosts.nix at $root"
  [ -f "$root/secrets/recipients.nix" ] || die "no secrets/recipients.nix at $root"
  printf '%s\n' "$root"
}

secrets_sync() {
  local root admins hosts rules host regex age
  root="$(secrets_repo_root)"

  # Admin recipients, ordered by admin name so the output is stable.
  admins=""
  while read -r _name value; do
    [ -n "$_name" ] || continue
    admins="${admins}$(age_recipient "$value"),"
  done < <(nix eval --json --file "$root/secrets/recipients.nix" |
    jq -r '.admins | to_entries | sort_by(.key)[] | "\(.key) \(.value)"')
  [ -n "$admins" ] || die "secrets/recipients.nix declares no admins"

  # Every host with a hostPublicKey, alphabetically, each reading its own file.
  hosts="$(nix eval --json --file "$root/hosts.nix" |
    jq -r 'to_entries | map(select(.value.hostPublicKey)) | sort_by(.key)[] |
           "\(.key)\t\(.value.hostPublicKey)"')"

  rules=""
  while IFS=$'\t' read -r host key; do
    [ -n "$host" ] || continue
    rules="${rules}  - path_regex: secrets/${host}\\.yaml"$'\n'
    rules="${rules}    age: ${admins}$(age_recipient "$key")"$'\n'
  done <<<"$hosts"

  # Shared and per-service files: services first, then the rest, each group
  # sorted by pattern. jq's sort_by keeps that ordering explicit.
  while IFS=$'\t' read -r regex hostlist; do
    [ -n "$regex" ] || continue
    age="$admins"
    for host in $hostlist; do
      key="$(jq -r --arg h "$host" '.[$h].hostPublicKey // empty' <<<"$(nix eval --json --file "$root/hosts.nix")")"
      [ -n "$key" ] ||
        die "host '$host' in secrets/recipients.nix has no hostPublicKey in hosts.nix"
      age="${age}$(age_recipient "$key"),"
    done
    rules="${rules}  - path_regex: ${regex}"$'\n'
    rules="${rules}    age: ${age%,}"$'\n'
  done < <(nix eval --json --file "$root/secrets/recipients.nix" |
    jq -r '.files | to_entries
           | map(. + {g: (if (.key | startswith("secrets/services/")) then 0 else 1 end)})
           | sort_by(.g, .key)[]
           | "\(.key)\t\(.value.hosts | join(" "))"')

  {
    printf '%s\n' "$SOPS_YAML_HEADER"
    printf 'creation_rules:\n'
    printf '%s' "$rules"
  } >"$root/.sops.yaml"
  echo "wrote $root/.sops.yaml"
}

# Regenerate .sops.yaml, then re-encrypt every sops file under secrets/ for the
# new recipient set. This decrypts each file, so it needs an admin identity --
# a YubiKey (PIN + touch) or the ssh key. It cannot run unattended.
secrets_rekey() {
  local root file failed=0
  secrets_sync
  root="$(secrets_repo_root)"
  sops_age_identity
  while IFS= read -r file; do
    # A sops file carries its own metadata; cheaper than parsing every format.
    grep -qE '^\s*(mac|"mac"):' "$file" 2>/dev/null || continue
    echo "==> sops updatekeys $file"
    (cd "$root" && sops updatekeys --yes "$file") || failed=$((failed + 1))
  done < <(find "$root/secrets" -type f | sort)
  [ "$failed" -eq 0 ] || die "$failed file(s) failed to re-encrypt"
}

cmd_secrets() {
  local subcommand="${1:-}"
  shift || true
  case "$subcommand" in
  edit)
    [ "$#" -gt 0 ] || die "usage: ks secrets edit FILE"
    sops_age_identity
    exec sops "$@"
    ;;
  sync) secrets_sync ;;
  rekey) secrets_rekey ;;
  *) die "usage: ks secrets edit FILE | ks secrets sync | ks secrets rekey" ;;
  esac
}

cmd_hardware_key() {
  local subcommand="${1:-}"
  shift || true
  case "$subcommand" in
  doctor)
    command -v ks-hardware-key-audit >/dev/null 2>&1 ||
      die "ks-hardware-key-audit is not on PATH"
    # The audit script defaults --flake to $PWD and requires --host. Feed it
    # what ks already resolved unless the caller named them.
    case " $* " in
    *" --flake "*) ;;
    *) set -- --flake "$(resolve_flake)" "$@" ;;
    esac
    case " $* " in
    *" --host "*) ;;
    *) set -- --host "$HOSTNAME" "$@" ;;
    esac
    exec ks-hardware-key-audit "$@"
    ;;
  register) hardware_key_register "$@" ;;
  *) die "usage: ks hardware-key {doctor|register}" ;;
  esac
}

# Enroll a physically connected token and print the blocks a consumer
# flake needs. Reads the token; never writes to the flake. Paste the output,
# review it, and commit it — enrollment is a fact about hardware, so a human
# confirms it lands in git.
hardware_key_register() {
  local name='' serial='' owner="${USER:-}" repo='' handle handle_source age_recipient pam_fragment
  local pubkey keytype keydata
  name="${1:-}"
  [ -n "$name" ] || die "usage: ks hardware-key register NAME [--serial S] [--owner U] [--repo DIR]"
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --serial)
      serial="${2:-}"
      shift 2
      ;;
    --owner)
      owner="${2:-}"
      shift 2
      ;;
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    *) die "unknown flag for register: $1" ;;
    esac
  done
  [ -n "$owner" ] || die "--owner is required when \$USER is unset"
  [ -n "$repo" ] || repo=$(resolve_flake)

  if [ -z "$serial" ]; then
    # One enumeration: ykman is a Python process talking to the token.
    local -a serials
    mapfile -t serials < <(ykman list --serials)
    [ "${#serials[@]}" -gt 0 ] || die "no hardware key detected. Insert one, or pass --serial."
    [ "${#serials[@]}" -eq 1 ] ||
      die "more than one hardware key is connected. Pass --serial to choose one."
    serial="${serials[0]}"
  fi
  note "using token serial ${serial}"

  handle="${repo}/hardware-keys/${name}"
  handle_source="./hardware-keys/${name}"
  if [ -f "${repo}/modules/keys.nix" ]; then
    handle_source="../hardware-keys/${name}"
  fi
  mkdir -p "${repo}/hardware-keys"
  if [ -e "$handle" ]; then
    note "reusing the existing key handle at ${handle}"
  else
    note "touch the token to create a resident credential"
    ssh-keygen -t ed25519-sk -O resident -O application="ssh:${name}" \
      -C "${owner}-${name}" -N '' -f "$handle"
  fi
  read -r keytype keydata _ <"${handle}.pub"
  pubkey="$keytype $keydata"

  age_recipient=$(age-plugin-yubikey --list |
    grep -A1 "Serial: ${serial}" | grep -m1 -o 'age1yubikey1[a-z0-9]*' || true)
  [ -n "$age_recipient" ] ||
    note "no age recipient found for ${serial}; run 'age-plugin-yubikey' to generate one"

  note "touch the token again to create the PAM/U2F registration"
  pam_fragment=$(pamu2fcfg -o "pam://$HOSTNAME" -i "pam://$HOSTNAME" |
    sed "s/^${owner}://" || true)

  cat <<EOF

# Add to keystone.hardwareKeys — presence enables the key fleet-wide.
keystone.hardwareKeys.${name} = "${serial}";

# Add to keystone.hardwareKeyRegistrations.
keystone.hardwareKeyRegistrations.${name} = {
  owner = "${owner}";
  sshPublicKeys = [ "${pubkey}" ];
  pamU2f = [ "${pam_fragment}" ];
  ageRecipients = [ "${age_recipient}" ];
};

# Add to the keystone.keys module. handleSource is relative to that file.
keystone.keys.${owner}.hardwareKeys.${name} = {
  publicKey = "${pubkey}";
  handleSource = ${handle_source};
};

# Key handle written to ${handle}{,.pub}. Commit both.
EOF
}

main() {
  local command
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --flake)
      FLAKE="${2:-}"
      shift 2
      ;;
    -h | --help | help)
      usage
      exit 0
      ;;
    *) break ;;
    esac
  done

  command="${1:-}"
  [ -n "$command" ] || {
    usage
    exit 1
  }
  shift

  case "$command" in
  build) cmd_build "$@" ;;
  switch) cmd_switch "$@" ;;
  update) cmd_update "$@" ;;
  activate) cmd_activate "$@" ;;
  approve) cmd_approve "$@" ;;
  kube) cmd_kube "$@" ;;
  hardware-key) cmd_hardware_key "$@" ;;
  menu) cmd_menu "$@" ;;
  secrets) cmd_secrets "$@" ;;
  *) die "unknown command: ${command}. Run 'ks --help'." ;;
  esac
}

main "$@"
