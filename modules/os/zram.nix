# Keystone OS Zram Module  [EXPERIMENTAL]
#
# EXPERIMENTAL: not part of the stable v1 surface; option surface and
# defaults may change as we tune for workstation/laptop/server profiles.
#
# Wraps nixpkgs `zramSwap` with keystone-flavoured defaults: a single
# zstd-compressed zram device sized at 50% of RAM and a higher
# vm.swappiness so the kernel actually reaches for compressed swap
# before evicting clean page-cache.
#
{ lib, config, ... }:
let
  osCfg = config.keystone.os;
  cfg = osCfg.zram;
in
{
  imports = [ ../shared/experimental.nix ];

  options.keystone.os.zram = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.keystone.experimental;
      description = ''
        Enable zstd-compressed RAM swap via the kernel zram device
        (EXPERIMENTAL).
      '';
    };

    memoryPercent = lib.mkOption {
      type = lib.types.ints.positive;
      default = 50;
      description = ''
        Cap on zram swap capacity as a percentage of physical RAM.
        Reflects the compressed-block-device size, not residency.
      '';
    };

    swappiness = lib.mkOption {
      type = lib.types.ints.between 0 200;
      default = 150;
      description = ''
        `vm.swappiness` value applied when zram is enabled. Default
        kernel value (60) is tuned for slow disk swap; with zram the
        backing store is RAM-fast and a higher value lets the kernel
        compress cold anonymous pages before evicting page-cache.
      '';
    };
  };

  config = lib.mkIf (osCfg.enable && cfg.enable) {
    # mkDefault so hosts can override individual zramSwap.* knobs (or
    # disable zramSwap entirely) without needing mkForce.
    zramSwap = {
      enable = lib.mkDefault true;
      algorithm = lib.mkDefault "zstd";
      memoryPercent = lib.mkDefault cfg.memoryPercent;
    };

    boot.kernel.sysctl."vm.swappiness" = lib.mkDefault cfg.swappiness;
  };
}
