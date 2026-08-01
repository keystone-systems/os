# Keystone Secrets
#
# Declarative secret interface backed by sops-nix. Consumer repos keep
# encrypted sops YAML files in-repo and point keystone.secrets.dir at them:
#
#   keystone.secrets.dir = ./secrets;
#
# Secrets are declared per host (or auto-declared by keystone modules) under
# keystone.secrets.provided.<name> and read back exclusively through the
# read-only `.path` accessor:
#
#   keystone.secrets.provided.grafana-api-token.scope = "shared";
#   ... config.keystone.secrets.provided.grafana-api-token.path ...
#
# Scope selects the sops file inside `dir`:
#   "host"        -> <dir>/<hostname>.yaml
#   "shared"      -> <dir>/shared.yaml
#   "service:<x>" -> <dir>/services/<x>.yaml
#
# Decryption uses the host's ed25519 SSH host key (via ssh-to-age); recipients
# are managed in the consumer repo's generated .sops.yaml (`ks secrets sync`).
{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.keystone.secrets;
  topConfig = config;

  scopeType =
    types.addCheck types.str (
      s: s == "host" || s == "shared" || (hasPrefix "service:" s && s != "service:")
    )
    // {
      description = ''string: "host", "shared", or "service:<name>"'';
    };

  sopsFileFor =
    scope:
    if scope == "host" then
      "${cfg.dir}/${config.networking.hostName}.yaml"
    else if scope == "shared" then
      "${cfg.dir}/shared.yaml"
    else
      "${cfg.dir}/services/${removePrefix "service:" scope}.yaml";

  providedType = types.submodule (
    { name, config, ... }:
    {
      options = {
        owner = mkOption {
          type = types.str;
          default = "root";
          description = "User that owns the decrypted secret file.";
        };
        group = mkOption {
          type = types.str;
          default = topConfig.users.users.${config.owner}.group or "root";
          defaultText = literalMD "{option}`users.users.\${owner}.group` if resolvable, else `\"root\"`";
          description = "Group of the decrypted secret file.";
        };
        mode = mkOption {
          type = types.str;
          default = "0400";
          description = "Permissions mode of the decrypted secret file, in octal.";
        };
        scope = mkOption {
          type = scopeType;
          default = "host";
          example = "service:k3s";
          description = ''
            Which sops file inside keystone.secrets.dir holds the secret:
            "host" (per-host file), "shared", or "service:<name>".
          '';
        };
        key = mkOption {
          type = types.str;
          default = name;
          description = "Key inside the sops YAML file. Defaults to the secret name.";
        };
        restartUnits = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "grafana.service" ];
          description = "Systemd units to restart when the decrypted secret changes.";
        };
        reloadUnits = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "nginx.service" ];
          description = "Systemd units to reload when the decrypted secret changes.";
        };
        path = mkOption {
          type = types.str;
          readOnly = true;
          # Fallback keeps the accessor usable in evaluations where the sops
          # backend is gated off (dir == null); it matches sops-nix's default.
          default = topConfig.sops.secrets.${name}.path or "/run/secrets/${name}";
          defaultText = literalExpression "config.sops.secrets.<name>.path";
          description = "Runtime path of the decrypted secret. Read-only accessor set by the backend.";
        };
      };
    }
  );

  generatedType = types.submodule {
    options = {
      persist = mkOption {
        type = types.enum [
          "host"
          "repo"
        ];
        default = "host";
        description = "Where the generated secret should persist.";
      };
      generator = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Freeform description/command of how to generate the secret. Currently unused.";
      };
    };
  };
in
{
  options.keystone.secrets = {
    dir = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = literalExpression "./secrets";
      description = ''
        Directory holding the consumer repo's sops-encrypted secret files.
        All sops backend configuration is gated on this being non-null.
      '';
    };

    provided = mkOption {
      type = types.attrsOf providedType;
      default = { };
      description = ''
        Secrets provided out-of-band (encrypted into the sops files under
        keystone.secrets.dir). Consumers read the decrypted runtime path via
        `config.keystone.secrets.provided.<name>.path`.
      '';
    };

    generated = mkOption {
      type = types.attrsOf generatedType;
      default = { };
      description = ''
        Declarations for host-generated secrets. Stub only: the generated
        backend is not implemented yet and materializes nothing.
      '';
    };
  };

  config = mkMerge [
    (mkIf (cfg.dir != null) {
      sops.secrets = mapAttrs (name: decl: {
        sopsFile = sopsFileFor decl.scope;
        inherit (decl)
          key
          owner
          group
          mode
          restartUnits
          reloadUnits
          ;
      }) cfg.provided;

      # Decrypt with the host's SSH host key (converted via ssh-to-age).
      # Explicit rather than relying on sops-nix's openssh-derived default.
      sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    })
    {
      warnings =
        optional (cfg.generated != { }) (
          "keystone.secrets.generated.${concatStringsSep ", " (attrNames cfg.generated)} declared "
          + "but the generated backend is not implemented yet; no secret will be materialized."
        )
        ++ optional (cfg.provided != { } && cfg.dir == null) (
          "keystone.secrets.provided.${concatStringsSep ", " (attrNames cfg.provided)} declared "
          + "but keystone.secrets.dir is null, so no secret will be materialized. "
          + "Set keystone.secrets.dir = ./secrets; (pointing at your repo's sops files)."
        );
    }
  ];
}
