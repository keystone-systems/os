{
  pkgs,
  lib,
  self,
}:
let
  evaluate =
    extra:
    (import "${pkgs.path}/nixos/lib/eval-config.nix") {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.operating-system
        self.nixosModules.desktop
        (
          { ... }:
          {
            system.stateVersion = "25.05";
            networking.hostId = "deadbeef";
            boot.loader.systemd-boot.enable = true;
            fileSystems."/" = {
              device = "rpool/crypt/system";
              fsType = "zfs";
            };
            keystone.desktop.enable = true;
            keystone.os = {
              enable = true;
              storage = {
                enable = false;
                type = "zfs";
              };
              hypervisor = {
                enable = false;
                client.enable = true;
              };
              users = {
                alice = {
                  fullName = "Alice";
                  initialPassword = "test";
                  admin = true;
                  desktop.enable = true;
                };
                bob = {
                  fullName = "Bob";
                  initialPassword = "test";
                };
              };
            };
          }
        )
        extra
      ];
    };
  defaults = evaluate { };
  overridden = evaluate {
    keystone.os.hypervisor.zvolStorage = {
      dataset = "rpool/crypt/scratch-vms";
      quota = "42G";
      volblocksize = "8K";
    };
  };
  datasets = defaults.config.keystone.os.storage.zfs.datasets;
  delegation = defaults.config.systemd.services.keystone-zvol-delegation.script;
  udev = defaults.config.services.udev.extraRules;
  exactPermissions = "create,mount,destroy,snapshot,rollback,volsize,volblocksize,compression,snapdev,volmode,userprop";
  failedMessages =
    evaluated:
    map (assertion: assertion.message) (
      builtins.filter (assertion: !assertion.assertion) evaluated.config.assertions
    );
  expectFailure = message: extra: builtins.elem message (failedMessages (evaluate extra));
  backend =
    builtins.fromJSON
      defaults.config.environment.etc."keystone/virtual-machine-backend.json".text;
  overriddenBackend =
    builtins.fromJSON
      overridden.config.environment.etc."keystone/virtual-machine-backend.json".text;
  udevLines = lib.splitString "\n" udev;
in
assert defaults.config.keystone.os.hypervisor.zvolStorage.enable;
assert defaults.config.keystone.os.hypervisor.zvolStorage.quota == "500G";
assert defaults.config.keystone.os.hypervisor.zvolStorage.volblocksize == "16K";
assert datasets."rpool/crypt/vms".class == "ephemeral";
assert datasets."rpool/crypt/vms".properties.quota == "500G";
assert datasets."rpool/crypt/vms/users/alice".mountpoint == "none";
assert datasets."rpool/crypt/vms/users/bob".properties.canmount == "off";
assert builtins.hasAttr "rpool/crypt/vms/users/alice" datasets;
assert builtins.hasAttr "rpool/crypt/vms/users/bob" datasets;
assert lib.hasInfix exactPermissions delegation;
assert
  !(
    lib.hasInfix "send" delegation || lib.hasInfix "receive" delegation || lib.hasInfix "key" delegation
  );
assert lib.hasInfix "rpool/crypt/vms/users/alice/*" udev;
assert lib.hasInfix ''OWNER="alice", MODE="0600"'' udev;
assert builtins.length (builtins.filter (line: lib.hasInfix ''OWNER="alice"'' line) udevLines) == 1;
assert builtins.length (builtins.filter (line: lib.hasInfix ''OWNER="bob"'' line) udevLines) == 1;
assert !(lib.hasInfix ''OWNER="alice"'' (builtins.elemAt udevLines 1));
assert !(lib.hasInfix "rpool/credstore" udev);
assert
  overridden.config.keystone.os.storage.zfs.datasets."rpool/crypt/scratch-vms".properties.quota
  == "42G";
assert
  backend == {
    backend = "zvol";
    dataset = "rpool/crypt/vms";
    quota = "500G";
    volblocksize = "16K";
  };
assert overriddenBackend.dataset == "rpool/crypt/scratch-vms";
assert overriddenBackend.quota == "42G";
assert overriddenBackend.volblocksize == "8K";
assert expectFailure "keystone.os.hypervisor.zvolStorage requires ZFS storage." {
  keystone.os.storage.type = lib.mkForce "lvm";
  keystone.os.hypervisor.zvolStorage.enable = true;
};
assert expectFailure
  "keystone.os.hypervisor.zvolStorage.dataset MUST be a native-encrypted child of rpool/crypt."
  {
    keystone.os.hypervisor.zvolStorage.dataset = "rpool/vms";
  };
assert expectFailure "keystone.os.hypervisor.zvolStorage requires the local qemu:///session URI." {
  keystone.os.hypervisor.defaultUri = "qemu:///system";
  keystone.os.hypervisor.zvolStorage.enable = true;
};
assert expectFailure "keystone.os.hypervisor.zvolStorage requires the local hypervisor client." {
  keystone.os.hypervisor.client.enable = lib.mkForce false;
  keystone.os.hypervisor.zvolStorage.enable = true;
};
pkgs.runCommand "zvol-storage-evaluation" { } ''
  touch "$out"
''
