{ ... }:
{
  imports = [
    ./loki.nix
    ./alloy.nix
    ./kube-prometheus-stack.nix
  ];
}
