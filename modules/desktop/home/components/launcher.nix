{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop;
  devScripts = import ../../../shared/dev-script-link.nix { inherit lib; };
  inherit (devScripts) mkHomeRepoFiles;
  themeDir = "${config.xdg.configHome}/keystone/current/theme";

  # Read and substitute the walker style.css template
  walkerStyleCss = builtins.replaceStrings [ "\${themeDir}" ] [ themeDir ] (
    builtins.readFile ./walker-style.css
  );

  # TODO(REQ-018.7a): Home Manager's Walker module currently embeds layout XML
  # inline, so this remains generated until Walker layouts can be referenced by
  # path without losing dev-mode behavior.
  walkerLayoutXml = builtins.readFile ./walker-layout.xml;
in
{
  # walker is imported via flake.nix homeModules.desktop (hoisted to avoid
  # _module.args infinite recursion when keystoneInputs is used in imports)

  config = mkIf cfg.enable (mkMerge [
    (mkHomeRepoFiles {
      inherit config;
      files = [
        {
          targetPath = ".local/share/applications/keystone-notes.desktop";
          relativePath = "modules/desktop/home/components/keystone-notes.desktop";
          sourcePath = ./keystone-notes.desktop;
        }
        {
          targetPath = ".config/elephant/menus/keystone-main.lua";
          relativePath = "modules/desktop/home/components/keystone-main.lua";
          sourcePath = ./keystone-main.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-learn.lua";
          relativePath = "modules/desktop/home/components/keystone-learn.lua";
          sourcePath = ./keystone-learn.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-capture.lua";
          relativePath = "modules/desktop/home/components/keystone-capture.lua";
          sourcePath = ./keystone-capture.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-screenshot.lua";
          relativePath = "modules/desktop/home/components/keystone-screenshot.lua";
          sourcePath = ./keystone-screenshot.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-toggle.lua";
          relativePath = "modules/desktop/home/components/keystone-toggle.lua";
          sourcePath = ./keystone-toggle.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-style.lua";
          relativePath = "modules/desktop/home/components/keystone-style.lua";
          sourcePath = ./keystone-style.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-theme.lua";
          relativePath = "modules/desktop/home/components/keystone-theme.lua";
          sourcePath = ./keystone-theme.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-system.lua";
          relativePath = "modules/desktop/home/components/keystone-system.lua";
          sourcePath = ./keystone-system.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-install.lua";
          relativePath = "modules/desktop/home/components/keystone-install.lua";
          sourcePath = ./keystone-install.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-update.lua";
          relativePath = "modules/desktop/home/components/keystone-update.lua";
          sourcePath = ./keystone-update.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-photos.lua";
          relativePath = "modules/desktop/home/components/keystone-photos.lua";
          sourcePath = ./keystone-photos.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-agents.lua";
          relativePath = "modules/desktop/home/components/keystone-agents.lua";
          sourcePath = ./keystone-agents.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-agent-actions.lua";
          relativePath = "modules/desktop/home/components/keystone-agent-actions.lua";
          sourcePath = ./keystone-agent-actions.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-setup.lua";
          relativePath = "modules/desktop/home/components/keystone-setup.lua";
          sourcePath = ./keystone-setup.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-hardware.lua";
          relativePath = "modules/desktop/home/components/keystone-hardware.lua";
          sourcePath = ./keystone-hardware.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-fingerprint.lua";
          relativePath = "modules/desktop/home/components/keystone-fingerprint.lua";
          sourcePath = ./keystone-fingerprint.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-monitors.lua";
          relativePath = "modules/desktop/home/components/keystone-monitors.lua";
          sourcePath = ./keystone-monitors.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-monitor-actions.lua";
          relativePath = "modules/desktop/home/components/keystone-monitor-actions.lua";
          sourcePath = ./keystone-monitor-actions.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-monitor-values.lua";
          relativePath = "modules/desktop/home/components/keystone-monitor-values.lua";
          sourcePath = ./keystone-monitor-values.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-printer.lua";
          relativePath = "modules/desktop/home/components/keystone-printer.lua";
          sourcePath = ./keystone-printer.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-wifi.lua";
          relativePath = "modules/desktop/home/components/keystone-wifi.lua";
          sourcePath = ./keystone-wifi.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-audio.lua";
          relativePath = "modules/desktop/home/components/keystone-audio.lua";
          sourcePath = ./keystone-audio.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-audio-devices.lua";
          relativePath = "modules/desktop/home/components/keystone-audio-devices.lua";
          sourcePath = ./keystone-audio-devices.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-accounts.lua";
          relativePath = "modules/desktop/home/components/keystone-accounts.lua";
          sourcePath = ./keystone-accounts.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-secrets.lua";
          relativePath = "modules/desktop/home/components/keystone-secrets.lua";
          sourcePath = ./keystone-secrets.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-secret-list.lua";
          relativePath = "modules/desktop/home/components/keystone-secret-list.lua";
          sourcePath = ./keystone-secret-list.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-secret-actions.lua";
          relativePath = "modules/desktop/home/components/keystone-secret-actions.lua";
          sourcePath = ./keystone-secret-actions.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-account-sections.lua";
          relativePath = "modules/desktop/home/components/keystone-account-sections.lua";
          sourcePath = ./keystone-account-sections.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-account-mailbox.lua";
          relativePath = "modules/desktop/home/components/keystone-account-mailbox.lua";
          sourcePath = ./keystone-account-mailbox.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-account-calendar.lua";
          relativePath = "modules/desktop/home/components/keystone-account-calendar.lua";
          sourcePath = ./keystone-account-calendar.lua;
        }
        {
          targetPath = ".config/elephant/menus/keystone-account-events.lua";
          relativePath = "modules/desktop/home/components/keystone-account-events.lua";
          sourcePath = ./keystone-account-events.lua;
        }
      ];
    })
    {
      # Wofi as the application launcher
      programs.wofi = {
        enable = mkDefault true;
        settings = {
          show = "drun";
          width = 600;
          height = 400;
          term = "ghostty";
          prompt = "Search...";
          allow_images = true;
          image_size = 24;
          insensitive = true;
        };
        style = ''
          @import "${config.xdg.configHome}/keystone/current/theme/wofi.css";
        '';
      };

      # Walker launcher using the official home-manager module
      programs.walker = {
        enable = mkDefault true;
        runAsService = true;

        config = {
          force_keyboard_focus = true;
          selection_wrap = true;
          theme = "keystone";
          resume_last_query = false;
          actions_as_menu = true;
          hide_action_hints = false;

          placeholders = {
            default = {
              input = " Search...";
              list = "No Results";
            };
            "menus:keystone-main" = {
              input = " Go";
              list = "No menu items available";
            };
            "menus:keystone-learn" = {
              input = " Learn";
              list = "No learn actions available";
            };
            "menus:keystone-capture" = {
              input = " Capture";
              list = "No capture actions available";
            };
            "menus:keystone-screenshot" = {
              input = " Screenshot";
              list = "No screenshot actions available";
            };
            "menus:keystone-toggle" = {
              input = " Toggle";
              list = "No toggle actions available";
            };
            "menus:keystone-style" = {
              input = " Style";
              list = "No style actions available";
            };
            "menus:keystone-theme" = {
              input = " Theme";
              list = "No themes found";
            };
            "menus:keystone-system" = {
              input = " System";
              list = "No system actions available";
            };
            "menus:keystone-install" = {
              input = " Install";
              list = "No install actions available";
            };
            "menus:keystone-update" = {
              input = " Update";
              list = "No update actions available";
            };
            "menus:keystone-photos" = {
              input = " Photos";
              list = "Search for a query to load photo results";
            };
            "menus:keystone-agents" = {
              input = " Agents";
              list = "No agents found";
            };
            "menus:keystone-agent-actions" = {
              input = " Agent actions";
              list = "No agent actions available";
            };
            "menus:keystone-monitors" = {
              input = " Monitors";
              list = "No monitors found";
            };
            "menus:keystone-setup" = {
              input = " Setup";
              list = "No setup actions available";
            };
            "menus:keystone-hardware" = {
              input = " Hardware";
              list = "No hardware actions available";
            };
            "menus:keystone-fingerprint" = {
              input = " Fingerprint";
              list = "No fingerprint actions available";
            };
            "menus:keystone-monitor-actions" = {
              input = " Monitor actions";
              list = "No actions available";
            };
            "menus:keystone-monitor-values" = {
              input = " Monitor values";
              list = "No values available";
            };
            "menus:keystone-printer" = {
              input = " Printers";
              list = "No printers found";
            };
            "menus:keystone-wifi" = {
              input = " Wi-Fi";
              list = "No Wi-Fi networks found";
            };
            "menus:keystone-audio" = {
              input = " Audio";
              list = "No audio actions available";
            };
            "menus:keystone-audio-devices" = {
              input = " Audio devices";
              list = "No audio devices found";
            };
            "menus:keystone-accounts" = {
              input = " Accounts";
              list = "No accounts found";
            };
            "menus:keystone-secrets" = {
              input = " Secrets";
              list = "No secret categories found";
            };
            "menus:keystone-secret-list" = {
              input = " Secret";
              list = "No secrets found";
            };
            "menus:keystone-secret-actions" = {
              input = " Secret actions";
              list = "No secret actions available";
            };
            "menus:keystone-account-sections" = {
              input = " Account actions";
              list = "No account actions available";
            };
            "menus:keystone-account-mailbox" = {
              input = " Mail";
              list = "No mail found";
            };
            "menus:keystone-account-calendar" = {
              input = " Calendars";
              list = "No calendars found";
            };
            "menus:keystone-account-events" = {
              input = " Events";
              list = "No events found";
            };
          };

          keybinds = {
            next = [ "Down" ];
            previous = [ "Up" ];
            quick_activate = [ ];
            show_actions = [ ];
          };

          providers = {
            max_results = 256;
            default = [
              "desktopapplications"
              "websearch"
            ];
            actions = {
              fallback = [
                {
                  action = "menus:open";
                  label = "open";
                  after = "Nothing";
                  default = true;
                }
                {
                  action = "erase_history";
                  label = "clear hist";
                  bind = "ctrl h";
                  after = "AsyncReload";
                }
              ];
            };
            prefixes = [
              {
                prefix = "/";
                provider = "providerlist";
              }
              {
                prefix = ".";
                provider = "files";
              }
              {
                prefix = ":";
                provider = "symbols";
              }
              {
                prefix = "=";
                provider = "calc";
              }
              {
                prefix = "@";
                provider = "websearch";
              }
              {
                prefix = "$";
                provider = "clipboard";
              }
            ];
          };
        };

        # Define the keystone theme
        themes.keystone = {
          style = walkerStyleCss;
          layouts = {
            layout = walkerLayoutXml;
          };
        };
      };
    }
  ]);
}
