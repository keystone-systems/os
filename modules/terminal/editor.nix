{
  config,
  lib,
  pkgs,
  keystoneInputs ? { },
  ...
}:
with lib;
let
  cfg = config.keystone.terminal;
  # Use unstable helix if keystoneInputs.nixpkgs-unstable is available, otherwise use stable
  helix-pkg =
    if keystoneInputs ? nixpkgs-unstable then
      (import keystoneInputs.nixpkgs-unstable {
        system = pkgs.stdenv.hostPlatform.system;
        config.allowUnfree = true;
      }).helix
    else
      pkgs.helix;
  # Kinda-nvim theme if available
  hasKindaNvim = keystoneInputs ? kinda-nvim-hx;
in
{
  config = mkIf cfg.enable {
    # Set the default editor
    home.sessionVariables = {
      EDITOR = cfg.editor;
      VISUAL = cfg.editor;
    };

    home.packages =
      with pkgs;
      [
        # LSP packages for Helix
        bash-language-server
        docker-compose-language-service
        yaml-language-server
        dockerfile-language-server
        vscode-langservers-extracted
        helm-ls
        ruby-lsp
        solargraph
        # `nodePackages` namespace was removed from nixpkgs unstable —
        # prettier moved to a top-level attr.
        prettier
        harper
        pandoc
        marksman
        zk
        xdg-utils
        # Helper script for Markdown preview in Helix
        # We use a script with :pipe because:
        # 1. Helix's % expansion in :sh commands is finicky (requires %% escaping in Nix, but sometimes fails in Helix)
        # 2. It allows previewing unsaved buffers (streaming content via stdin)
        # 3. It creates a robust environment with absolute paths for pandoc/xdg-open
        (writeShellScriptBin "helix-preview-markdown" ''
          LOG="/tmp/helix-preview.log"
          echo "--- $(date) ---" >> "$LOG"
          temp_file=$(mktemp)
          cat > "$temp_file"

          ${pkgs.pandoc}/bin/pandoc -f markdown "$temp_file" -o /tmp/helix-preview.html 2>> "$LOG"

          if [ $? -eq 0 ]; then
            echo "Pandoc success" >> "$LOG"
            URL="file:///tmp/helix-preview.html"
            
            # Copy to clipboard
            CMD="${if pkgs.stdenv.isDarwin then "pbcopy" else "${pkgs.wl-clipboard}/bin/wl-copy"}"
            if command -v $CMD >/dev/null 2>&1 || [ -x "$CMD" ]; then
               echo -n "$URL" | $CMD
               echo "Copied to clipboard: $URL" >> "$LOG"
            else
               echo "Clipboard command not found: $CMD" >> "$LOG"
            fi

            # Open in browser
            ${pkgs.xdg-utils}/bin/xdg-open /tmp/helix-preview.html >> "$LOG" 2>&1 &
          else
            echo "Pandoc failed" >> "$LOG"
          fi

          cat "$temp_file"
          rm "$temp_file"
        '')
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.wl-clipboard ];

    # Helix - Modal text editor
    # https://helix-editor.com/
    programs.helix = {
      enable = mkDefault true;
      package = mkDefault helix-pkg;
      settings = mkDefault {
        # Use kinda_nvim theme if available, otherwise use default
        theme = if hasKindaNvim then "kinda_nvim" else "default";
        editor = {
          line-number = "absolute";
          mouse = true;
          clipboard-provider = "wayland";
          text-width = 120;
          soft-wrap = {
            enable = true;
            wrap-at-text-width = true;
          };
          cursor-shape = {
            insert = "bar";
            normal = "block";
            select = "underline";
          };
        };
        keys.normal = {
          ret = ":write";
          # Keystone Helix Commands
          # Tutorial: https://helix-editor-tutorials.com/tutorials/writing-documentation-and-prose-in-markdown-using-helix/
          F6 = [
            "select_all"
            ":pipe helix-preview-markdown"
            "collapse_selection"
          ];
          F7 = ":toggle soft-wrap.enable";
        };
      };
      languages = with pkgs; {
        language-server = {
          typescript-language-server = {
            command = "${typescript-language-server}/bin/typescript-language-server";
            args = [ "--stdio" ];
            config = {
              documentFormatting = false;
              tsserver = {
                path = "./node_modules/typescript/lib";
                fallbackPath = "${typescript}/lib/node_modules/typescript/lib";
              };
            };
          };
          bash-language-server = {
            command = "${bash-language-server}/bin/bash-language-server";
            args = [ "start" ];
          };
          docker-compose-language-service = {
            command = "${docker-compose-language-service}/bin/docker-compose-langserver";
            args = [ "--stdio" ];
          };
          yaml-language-server = {
            command = "${yaml-language-server}/bin/yaml-language-server";
            args = [ "--stdio" ];
          };
          dockerfile-language-server = {
            command = "${dockerfile-language-server}/bin/docker-langserver";
            args = [ "--stdio" ];
          };
          vscode-json-language-server = {
            command = "${vscode-langservers-extracted}/bin/vscode-json-language-server";
            args = [ "--stdio" ];
          };
          vscode-css-language-server = {
            command = "${vscode-langservers-extracted}/bin/vscode-css-language-server";
            args = [ "--stdio" ];
          };
          vscode-html-language-server = {
            command = "${vscode-langservers-extracted}/bin/vscode-html-language-server";
            args = [ "--stdio" ];
          };
          helm-ls = {
            command = "${helm-ls}/bin/helm_ls";
            args = [ "serve" ];
          };
          ruby-lsp = {
            command = "${ruby-lsp}/bin/ruby-lsp";
          };
          solargraph = {
            command = "${solargraph}/bin/solargraph";
            args = [ "stdio" ];
          };
          harper-ls = {
            command = "${harper}/bin/harper-ls";
            args = [ "--stdio" ];
          };
          marksman = {
            command = "${marksman}/bin/marksman";
            args = [ "server" ];
          };
          zk-lsp = {
            command = "${zk}/bin/zk";
            args = [ "lsp" ];
          };
        };
        language = [
          {
            name = "nix";
            auto-format = true;
            formatter.command = "${pkgs.nixfmt}/bin/nixfmt";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "bash";
            language-servers = [
              "bash-language-server"
              "harper-ls"
            ];
          }
          {
            name = "yaml";
            language-servers = [ "yaml-language-server" ];
          }
          {
            name = "dockerfile";
            language-servers = [ "dockerfile-language-server" ];
          }
          {
            name = "docker-compose";
            language-servers = [
              "docker-compose-language-service"
              "yaml-language-server"
            ];
          }
          {
            name = "json";
            language-servers = [ "vscode-json-language-server" ];
          }
          {
            name = "json5";
            language-servers = [ "vscode-json-language-server" ];
          }
          {
            name = "css";
            language-servers = [ "vscode-css-language-server" ];
          }
          {
            name = "html";
            language-servers = [
              "vscode-html-language-server"
              "harper-ls"
            ];
          }
          {
            name = "typescript";
            formatter = {
              command = "prettier";
              args = [
                "--parser"
                "typescript"
              ];
            };
            auto-format = true;
            language-servers = [
              "typescript-language-server"
              "harper-ls"
            ];
          }
          {
            name = "helm";
            language-servers = [ "helm-ls" ];
          }
          {
            name = "ruby";
            language-servers = [
              "ruby-lsp"
              "solargraph"
              "harper-ls"
            ];
          }
          {
            name = "markdown";
            language-servers = [
              "marksman"
              "zk-lsp"
              "harper-ls"
            ];
            auto-format = true;
            formatter = {
              command = "prettier";
              args = [
                "--parser"
                "markdown"
              ];
            };
          }
          {
            name = "c";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "cmake";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "cpp";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "c-sharp";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "dart";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "git-commit";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "go";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "haskell";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "java";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "javascript";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "jsx";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "lua";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "php";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "python";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "rust";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "scala";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "solidity";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "swift";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "toml";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "tsx";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "typst";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "kotlin";
            language-servers = [ "harper-ls" ];
          }
          {
            name = "clojure";
            language-servers = [ "harper-ls" ];
          }
        ];
      };
    };

    # Copy helix theme files from the flake input (if available)
    xdg.configFile."helix/themes/kinda_nvim.toml" = mkIf hasKindaNvim {
      source = "${keystoneInputs.kinda-nvim-hx}/kinda_nvim.toml";
    };
    xdg.configFile."helix/themes/kinda_nvim_light.toml" = mkIf hasKindaNvim {
      source = "${keystoneInputs.kinda-nvim-hx}/kinda_nvim_light.toml";
    };
  };
}
