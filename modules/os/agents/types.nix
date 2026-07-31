# Agent submodule type definition.
# Defines the schema for keystone.os.agents.<name>.
#
# Implements REQ-007 (OS Agents)
# See docs/specs/REQ-017-conventions-grafana-mcp.md (REQ-017.9: Grafana MCP options)
# See docs/specs/REQ-018-repo-management.md (REQ-018.14: agent notes path default)
# See docs/specs/REQ-023-executive-assistant-perception-layer.md (REQ-023.34: perception options)
# See docs/specs/REQ-024-agentic-calendar.md (REQ-024.22: calendar.teamEvents)
# See conventions/os.requirements.md
# See conventions/process.keystone-principal-parity.md
{
  lib,
  config,
  ...
}:
with lib;
let
  topDomain = config.keystone.domain;
  taskLoopProviderType = types.enum [
    "claude"
    "gemini"
    "codex"
  ];
  taskLoopEffortType = types.enum [
    "low"
    "medium"
    "high"
    "max"
  ];
  taskLoopProfileProviderSubmodule = types.submodule {
    options = {
      model = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Model name for this provider when the profile is selected.";
      };

      fallbackModel = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Fallback model for this provider when the primary model is unavailable.";
      };

      effort = mkOption {
        type = types.nullOr taskLoopEffortType;
        default = null;
        description = "Reasoning effort level for this provider. Currently only Claude consumes this value.";
      };
    };
  };
  taskLoopProfileSubmodule = types.submodule {
    options = {
      claude = mkOption {
        type = taskLoopProfileProviderSubmodule;
        default = { };
        description = "Claude-specific model settings for this task-loop profile.";
      };

      gemini = mkOption {
        type = taskLoopProfileProviderSubmodule;
        default = { };
        description = "Gemini-specific model settings for this task-loop profile.";
      };

      codex = mkOption {
        type = taskLoopProfileProviderSubmodule;
        default = { };
        description = "Codex-specific model settings for this task-loop profile.";
      };
    };
  };
  taskLoopStageSubmodule =
    {
      providerDefault ? null,
      profileDefault ? null,
      descriptionPrefix,
    }:
    types.submodule {
      options = {
        profile = mkOption {
          type = types.nullOr types.str;
          default = profileDefault;
          description = "${descriptionPrefix} profile name. Semantic profiles such as fast, medium, and max resolve to provider-specific model settings.";
          example = "fast";
        };

        provider = mkOption {
          type = types.nullOr taskLoopProviderType;
          default = providerDefault;
          description = "${descriptionPrefix} provider. If null, the task loop falls back to the next configured scope.";
        };

        model = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "${descriptionPrefix} explicit model override.";
          example = "sonnet";
        };

        fallbackModel = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "${descriptionPrefix} fallback model override.";
          example = "opus";
        };

        effort = mkOption {
          type = types.nullOr taskLoopEffortType;
          default = null;
          description = "${descriptionPrefix} reasoning effort override. Currently only Claude consumes this value.";
        };
      };
    };
