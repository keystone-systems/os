# Ollama local LLM inference server
#
# Wraps NixOS services.ollama with keystone defaults suitable for
# workstations and desktops. Binds 0.0.0.0 by default so other
# tailnet machines can reach the API, which is safe because the
# existing firewall + Tailscale trusted interface setup restricts
# access to tailnet peers only.
#
# Usage:
#   keystone.os.services.ollama = {
#     enable = true;
#     acceleration = "vulkan";  # or "rocm", "cuda", null
#     models = [ "qwen3:32b" ];
#   };
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.os.services.ollama;

  # Map acceleration backend to the appropriate Ollama package variant.
  # nixpkgs removed services.ollama.acceleration in favor of package selection.
  ollamaPackage =
    if cfg.acceleration == "rocm" then
      pkgs.ollama-rocm
    else if cfg.acceleration == "cuda" then
      pkgs.ollama-cuda
    else if cfg.acceleration == "vulkan" then
      pkgs.ollama-vulkan
    else
      pkgs.ollama-cpu;
in
{
  options.keystone.os.services.ollama = {
    enable = mkEnableOption "Ollama local LLM inference server";

    acceleration = mkOption {
      type = types.nullOr (
        types.enum [
          "rocm"
          "cuda"
          "vulkan"
        ]
      );
      default = null;
      description = "GPU acceleration backend. null uses CPU only.";
      example = "vulkan";
    };

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Bind address. 0.0.0.0 allows access from tailnet peers.";
    };

    port = mkOption {
      type = types.port;
      default = 11434;
      description = "Listen port for the Ollama API.";
    };

    models = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Models to automatically pull on service activation.";
      example = [
        "qwen3:32b"
        "llama3.1:8b"
      ];
    };

    environmentVariables = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Extra environment variables for the Ollama service.";
      example = {
        OLLAMA_CONTEXT_LENGTH = "64000";
      };
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open the listen port in the firewall (needed for Tailscale cross-machine access).";
    };
  };

  config = mkIf cfg.enable {
    services.ollama = {
      enable = true;
      package = ollamaPackage;
      host = cfg.host;
      port = cfg.port;
      loadModels = cfg.models;
      environmentVariables = cfg.environmentVariables;
      openFirewall = cfg.openFirewall;
    };
  };
}
