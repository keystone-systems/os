# Shell environment — Zsh, starship prompt, zoxide, direnv, zellij, and CLI tools.
# Includes zellij layout presets (dev, ops, write) for the context system.
#
# Implements REQ-002 (FR-001: Shell Environment, FR-003: Terminal Multiplexer)
# See conventions/tool.nix-devshell.md
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal;
  notesPath = config.keystone.notes.path or "${config.home.homeDirectory}/notes";
  devScripts = import ../shared/dev-script-link.nix { inherit lib; };
  inherit (devScripts) mkHomeRepoFiles;
  zellijNewTabPrompt = pkgs.writeShellScriptBin "keystone-zellij-new-tab-prompt" ''
    printf '\nName new tab: '
    IFS= read -r tab_name

    if [[ -z "$tab_name" ]]; then
      exit 0
    fi

    # Avoid inheriting a deleted worktree cwd, which can wedge new-tab creation.
    tab_cwd="''${PWD:-$HOME}"
    if [[ -z "$tab_cwd" || ! -d "$tab_cwd" ]]; then
      tab_cwd="$HOME"
    fi

    if ! ${pkgs.coreutils}/bin/timeout 5s \
      ${pkgs.zellij}/bin/zellij action new-tab --cwd "$tab_cwd" --name "$tab_name"; then
      printf 'Failed to create tab. Try again from a live shell in the target directory.\n' >&2
      sleep 2
      exit 1
    fi
  '';
  ksCommand = {
    home.packages = [ pkgs.keystone.ks ];
  };
