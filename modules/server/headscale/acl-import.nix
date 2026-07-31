# Keystone Headscale ACL Import Module
#
# Merges auto-generated ACL rules from keystone.services with static rules
# and writes the combined policy to /etc/headscale/acl.hujson.
#
# Usage on headscale host:
#   keystone.headscale = {
#     enable = true;
#     aclRules = oceanConfig.keystone.services.generatedACLRules;
#     tagOwners = { ... };
#     staticACLs = [ ... ];
#   };
#
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.keystone.headscale;

  aclRuleType = lib.types.submodule {
    options = {
      action = lib.mkOption {
        type = lib.types.str;
        default = "accept";
      };
      comment = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      src = lib.mkOption { type = lib.types.listOf lib.types.str; };
      dst = lib.mkOption { type = lib.types.listOf lib.types.str; };
    };
  };

  # Strip null comments for clean JSON output
  cleanRule = rule: {
    inherit (rule) action src dst;
  };

  mergedPolicy = {
    tagOwners = cfg.tagOwners // cfg.generatedTagOwners;
    acls = map cleanRule (cfg.staticACLs ++ cfg.aclRules);
  };
in
{
  options.keystone.headscale = {
    tagOwners = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      description = "Headscale tag ownership mapping.";
    };

    staticACLs = lib.mkOption {
      type = lib.types.listOf aclRuleType;
      default = [ ];
      description = "Static ACL rules (base policy).";
    };

    generatedTagOwners = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      description = "Auto-generated tag owners from keystone.services.";
    };

    aclRules = lib.mkOption {
      type = lib.types.listOf aclRuleType;
      default = [ ];
      description = ''
        Auto-generated ACL rules from keystone.services.
        Typically passed from oceanConfig.keystone.services.generatedACLRules.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."headscale/acl.hujson" = {
      text = builtins.toJSON mergedPolicy;
      mode = "0644";
    };
  };
}