in
{
  agentSubmodule = types.submodule (
    {
      name,
      config,
      ...
    }:
    {
      options = {
        uid = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = "User ID. If null, auto-assigned from the 4000+ range.";
        };

        archetype = mkOption {
          type = types.enum [
            "engineer"
            "product"
          ];
          default = "engineer";
          description = "Convention archetype for this agent. Controls which conventions are inlined vs referenced. Available: engineer, product. See conventions/archetypes.yaml.";
          example = "product";
        };

        capabilities = mkOption {
          type = types.listOf (
            types.enum [
              "ks"
              "ks-dev"
              "assistant"
              "notes"
              "project"
              "engineer"
              "product"
              "project-manager"
              "executive-assistant"
            ]
          );
          default = [ ];
          description = ''
            Extra Keystone AI workflow capabilities for this agent. These
            capabilities are merged with archetype and dev-mode defaults and
            gate what the generated `/ks` and `/ks-dev` skills may do.
          '';
          example = [
            "notes"
            "executive-assistant"
          ];
        };

        host = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Hostname where this agent primarily runs. Controls two things:

            1. Feature filtering — desktop, mail-client, and SSH resources
               (secrets, assertions, services), plus the agent's Home Manager
               profile, are only created on the host whose networking.hostName
               matches this value.

            2. All hosts still get the agent's OS user/group and home directory
               so the agent can SSH in everywhere.

            Server-side provisioning (mail.nix, git-server.nix) is independent
            of this field — it runs wherever Stalwart/Forgejo is enabled and
            is gated by mail.provision / git.provision instead.
          '';
          example = "ncrmro-workstation";
        };

        fullName = mkOption {
          type = types.str;
          description = "Display name for the agent";
          example = "Research Agent";
        };

        email = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Email address for the agent (used for git config and mail provisioning)";
          example = "researcher@ks.systems";
        };

        terminal = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable terminal environment (zsh, starship, helix, AI tools) via home-manager.";
          };
        };

        desktop = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable headless Wayland desktop (labwc + wayvnc).";
          };

          resolution = mkOption {
            type = types.str;
            default = "1920x1080";
            description = "Desktop resolution (WxH)";
          };

          vncPort = mkOption {
            type = types.nullOr types.port;
            default = null;
            description = "VNC port. If null, auto-assigned starting from 5901.";
          };

          vncBind = mkOption {
            type = types.str;
            default = "0.0.0.0";
            description = "Address for wayvnc to bind. Use 127.0.0.1 for localhost-only.";
          };
        };

        chrome = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable Chrome remote debugging via Chromium + DevTools MCP.";
          };

          debugPort = mkOption {
            type = types.nullOr types.port;
            default = null;
            description = "Chrome remote debugging port. If null, auto-assigned starting from 9222.";
          };

          mcp = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Enable Chrome DevTools MCP server for this agent.";
            };

            port = mkOption {
              type = types.nullOr types.port;
              default = null;
              description = "Chrome DevTools MCP server port. If null, auto-assigned starting from 3101.";
            };
          };
        };

        # Grafana MCP server for querying metrics and logs (REQ-017.9)
        grafana = {
          mcp = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = "Enable Grafana MCP server for this agent, providing access to Prometheus metrics and Loki logs.";
            };

            url = mkOption {
              type = types.str;
              default = if topDomain != null then "https://grafana.${topDomain}" else "";
              description = "Grafana URL for the MCP server connection.";
            };
          };
        };

        mail = {
          provision = mkOption {
            type = types.bool;
            default = false;
            description = "Auto-provision Stalwart mail account on the mail server host.";
          };

          address = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Full email address. Defaults to agent-{name}@{keystone.domain}.";
            example = "agent-researcher@ks.systems";
          };

          imap.port = mkOption {
            type = types.int;
            default = 993;
            description = "IMAP port";
          };

          smtp.port = mkOption {
            type = types.int;
            default = 465;
            description = "SMTP port";
          };

          # CalDAV and CardDAV are always provisioned alongside mail
        };

        github = {
          username = mkOption {
            type = types.str;
            default = name;
            description = "GitHub username. Defaults to the agent name. The task loop automatically fetches GitHub issues and PRs assigned to this user.";
            example = "octocat";
          };
        };

        forgejo = {
          username = mkOption {
            type = types.str;
            default = name;
            description = "Forgejo username. Defaults to the agent name. The task loop automatically fetches Forgejo issues and PRs assigned to this user.";
            example = "luce";
          };
        };

        # Tailscale: each agent gets its own tailscaled instance with unique
        # state dir, socket, and TUN interface. An nftables fwmark rule routes
        # the agent's UID traffic through its dedicated TUN.
        # Requires an agenix secret at age.secrets."agent-{name}-tailscale-auth-key".

        # SSH: each agent gets ssh-agent + git signing + agenix secrets.
        # Requires agenix secrets: agent-{name}-ssh-key, agent-{name}-ssh-passphrase.
        # CRITICAL: SSH public key is now declared in keystone.keys."agent-{name}"
        # instead of here. The single host key is read from the registry.

        git = {
          provision = mkOption {
            type = types.bool;
            default = false;
            description = "Auto-provision Forgejo user, SSH key, and notes repo on the git server host.";
          };

          username = mkOption {
            type = types.str;
            default = name;
            description = "Forgejo username. Defaults to agent name.";
          };

          host = mkOption {
            type = types.str;
            default = "git.${topDomain}";
            description = "Git server hostname. Defaults to git.{keystone.domain}.";
          };

          sshPort = mkOption {
            type = types.port;
            default = 2222;
            description = "Git SSH port.";
          };

          repoName = mkOption {
            type = types.str;
            default = "notes";
            description = "Name of auto-created notes repository.";
          };
        };

        passwordManager = {
          provision = mkOption {
            type = types.bool;
            default = false;
            description = "Emit provisioning instructions for Vaultwarden (no API available for auto-create).";
          };
        };

        notes = {
          repo = mkOption {
            type = types.str;
            default = "ssh://forgejo@${config.git.host}:${toString config.git.sshPort}/${config.git.username}/${config.git.repoName}.git";
            description = "Git repository URL for the agent's notes. Auto-derived from git options.";
            example = "ssh://forgejo@git.example.com:2222/user/notes.git";
          };

          path = mkOption {
            type = types.str;
            default = "/home/agent-${name}/notes";
            description = "Local checkout path for the notes repo.";
          };

          syncOnCalendar = mkOption {
            type = types.str;
            default = "*:0/5";
            description = "Systemd calendar spec for notes sync timer. Default: every 5 minutes.";
          };

          taskLoop = {
            onCalendar = mkOption {
              type = types.str;
              default = "*:0/5";
              description = "Systemd calendar spec for task loop timer. Default: every 5 minutes.";
            };

            maxTasks = mkOption {
              type = types.int;
              default = 5;
              description = "Maximum number of pending tasks to execute per run.";
            };

            defaults = mkOption {
              type = taskLoopStageSubmodule {
                providerDefault = "claude";
                profileDefault = null;
                descriptionPrefix = "Global task-loop default";
              };
              default = { };
              description = ''
                Global task-loop defaults shared by ingest, prioritize, and
                execute. Stage-specific settings and TASKS.yaml fields can
                override these values.
              '';
            };

            profiles = mkOption {
              type = types.attrsOf taskLoopProfileSubmodule;
              default = { };
              description = ''
                Custom task-loop model profiles keyed by semantic names such as
                fast, medium, or max. These extend and override the built-in
                profile catalog.
              '';
              example = literalExpression ''
                {
                  medium = {
                    claude = {
                      model = "sonnet";
                      fallbackModel = "opus";
                      effort = "medium";
                    };
                    gemini.model = "auto-gemini-3";
                  };
                }
              '';
            };

            ingest = mkOption {
              type = taskLoopStageSubmodule {
                descriptionPrefix = "Ingest-stage";
              };
              default = { };
              description = "Provider, profile, model, fallback model, and effort overrides for the ingest stage.";
            };

            prioritize = mkOption {
              type = taskLoopStageSubmodule {
                descriptionPrefix = "Prioritize-stage";
              };
              default = { };
              description = "Provider, profile, model, fallback model, and effort overrides for the prioritize stage.";
            };

            execute = mkOption {
              type = taskLoopStageSubmodule {
                descriptionPrefix = "Execute-stage";
              };
              default = { };
              description = "Provider, profile, model, fallback model, and effort overrides for task execution.";
            };
          };

          scheduler = {
            onCalendar = mkOption {
              type = types.str;
              default = "*-*-* 05:00:00";
              description = "Systemd calendar spec for scheduler timer. Default: daily at 5 AM.";
            };
          };
        };

        calendar = {
          teamEvents = mkOption {
            type = types.listOf (
              types.submodule {
                options = {
                  summary = mkOption {
                    type = types.str;
                    description = "Event summary (e.g. 'Weekly Retrospective').";
                    example = "Weekly Retrospective";
                  };
                  schedule = mkOption {
                    type = types.str;
                    description = "Recurrence in SCHEDULES.yaml format: daily, weekly:<day>, monthly:<day>.";
                    example = "weekly:friday";
                  };
                  time = mkOption {
                    type = types.str;
                    default = "20:00";
                    description = "Event start time in HH:MM format.";
                  };
                  workflow = mkOption {
                    type = types.str;
                    default = "";
                    description = "DeepWork workflow to invoke when this event triggers a task.";
                  };
                };
              }
            );
            default = [ ];
            description = ''
              Recurring team cadence events for the agent's CalDAV calendar.
              All events on the calendar become tasks — the calendar itself is the
              scheduling mechanism. These events must be created on the CalDAV
              server (e.g. via calendula or a CalDAV client). The scheduler reads
              events from the calendar and creates tasks with source: "calendar".
            '';
            example = [
              {
                summary = "Weekly Retrospective";
                schedule = "weekly:friday";
                time = "20:00";
                workflow = "retrospective/run";
              }
            ];
          };
        };

        mcp = {
          servers = mkOption {
            type = types.attrsOf (
              types.submodule {
                options = {
                  command = mkOption {
                    type = types.str;
                    description = "Absolute path to the MCP server binary.";
                  };
                  args = mkOption {
                    type = types.listOf types.str;
                    default = [ ];
                    description = "Arguments to pass to the MCP server.";
                  };
                  env = mkOption {
                    type = types.attrsOf types.str;
                    default = { };
                    description = "Environment variables for the MCP server.";
                  };
                };
              }
            );
            default = { };
            description = "Additional MCP servers to configure for this agent.";
          };
        };

        # Perception layer: document parsing, voice transcription,
        # screenshot syncing, contact linking, and activity reconstruction.
        # See docs/specs/REQ-023-executive-assistant-perception-layer.md
        perception = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable perception layer for this agent (PDF parsing, voice transcription, screenshot sync, contact linking, activity summaries).";
          };

          pdf = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Enable PDF-to-markdown conversion with bounding box citations.";
            };

            inputDir = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Watch directory for PDFs. Defaults to ~/documents/inbox.";
            };

            outputDir = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Output directory for parsed markdown + bbox JSON. Defaults to ~/documents/parsed.";
            };
          };

          voice = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Enable local voice transcription via whisper.cpp.";
            };

            inputDir = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Watch directory for audio files. Defaults to ~/voice/inbox.";
            };

            outputDir = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Output directory for transcripts. Defaults to ~/voice/transcripts.";
            };

            model = mkOption {
              type = types.enum [
                "tiny"
                "base"
                "small"
                "medium"
                "large"
              ];
              default = "base";
              description = "Whisper model size. Larger models are more accurate but slower.";
            };
          };

          screenshots = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Enable screenshot syncing to Immich for ML indexing.";
            };

            syncOnCalendar = mkOption {
              type = types.str;
              default = "*:0/5";
              description = "Systemd calendar expression for screenshot sync interval.";
            };
          };

          contacts = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Enable face-to-contact linking via Immich + CardDAV.";
            };
          };

          processor = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Enable activity reconstruction and notes sync.";
            };

            onCalendar = mkOption {
              type = types.str;
              default = "*:0/30";
              description = "Systemd calendar expression for perception processor interval.";
            };

            useOllama = mkOption {
              type = types.bool;
              default = false;
              description = "Use local Ollama for natural-language summaries and transcript correction.";
            };
          };
        };
      };
    }
  );
}
