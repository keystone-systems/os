{ pkgs, ... }:
# Macbook host — Home Manager module, NOT a NixOS module.
#
# macOS doesn't run NixOS, so this host doesn't get a `nixosConfigurations.macbook`.
# `kind = "macbook"` in flake.nix routes it through Keystone's mkSystemFlake
# into a `homeConfigurations.<name>` output instead. That's why there's no
# `hardware.nix` next to this file, no disko, no agenix, no system services —
# you're configuring a user environment that lives on top of someone else's
# macOS install (typically your own laptop).
#
# Allowed here:
#   - home.packages         — user-scope CLI tools
#   - home.sessionVariables — exported in the user's shell
#   - programs.*.enable     — Home Manager program modules (git, zsh, fzf, …)
#   - home.file.*           — dotfile management
#
# NOT allowed here (these are NixOS options and will fail to evaluate):
#   - environment.systemPackages, services.*, networking.*, users.*,
#     boot.*, age.secrets.*, etc.
#
# Deploy:
#   nix run nixpkgs#home-manager -- switch --flake .#<username>@macbook
# (or `home-manager switch --flake .#<username>@macbook` once Home Manager is
# already installed on the Mac). Replace `<username>` with `admin.username`
# from flake.nix.
{
  home.packages = with pkgs; [
    # jq
  ];
}
