{ lib, ... }:
with lib;
{
  options.keystone.domain = mkOption {
    type = types.nullOr types.str;
    default = null;
    example = "example.com";
    description = ''
      Shared top-level domain for all Keystone services.
      Used by both OS agents (mail, bitwarden) and server services (harmonia, grafana).
      Set once per infrastructure to avoid repetition across modules.
    '';
  };
}
