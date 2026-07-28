{ pkgs }:
pkgs.writeShellApplication {
  name = "ks-hardware-key-audit";
  runtimeInputs = with pkgs; [
    coreutils
    cryptsetup
    gnugrep
    jq
    openssh
    yubikey-manager
  ];
  # Evaluate the consumer with its caller-provided Nix. Pinning this tool's
  # Nixpkgs revision here can make an older Nix reject inputs the consumer's
  # own Nix accepts. KS_HARDWARE_KEY_NIX remains available for explicit use.
  text = builtins.readFile ../bin/ks-hardware-key-audit;
}
