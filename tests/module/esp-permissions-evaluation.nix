{
  pkgs,
  lib,
  self,
}:
let
  evaluate =
    type:
    (import "${pkgs.path}/nixos/lib/eval-config.nix") {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.operating-system
        {
          system.stateVersion = "25.05";
          networking.hostId = "deadbeef";
          keystone.os = {
            enable = true;
            storage = {
              inherit type;
              devices = [ "/dev/vda" ];
            };
          };
        }
      ];
    };

  zfs = evaluate "zfs";
  lvm = evaluate "lvm";
  expected = [ "umask=0077" ];

  zfsDiskoOptions = zfs.config.disko.devices.disk.disk0.content.partitions.esp.content.mountOptions;
  lvmDiskoOptions = lvm.config.disko.devices.disk.root.content.partitions.esp.content.mountOptions;
  zfsFileSystemOptions = zfs.config.fileSystems."/boot".options;
  lvmFileSystemOptions = lvm.config.fileSystems."/boot".options;

  assertPrivate =
    backend: diskoOptions: fileSystemOptions:
    assert lib.assertMsg (diskoOptions == expected) (
      "${backend} ESP Disko options must be ${builtins.toJSON expected}, got "
      + builtins.toJSON diskoOptions
    );
    assert lib.assertMsg (lib.elem "umask=0077" fileSystemOptions) (
      "${backend} /boot filesystem options must include umask=0077, got "
      + builtins.toJSON fileSystemOptions
    );
    true;
in
assert assertPrivate "ZFS" zfsDiskoOptions zfsFileSystemOptions;
assert assertPrivate "LVM" lvmDiskoOptions lvmFileSystemOptions;
assert zfs.config.boot.lanzaboote.enable;
assert lvm.config.boot.lanzaboote.enable;
assert !zfs.config.boot.loader.systemd-boot.enable;
assert !lvm.config.boot.loader.systemd-boot.enable;
pkgs.runCommand "esp-permissions-evaluation" { } ''
  touch "$out"
''
