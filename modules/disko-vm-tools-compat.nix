{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  vmToolsArgs = builtins.functionArgs (import (pkgs.path + "/pkgs/build-support/vm/default.nix"));
  splitKernelInterface = vmToolsArgs ? kernelModules;
  kernelPackages = config.disko.imageBuilder.kernelPackages;

  imageBuilderPkgs = pkgs.extend (
    _final: prev: {
      vmTools = prev.vmTools // {
        override =
          args:
          prev.vmTools.override (
            if args ? kernel && !(args.kernel ? target) then
              (removeAttrs args [ "kernel" ])
              // {
                kernel = kernelPackages.kernel;
                kernelModules = args.kernel;
              }
            else
              args
          );
      };
    }
  );
in
{
  config = lib.mkIf (options ? disko.imageBuilder.pkgs && splitKernelInterface) {
    # Disko currently passes an aggregate module tree as vmTools.kernel.
    # Newer Nixpkgs requires the bootable kernel and module tree separately.
    disko.imageBuilder.pkgs = lib.mkDefault imageBuilderPkgs;
  };
}
