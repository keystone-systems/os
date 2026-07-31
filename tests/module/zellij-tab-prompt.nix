{
  pkgs,
  lib,
  self,
  home-manager,
}:
let
  hmConfig = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      self.homeModules.notes
      self.homeModules.terminal
      {
        nixpkgs.overlays = [ self.overlays.default ];
        home.username = "testuser";
        home.homeDirectory = "/home/testuser";
        home.stateVersion = "25.05";

        keystone.terminal = {
          enable = true;
          sandbox.enable = false;
          git = {
            userName = "Test User";
            userEmail = "testuser@example.com";
          };
        };
      }
    ];
  };

  zellijConfig = hmConfig.config.xdg.configFile."zellij/config.kdl".text or "";
  zshInit = hmConfig.config.programs.zsh.initContent or "";
in
pkgs.runCommand "zellij-tab-prompt-check" { } ''
    zellij_config_file="$TMPDIR/zellij-config.kdl"
    zsh_init_file="$TMPDIR/zsh-init.sh"

    cat >"$zellij_config_file" <<'EOF_ZELLIJ'
  ${zellijConfig}
  EOF_ZELLIJ

    cat >"$zsh_init_file" <<'EOF_ZSH'
  ${zshInit}
  EOF_ZSH

    if ! grep -Fq 'Run "' "$zellij_config_file"; then
      echo "FAIL: zellij config is missing the Run action for Ctrl+t" >&2
      cat "$zellij_config_file" >&2
      exit 1
    fi

    if ! grep -Fq 'keystone-zellij-new-tab-prompt' "$zellij_config_file"; then
      echo "FAIL: zellij config is missing the visible new-tab prompt command" >&2
      cat "$zellij_config_file" >&2
      exit 1
    fi

    if ! grep -Fq 'floating true' "$zellij_config_file"; then
      echo "FAIL: zellij config is missing the floating prompt setting" >&2
      cat "$zellij_config_file" >&2
      exit 1
    fi

    if ! grep -Fq 'close_on_exit true' "$zellij_config_file"; then
      echo "FAIL: zellij config is missing the close_on_exit setting for the prompt" >&2
      cat "$zellij_config_file" >&2
      exit 1
    fi

    if ! grep -Fq 'zellij action pipe' "$zsh_init_file"; then
      echo "FAIL: zsh init is missing the plugin-backed tab rename helper" >&2
      cat "$zsh_init_file" >&2
      exit 1
    fi

    if ! grep -Fq 'zellij action new-tab --cwd "$tab_cwd" --name "$title"' "$zsh_init_file"; then
      echo "FAIL: zsh init is missing the explicit cwd for new tabs" >&2
      cat "$zsh_init_file" >&2
      exit 1
    fi

    if ! grep -Fq -- '--close-on-exit' "$zsh_init_file" || ! grep -Fq -- '--cwd "$tab_cwd"' "$zsh_init_file"; then
      echo "FAIL: zsh init is missing the explicit cwd for the floating new-tab prompt" >&2
      cat "$zsh_init_file" >&2
      exit 1
    fi

    if ! grep -Fq 'zellij-tab-name.wasm' "$zsh_init_file"; then
      echo "FAIL: zsh init is missing the zellij-tab-name plugin reference" >&2
      cat "$zsh_init_file" >&2
      exit 1
    fi

    touch "$out"
''