in
{
  config = mkIf cfg.enable (mkMerge [
    {
      home.sessionVariables = {
        ZK_NOTEBOOK_DIR = notesPath;
      };

      # Starship - A minimal, blazing-fast, and infinitely customizable prompt for any shell
      # Shows git status, language versions, execution time, and more in your terminal prompt
      # https://starship.rs/
      programs.starship.enable = true;

      # Zoxide - A smarter cd command that learns your navigation patterns
      # Tracks your most used directories and lets you jump to them with 'z <partial-name>'
      # Example: 'z proj' jumps to ~/repos/projects, 'zi' for interactive selection
      # https://github.com/ajeetdsouza/zoxide
      programs.zoxide = {
        enable = true;
        enableZshIntegration = true;
      };

      # Direnv - Unclutter your .profile
      # Loads and unloads environment variables depending on the current directory
      # https://direnv.net/
      programs.direnv = {
        enable = true;
        enableZshIntegration = true;
        nix-direnv.enable = true;
      };

      # Zellij - A terminal multiplexer with layouts, panes, and tabs
      # Modern alternative to tmux/screen with built-in session management
      # https://zellij.dev/
      programs.zellij = {
        enable = true;
        enableZshIntegration = false;
        settings = {
          theme = "current";
          startup_tips = false;
          pane_frames = false;
          # Ctrl+punctuation bindings such as Ctrl+, need extended keyboard reporting.
          support_kitty_keyboard_protocol = true;
          keybinds = {
            normal = {
              # Previous tab: Ctrl+,
              "bind \"Ctrl ,\"" = {
                GoToPreviousTab = { };
              };
              # Previous tab: Ctrl+PageUp
              "bind \"Ctrl PageUp\"" = {
                GoToPreviousTab = { };
              };
              # Next tab: Ctrl+.
              "bind \"Ctrl .\"" = {
                GoToNextTab = { };
              };
              # Next tab: Ctrl+PageDown
              "bind \"Ctrl PageDown\"" = {
                GoToNextTab = { };
              };
              # Move tab left: Ctrl+<
              "bind \"Ctrl <\"" = {
                MoveTab = "Left";
              };
              # Move tab right: Ctrl+>
              "bind \"Ctrl >\"" = {
                MoveTab = "Right";
              };
              # New tab: Ctrl+T
              # Open a visible floating prompt instead of the subtle RenameTab mode UI.
              "bind \"Ctrl t\"" = {
                Run = {
                  _args = [
                    "${zellijNewTabPrompt}/bin/keystone-zellij-new-tab-prompt"
                  ];
                  floating = true;
                  close_on_exit = true;
                };
              };
              # Close tab: Ctrl+W
              "bind \"Ctrl w\"" = {
                CloseTab = { };
              };
              # Unbind default Ctrl+G (conflict with Claude Code)
              "unbind \"Ctrl g\"" = [ ];
              # Lock mode: Ctrl+Shift+G
              "bind \"Ctrl Shift g\"" = {
                SwitchToMode = "locked";
              };
              # Unbind default Ctrl+O (conflict with Claude Code and lazygit)
              "unbind \"Ctrl o\"" = [ ];
              # Session mode: Ctrl+Shift+O
              "bind \"Ctrl Shift o\"" = {
                SwitchToMode = "session";
              };
            };
          };
        };
      };

      # Fzf - A command-line fuzzy finder
      # https://github.com/junegunn/fzf
      programs.fzf = {
        enable = true;
        enableZshIntegration = true;
      };

      # Bat - A cat(1) clone with wings (syntax highlighting and Git integration)
      # https://github.com/sharkdp/bat
      programs.bat = {
        enable = true;
      };

      programs.zsh = {
        enable = true;
        enableCompletion = mkDefault true;
        autosuggestion.enable = mkDefault true;
        syntaxHighlighting.enable = mkDefault true;
        shellAliases = {
          # Better unix commands
          l = "eza -1l";
          ls = "eza -1l";
          grep = "rg";
          # Local Development
          g = "git";
          lg = "lazygit";
          # Terminal utilities
          zs = "zesh connect"; # Zellij session manager with zoxide integration
          y = "yazi";
        };
        history.size = 100000;
        zplug.enable = lib.mkForce false;
        oh-my-zsh = {
          enable = true;
          plugins = [
            "git"
            "colored-man-pages"
          ];
          theme = "robbyrussell";
        };
        initContent = ''
          _keystone_zellij_effective_cwd() {
            local cwd="''${PWD:-$HOME}"

            if [[ -z "$cwd" || ! -d "$cwd" ]]; then
              cwd="$HOME"
            fi

            print -r -- "$cwd"
          }

          _keystone_zellij_pipe_tab_name() {
            [[ -n "''${ZELLIJ:-}" && -n "''${ZELLIJ_PANE_ID:-}" ]] || return 1

            local title="$1"
            local payload
            payload="$(${pkgs.jq}/bin/jq -nc \
              --arg pane_id "$ZELLIJ_PANE_ID" \
              --arg name "$title" \
              '{ pane_id: $pane_id, name: $name }')"

            ${pkgs.zellij}/bin/zellij action pipe \
              --plugin "file:${pkgs.keystone.zellij-tab-name}/share/zellij/plugins/zellij-tab-name.wasm" \
              --name change-tab-name \
              -- "$payload" >/dev/null 2>&1
          }

          ztab() {
            if [[ $# -eq 0 ]]; then
              print "usage: ztab <name>" >&2
              return 1
            fi

            _keystone_zellij_pipe_tab_name "$*"
          }

          znewtab() {
            local title="$*"
            local tab_cwd
            tab_cwd="$(_keystone_zellij_effective_cwd)"

            if [[ -n "$title" ]]; then
              ${pkgs.coreutils}/bin/timeout 5s \
                ${pkgs.zellij}/bin/zellij action new-tab --cwd "$tab_cwd" --name "$title"
            else
              ${pkgs.zellij}/bin/zellij run \
                --floating \
                --close-on-exit \
                --cwd "$tab_cwd" \
                -- "${zellijNewTabPrompt}/bin/keystone-zellij-new-tab-prompt"
            fi
          }
        '';
      };

      home.sessionPath = [ "$HOME/.local/bin" ];

      home.packages =
        with pkgs;
        [
          # Bottom - Graphical process/system monitor
          # https://github.com/ClementTsang/bottom
          bottom

          # Dust - A more intuitive version of du in rust
          # https://github.com/bootandy/dust
          dust

          # Fd - A simple, fast and user-friendly alternative to 'find'
          # https://github.com/sharkdp/fd
          fd

          # Ncdu - NCurses Disk Usage
          # https://dev.yorhel.nl/ncdu
          ncdu

          # Sd - Intuitive find & replace CLI (sed alternative)
          # https://github.com/chmln/sd
          sd

          # Tealdeer - A fast tldr client in Rust (simplified man pages)
          # https://github.com/dbrgn/tealdeer
          tealdeer

          # Direnv - Unclutter your .profile
          # https://direnv.net/
          direnv

          # Eza - Modern replacement for ls with colors and git integration
          # https://github.com/eza-community/eza
          eza

          zellijNewTabPrompt

          # Glow - Render markdown on the CLI with style
          # https://github.com/charmbracelet/glow
          glow

          # WeasyPrint - HTML/CSS to PDF converter (used by ks print)
          # https://weasyprint.org/
          python3Packages.weasyprint

          # GNU Make - Build automation tool
          # https://www.gnu.org/software/make/
          gnumake

          # Htop - Interactive process viewer
          # https://htop.dev/
          htop

          # GitHub CLI - GitHub's official command line tool
          # https://cli.github.com/
          gh

          # Lazygit - Simple terminal UI for git commands
          # https://github.com/jesseduffield/lazygit
          lazygit

          # Ripgrep - Fast search tool that recursively searches directories
          # https://github.com/BurntSushi/ripgrep
          ripgrep

          # Tree - Display directory structure as a tree
          # https://mama.indstate.edu/users/ice/tree/
          tree

          # Yazi - Blazing fast terminal file manager written in Rust
          # https://github.com/sxyazi/yazi
          yazi

          # Zesh - Zellij session manager with zoxide integration
          # https://github.com/roberte777/zesh
          # Provided via keystone overlay
          pkgs.keystone.zesh

          # Jq - Lightweight command-line JSON processor
          # https://jqlang.github.io/jq/
          jq

          # Yq - Portable command-line YAML processor
          # https://github.com/mikefarah/yq
          yq-go

          # Nixfmt - Official Nix code formatter (RFC style)
          # https://github.com/NixOS/nixfmt
          nixfmt
        ]
        ++ lib.optionals pkgs.stdenv.isLinux [
          # Ghostty terminfo - Required for SSH connections from Ghostty terminal
          # Without this, remote systems don't recognize TERM="xterm-ghostty" and
          # ncurses applications fail with "cannot initialize terminal type" errors.
          # This enables proper terminal handling when SSHing into this machine from Ghostty.
          # (Only available on Linux - macOS users install Ghostty via native app)
          ghostty.terminfo
        ];
    }
    # Enable flakes for Darwin (standalone home-manager)
    # On NixOS this is handled by keystone.os.nix.flakes
    (mkIf pkgs.stdenv.isDarwin {
      home.file.".config/nix/nix.conf".text = ''
        experimental-features = nix-command flakes
      '';
    })
    (mkHomeRepoFiles {
      inherit config;
      files = [
        {
          targetPath = ".config/zellij/layouts/dev.kdl";
          relativePath = "modules/terminal/layouts/dev.kdl";
          sourcePath = ./layouts/dev.kdl;
        }
        {
          targetPath = ".config/zellij/layouts/ops.kdl";
          relativePath = "modules/terminal/layouts/ops.kdl";
          sourcePath = ./layouts/ops.kdl;
        }
        {
          targetPath = ".config/zellij/layouts/write.kdl";
          relativePath = "modules/terminal/layouts/write.kdl";
          sourcePath = ./layouts/write.kdl;
        }
      ];
    })
    ksCommand
  ]);
}
