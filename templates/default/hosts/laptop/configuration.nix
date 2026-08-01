{ ... }:
{
  # Optional host-specific overrides.
  #
  # Keep the core machine shape in flake.nix so readers can see the archetype,
  # admin, shared users, Keystone modules, and service enables in one place.
  #
  # Keystone's terminal module already ships git, helix, zsh, zellij, starship,
  # and the rest of the core CLI environment — no need to add them here.
  #
  # Add extra host-only settings when they do not belong in the top-level
  # machine declaration. Examples:
  #
  # services.printing.enable = true;
  # networking.firewall.allowedTCPPorts = [ 22 80 443 ];
  # environment.systemPackages = with pkgs; [ wireshark ];  # add `pkgs` to the args above

  # ---------------------------------------------------------------------------
  # GitHub PAT secret (optional — uncomment with Step 8 of onboarding).
  # See docs/keystone/github-token.md for the full setup.
  # ---------------------------------------------------------------------------
  #
  # Keystone's operating-system module imports sops-nix, and mkSystemFlake
  # defaults `keystone.secrets.dir` to this repo's `secrets/` directory — you
  # just declare the secret here. (If you move the secrets directory, set
  # `keystone.secrets.dir` yourself; without it, provided secrets materialize
  # nothing and the build warns.)
  #
  # Requires:
  #   - a `<username>-github-token` key added to this host's sops file via
  #     `ks secrets edit secrets/laptop.yaml`
  #   - secrets/recipients.nix including your admin key (then `ks secrets sync`)
  #
  # Replace <username> below with the value from flake.nix `admin.username`.
  #
  # keystone.secrets.provided."<username>-github-token" = {
  #   owner = "<username>";
  #   scope = "host";
  # };
  #
  # programs.zsh.interactiveShellInit = ''
  #   # Read the sops-decrypted PAT into the env so gh + ks pick it up.
  #   # Read at shell start (not via session vars) to keep the secret out of
  #   # the Nix store at evaluation time.
  #   if [ -f /run/secrets/<username>-github-token ]; then
  #     export GITHUB_TOKEN="$(tr -d '\n' < /run/secrets/<username>-github-token)"
  #   fi
  # '';
}
