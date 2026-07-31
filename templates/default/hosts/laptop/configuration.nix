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
  # `age.secrets.*` is already wired by Keystone's operating-system module — you
  # just declare the secret here.
  #
  # Requires:
  #   - secrets/<username>-github-token.age created via `nix shell nixpkgs#agenix
  #     --command agenix -e secrets/<username>-github-token.age`
  #   - secrets.nix recipients including this host's age pubkey
  #
  # Replace <username> below with the value from flake.nix `admin.username`.
  #
  # age.secrets."<username>-github-token" = {
  #   file = ../../secrets/<username>-github-token.age;
  #   owner = "<username>";
  #   mode = "0400";
  # };
  #
  # programs.zsh.interactiveShellInit = ''
  #   # Read the agenix-decrypted PAT into the env so gh + ks pick it up.
  #   # Read at shell start (not via session vars) to keep the secret out of
  #   # the Nix store at evaluation time.
  #   if [ -f /run/agenix/<username>-github-token ]; then
  #     export GITHUB_TOKEN="$(tr -d '\n' < /run/agenix/<username>-github-token)"
  #   fi
  # '';
}
