# Standalone notes module wrapper.
#
# The OS composition imports core.nix because ks.systems/terminal already
# declares keystone.experimental at Home Manager scope.
{
  imports = [
    ../shared/experimental.nix
    ./core.nix
  ];
}
