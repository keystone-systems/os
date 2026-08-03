# Keystone glue for ks.systems/desktop — the ONLY desktop content left in
# this repo. The desktop flake owns the full keystone.desktop.* option
# surface and implementation; this module wires keystone-owned option values
# (which user, resolved routing, terminal/experimental integration) into it.
{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.keystone.desktop.enable {
    keystone.desktop.user = lib.mkDefault config.keystone.os.adminUsername;

    # resolved routing stays os-side: keystone.os owns services.resolved.
    # Route the desktop default through keystone.os so the core OS module
    # stays the single writer of services.resolved.enable.
    keystone.os.services.resolved.enable = lib.mkDefault true;
    # Required for Tailscale MagicDNS to work with systemd-resolved
    # https://github.com/NixOS/nixpkgs/issues/231191#issuecomment-1664053176
    environment.etc."resolv.conf".mode = "direct-symlink";

    home-manager.sharedModules = [
      (
        {
          config,
          pkgs,
          lib,
          ...
        }:
        {
          # keystone.experimental is normally declared at HM scope by the
          # terminal sharedModule (modules/terminal imports it). Import the
          # declaration path here too so the glue stays evaluable when the
          # desktop module is used without operating-system — path imports
          # deduplicate safely.
          imports = [ ../shared/experimental.nix ];

          # keystone-owned option values the standalone desktop flake may not
          # declare/set:
          keystone.terminal.enable = lib.mkDefault true; # desktop implies terminal
          keystone.desktop.photos.enable = lib.mkDefault config.keystone.experimental;
          keystone.desktop.agents.enable = lib.mkDefault config.keystone.experimental;
          # The Walker menus drive `ks menu update`, whose backend lived in
          # the Rust CLI. The shell CLI covers OS deploy, hardware keys,
          # secrets, and services — not menus — so this stays null and the
          # menu entries gate off, exactly like agenixPackage below.
          keystone.desktop.integration.ksPackage = lib.mkDefault null;
          # integration.agenixPackage stays unset: the desktop secrets menu is
          # agenix-based while keystone secrets moved to sops; the option is
          # null-tolerant, so the menu entry is simply gated off.
          home.packages = lib.mkIf config.keystone.desktop.enable [
            # Presentations — keystone-built, so it stays a keystone-side add.
            pkgs.keystone.slidev
          ];
        }
      )
    ];
  };
}
