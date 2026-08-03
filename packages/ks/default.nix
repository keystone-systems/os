# ks — Keystone CLI, a shell front end over nixos-rebuild, ks-fleet,
# keystone-approve-exec, and the hardware-key tools.
#
# The CLI was a 35k-line Rust crate until 2026-08-02. It grew subcommands
# for photos, screenshots, tasks, projects, and notifications that no
# module ever wired up, and every one of them cost a Rust toolchain in CI.
# What the fleet actually invokes is small enough to read in one sitting,
# so it lives in ks.sh now. Add a subcommand here only when a module, a
# desktop menu, or the contributor workflow calls it.
{
  lib,
  writeShellApplication,
  age-plugin-yubikey,
  coreutils,
  git,
  gnugrep,
  gnused,
  hostname,
  jq,
  kubectl,
  nix,
  nixos-rebuild,
  openssh,
  pam_u2f,
  sops,
  ssh-to-age,
  yubikey-manager,
}:
writeShellApplication {
  name = "ks";

  runtimeInputs = [
    age-plugin-yubikey
    coreutils
    git
    gnugrep
    gnused
    hostname
    # `secrets sync` parses nix eval --json and derives age recipients from
    # each host's ssh key.
    jq
    kubectl
    nix
    nixos-rebuild
    openssh
    pam_u2f
    sops
    ssh-to-age
    yubikey-manager
  ];

  text = builtins.readFile ./ks.sh;

  meta = with lib; {
    description = "Keystone CLI for building, deploying, and enrolling hardware keys";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "ks";
  };
}
