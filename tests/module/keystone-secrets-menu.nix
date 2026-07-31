{
  pkgs,
  lib,
}:
pkgs.runCommand "test-keystone-secrets-menu"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      findutils
      gnugrep
      gnused
      jq
      ripgrep
      zsh
    ];
  }
  ''
    set -euo pipefail

    export REPO_ROOT="${../..}"
    export HOME="$PWD/home"
    export XDG_RUNTIME_DIR="$PWD/runtime"
    export KEYSTONE_SYSTEM_FLAKE_POINTER_FILE="$PWD/keystone-system-flake"
    export PATH="$PWD/bin:${
      lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
        pkgs.gnused
        pkgs.jq
        pkgs.ripgrep
        pkgs.zsh
      ]
    }"

    NIXOS_CONFIG_DIR="$PWD/nixos-config"

    mkdir -p "$HOME/.local/bin" "$HOME/.age" "$XDG_RUNTIME_DIR" "$NIXOS_CONFIG_DIR/agenix-secrets/secrets" \
      "$NIXOS_CONFIG_DIR/home-manager/ncrmro" "$NIXOS_CONFIG_DIR/hosts/ocean" \
      "$NIXOS_CONFIG_DIR/hosts/ncrmro-workstation" "$PWD/bin"

    # Write the pointer file so scripts can locate the system flake.
    printf '%s\n' "$NIXOS_CONFIG_DIR" > "$KEYSTONE_SYSTEM_FLAKE_POINTER_FILE"

    cat > "$HOME/.age/yubikey-identity.txt" <<'EOF'
    # serial:36854515
    AGE-PLUGIN-YUBIKEY-TEST
    EOF

    cat > "$PWD/bin/keystone-secrets-menu" <<'EOF'
    #!${pkgs.bash}/bin/bash
    exec ${pkgs.bash}/bin/bash "$REPO_ROOT/modules/desktop/home/scripts/keystone-secrets-menu.sh" "$@"
    EOF
    chmod +x "$PWD/bin/keystone-secrets-menu"
    ln -s "$PWD/bin/keystone-secrets-menu" "$HOME/.local/bin/keystone-secrets-menu"

    cat > "$PWD/bin/keystone-setup-menu" <<'EOF'
    #!${pkgs.bash}/bin/bash
    exec ${pkgs.bash}/bin/bash "$REPO_ROOT/modules/desktop/home/scripts/keystone-setup-menu.sh" "$@"
    EOF
    chmod +x "$PWD/bin/keystone-setup-menu"
    ln -s "$PWD/bin/keystone-setup-menu" "$HOME/.local/bin/keystone-setup-menu"

    cat > "$PWD/bin/keystone-detach" <<'EOF'
    #!${pkgs.bash}/bin/bash
    printf '%s\n' "$*" > "$XDG_RUNTIME_DIR/detach-command.txt"
    exit 0
    EOF
    chmod +x "$PWD/bin/keystone-detach"

    cat > "$PWD/bin/ghostty" <<'EOF'
    #!${pkgs.bash}/bin/bash
    exit 0
    EOF
    chmod +x "$PWD/bin/ghostty"

    for command_name in keystone-audio-menu keystone-monitor-menu keystone-hardware-menu keystone-fingerprint-menu keystone-accounts-menu keystone-printer-menu keystone-wifi-menu; do
      cat > "$PWD/bin/$command_name" <<EOF
    #!${pkgs.bash}/bin/bash
    exit 0
    EOF
      chmod +x "$PWD/bin/$command_name"
    done

    cat > "$PWD/bin/ykman" <<'EOF'
    #!${pkgs.bash}/bin/bash
    if [[ "''${1:-}" == "list" && "''${2:-}" == "--serials" ]]; then
      printf '%s\n' '36854515'
      exit 0
    fi
    exit 1
    EOF
    chmod +x "$PWD/bin/ykman"

    cat > "$PWD/bin/hwrekey" <<'EOF'
    #!${pkgs.bash}/bin/bash
    printf 'hwrekey %s\n' "$*" > "$XDG_RUNTIME_DIR/hwrekey-command.txt"
    exit 0
    EOF
    chmod +x "$PWD/bin/hwrekey"

    cat > "$PWD/bin/agenix" <<'EOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    args=("$@")
    if [[ " $* " == *" -d "* ]]; then
      target="''${args[-1]}"
      case "$target" in
        */ncrmro-github-token.age)
          printf '%s\n' 'ghp_test_token'
          exit 0
          ;;
        *)
          exit 1
          ;;
      esac
    fi

    if [[ " $* " == *" -e "* ]]; then
      printf 'agenix-edit %s\n' "$*" > "$XDG_RUNTIME_DIR/agenix-edit-command.txt"
      exit 0
    fi

    if [[ " $* " == *" -r "* || " $* " == *" --rekey "* ]]; then
      printf 'agenix-rekey %s\n' "$*" > "$XDG_RUNTIME_DIR/agenix-rekey-command.txt"
      exit 0
    fi

    exit 1
    EOF
    chmod +x "$PWD/bin/agenix"

    cat > "$NIXOS_CONFIG_DIR/agenix-secrets/secrets.nix" <<'EOF'
    {
      "secrets/ocean-ssh-passphrase.age".publicKeys = [];
      "secrets/cloudflare-api-token.age".publicKeys = [];
      "secrets/ncrmro-github-token.age".publicKeys = [];
      "secrets/custom-demo.age".publicKeys = [];
    }
    EOF

    touch "$NIXOS_CONFIG_DIR/agenix-secrets/secrets/ocean-ssh-passphrase.age"
    touch "$NIXOS_CONFIG_DIR/agenix-secrets/secrets/cloudflare-api-token.age"
    touch "$NIXOS_CONFIG_DIR/agenix-secrets/secrets/ncrmro-github-token.age"
    touch "$NIXOS_CONFIG_DIR/agenix-secrets/secrets/custom-demo.age"

    categories_json="$(keystone-secrets-menu categories-json)"
    printf '%s\n' "$categories_json" | jq -e '
      length == 4
      and any(.[]; .Text == "OS-level" and (.Subtext | contains("1")))
      and any(.[]; .Text == "Service" and (.Subtext | contains("1")))
      and any(.[]; .Text == "User-home" and (.Subtext | contains("1")))
      and any(.[]; .Text == "Custom" and (.Subtext | contains("1")))
    ' >/dev/null

    user_json="$(keystone-secrets-menu secrets-json user-home)"
    printf '%s\n' "$user_json" | jq -e '
      length == 1
      and .[0].Text == "ncrmro-github-token"
      and .[0].SubMenu == "keystone-secret-actions"
    ' >/dev/null

    service_actions="$(keystone-secrets-menu actions-json service secrets/cloudflare-api-token.age)"
    printf '%s\n' "$service_actions" | jq -e '
      any(.[]; .Text == "View value unavailable")
      and any(.[]; .Text == "Edit recipients and rekey")
    ' >/dev/null

    user_actions="$(keystone-secrets-menu actions-json user-home secrets/ncrmro-github-token.age)"
    printf '%s\n' "$user_actions" | jq -e '
      any(.[]; .Text == "View value")
      and any(.[]; .Text == "Edit value")
      and any(.[]; .Text == "Rekey now")
    ' >/dev/null

    preview_secret="$(keystone-secrets-menu preview-secret secrets/ncrmro-github-token.age)"
    printf '%s\n' "$preview_secret" | grep -F 'YubiKey: identity file present, YubiKey detected: 36854515' >/dev/null

    mv "$NIXOS_CONFIG_DIR/agenix-secrets" "$PWD/hidden-agenix-secrets"
    # Point the pointer file at a path without agenix-secrets to test the "no secrets" case.
    printf '%s\n' "$PWD/no-secrets-flake" > "$KEYSTONE_SYSTEM_FLAKE_POINTER_FILE"
    mkdir -p "$PWD/no-secrets-flake"
    setup_entries_json="$(keystone-setup-menu entries-json)"
    printf '%s\n' "$setup_entries_json" | jq -e '
      any(.[]; .Text == "Secrets") | not
    ' >/dev/null
    # Restore the pointer file and agenix-secrets.
    printf '%s\n' "$NIXOS_CONFIG_DIR" > "$KEYSTONE_SYSTEM_FLAKE_POINTER_FILE"
    mv "$PWD/hidden-agenix-secrets" "$NIXOS_CONFIG_DIR/agenix-secrets"

    keystone-secrets-menu dispatch $'view-value\tsecrets/ncrmro-github-token.age'
    grep -E 'agenix(\\ |-d|-i|.*-d.*-i)' "$XDG_RUNTIME_DIR/detach-command.txt" >/dev/null
    grep -F '.age/yubikey-identity.txt' "$XDG_RUNTIME_DIR/detach-command.txt" >/dev/null

    keystone-secrets-menu dispatch $'rekey\tsecrets/ncrmro-github-token.age'
    grep -E 'hwrekey(\\ |-m|.*-m)' "$XDG_RUNTIME_DIR/detach-command.txt" >/dev/null

    touch "$out"
  ''
