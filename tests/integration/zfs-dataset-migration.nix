{
  pkgs,
  self,
}:
pkgs.testers.nixosTest {
  name = "zfs-dataset-migration";

  nodes.machine =
    { lib, pkgs, ... }:
    {
      imports = [ self.nixosModules.operating-system ];
      nixpkgs.overlays = [ self.overlays.default ];
      virtualisation.emptyDiskImages = [ 256 ];
      boot.supportedFilesystems = [ "zfs" ];
      networking.hostId = "12345678";
      system.stateVersion = "25.05";

      keystone.os = {
        enable = true;
        secureBoot.enable = false;
        tpm.enable = false;
        tailscale.enable = false;
        storage = {
          enable = false;
          type = "zfs";
        };
        services.ollama = {
          enable = true;
          acceleration = null;
          zfsDataset = {
            enable = true;
            refquota = "32M";
          };
        };
      };

      # Avoid starting the real server; this test only needs its dependency edge.
      services.ollama.package = lib.mkForce (
        pkgs.writeShellScriptBin "ollama" "exec ${pkgs.coreutils}/bin/sleep infinity"
      );
      systemd.services.ollama.serviceConfig.ExecStart =
        lib.mkForce "${pkgs.coreutils}/bin/sleep infinity";
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")

    # The declared parent is intentionally absent on first boot.
    machine.succeed("zpool create -f rpool /dev/vdb")
    machine.fail("systemctl restart keystone-zfs-datasets.service")
    machine.fail("zfs list rpool/crypt/system/var/lib/ollama")
    machine.fail("systemctl is-active --quiet ollama.service")

    machine.succeed("zfs create -p rpool/crypt/system/var/lib")
    machine.succeed("mkdir -p /var/lib/private/ollama/sub")
    machine.succeed("printf model > /var/lib/private/ollama/sub/model")
    machine.succeed("ln /var/lib/private/ollama/sub/model /var/lib/private/ollama/sub/hardlink")
    machine.succeed("ln -s model /var/lib/private/ollama/sub/symlink")
    machine.succeed("chown 123:456 /var/lib/private/ollama/sub/model")
    machine.succeed("chmod 0640 /var/lib/private/ollama/sub/model")
    machine.succeed("${pkgs.attr}/bin/setfattr -n user.keystone -v preserved /var/lib/private/ollama/sub/model")

    machine.succeed("systemctl restart keystone-zfs-datasets.service")
    machine.succeed("zfs list rpool/crypt/system/var/lib/ollama")
    machine.succeed("findmnt -n -o SOURCE /var/lib/private/ollama | grep -Fx rpool/crypt/system/var/lib/ollama")
    machine.succeed("zfs get -H -o value recordsize rpool/crypt/system/var/lib/ollama | grep -Fx 1M")
    machine.succeed("zfs get -H -o value refquota rpool/crypt/system/var/lib/ollama | grep -Fx 32M")
    machine.succeed("zfs get -H -o value com.sun:auto-snapshot rpool/crypt/system/var/lib/ollama | grep -Fx false")
    machine.succeed("test $(stat -c %u /var/lib/private/ollama/sub/model) = 123")
    machine.succeed("test $(stat -c %g /var/lib/private/ollama/sub/model) = 456")
    machine.succeed("test $(stat -c %a /var/lib/private/ollama/sub/model) = 640")
    machine.succeed("test $(stat -c %i /var/lib/private/ollama/sub/model) = $(stat -c %i /var/lib/private/ollama/sub/hardlink)")
    machine.succeed("${pkgs.attr}/bin/getfattr --only-values -n user.keystone /var/lib/private/ollama/sub/model | grep -Fx preserved")
    machine.succeed("test $(readlink /var/lib/private/ollama/sub/symlink) = model")
    machine.succeed("test ! -e /var/lib/private/ollama.keystone-migration")
    # The reconciler must not leave systemd's DynamicUser state root listable.
    machine.succeed("test $(stat -c %a /var/lib/private) = 700")
    machine.succeed("systemctl restart keystone-zfs-datasets.service")

    # Resume an interrupted partial copy and verification.
    machine.succeed("mkdir /var/lib/private/ollama.keystone-migration")
    machine.succeed("printf resume > /var/lib/private/ollama.keystone-migration/resume")
    machine.succeed("printf partial > /var/lib/private/ollama/resume")
    machine.succeed("systemctl restart keystone-zfs-datasets.service")
    machine.succeed("grep -Fx resume /var/lib/private/ollama/resume")
    machine.succeed("test ! -e /var/lib/private/ollama.keystone-migration")

    # Resume cleanup after verification completed.
    machine.succeed("mkdir /var/lib/private/ollama.keystone-migration")
    machine.succeed("printf recoverable > /var/lib/private/ollama.keystone-migration/recoverable")
    machine.succeed("touch /var/lib/private/ollama.keystone-migration.verified")
    machine.succeed("systemctl restart keystone-zfs-datasets.service")
    machine.succeed("test ! -e /var/lib/private/ollama.keystone-migration")
    machine.succeed("test ! -e /var/lib/private/ollama.keystone-migration.verified")

    # Refuse an ambiguous pre-creation state without deleting either copy.
    machine.succeed("zfs unmount rpool/crypt/system/var/lib/ollama")
    machine.succeed("zfs destroy rpool/crypt/system/var/lib/ollama")
    machine.succeed("mkdir -p /var/lib/private/ollama /var/lib/private/ollama.keystone-migration")
    machine.succeed("printf source > /var/lib/private/ollama/source")
    machine.succeed("printf staged > /var/lib/private/ollama.keystone-migration/staged")
    machine.fail("systemctl restart keystone-zfs-datasets.service")
    machine.succeed("test -f /var/lib/private/ollama/source")
    machine.succeed("test -f /var/lib/private/ollama.keystone-migration/staged")

    # Insufficient capacity leaves the sole staged copy intact.
    machine.succeed("rm /var/lib/private/ollama/source")
    machine.succeed("dd if=/dev/urandom of=/var/lib/private/ollama.keystone-migration/large bs=1M count=40")
    machine.fail("systemctl restart keystone-zfs-datasets.service")
    machine.succeed("test -f /var/lib/private/ollama.keystone-migration/large")
    machine.succeed("systemctl is-failed keystone-zfs-datasets.service")
    machine.fail("systemctl is-active --quiet ollama.service")
  '';
}
