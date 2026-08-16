{
  pkgs,
  lib,
  self,
  ...
}:
let
  fakeTailscale = pkgs.writeShellApplication {
    name = "tailscale";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      case "''${1-}" in
        wait)
          printf 'wait\n' >> /run/test-tailnet-waits
          while ! test -e /run/test-tailnet-ready; do
            sleep 0.1
          done
          ;;
        ip)
          expected="''${2#--assert=}"
          if ! test "$expected" = "$(cat /run/test-tailnet-ip)"; then
            touch /run/test-tailnet-first-failure
            exit 1
          fi
          ;;
        *)
          exit 2
          ;;
      esac
    '';
  };

  topology = {
    keystone.hosts = {
      server = {
        hostname = "workstation";
        role = "client";
        tailscaleIP = "192.168.1.3";
        baremetal = false;
      };
      client = {
        hostname = "laptop";
        role = "client";
        tailscaleIP = "192.168.1.1";
        baremetal = false;
      };
    };

    keystone.services.cachedUserShare = {
      enable = true;
      serverHost = "workstation";
      clientHost = "laptop";
      exportPath = "/srv/user-share";
      owner = {
        uid = 1234;
        gid = 1234;
      };
      client = {
        mountPoint = "/mnt/user-share";
      };
    };

    services.tailscale.package = fakeTailscale;
    systemd.services.tailscaled = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = lib.mkForce "oneshot";
        RemainAfterExit = lib.mkForce true;
        ExecStart = lib.mkForce "${pkgs.coreutils}/bin/true";
      };
    };
  };
in
pkgs.testers.nixosTest {
  name = "cached-user-share";

  nodes = {
    server = {
      imports = [
        self.nixosModules.operating-system
        topology
      ];
      system.stateVersion = "25.05";
      networking = {
        hostName = "workstation";
        firewall.enable = false;
      };

      users.groups.share-owner.gid = 1234;
      users.users.share-owner = {
        isSystemUser = true;
        uid = 1234;
        group = "share-owner";
      };

      systemd.tmpfiles.rules = [
        "d /srv/user-share 0750 share-owner share-owner -"
        "f /srv/user-share/from-server 0640 share-owner share-owner - server-data"
      ];
    };

    client = {
      imports = [
        self.nixosModules.operating-system
        topology
      ];
      system.stateVersion = "25.05";
      networking = {
        hostName = "laptop";
        firewall.enable = false;
      };
      services.prometheus.exporters.node = {
        enable = true;
        enabledCollectors = [ "textfile" ];
        extraFlags = [
          "--collector.textfile.directory=/var/lib/prometheus-node-exporter"
        ];
      };
    };

    other = {
      system.stateVersion = "25.05";
      networking.firewall.enable = false;
      environment.systemPackages = [ pkgs.nfs-utils ];
    };
  };

  testScript = ''
    start_all()

    server.wait_for_unit("tailscaled.service")
    client.wait_for_unit("tailscaled.service")
    client.wait_for_unit("mnt-user\\x2dshare.automount")
    client.wait_for_unit("cachefilesd.service")

    with subtest("the automount starts without tailnet readiness"):
        client.fail("systemctl is-active --quiet cached-user-share-tailnet-ready.service")
        client.fail("systemctl is-active --quiet mnt-user\\x2dshare.mount")

    with subtest("the server recovers after its first readiness failure"):
        server.succeed("printf 192.168.1.99 > /run/test-tailnet-ip")
        server.succeed("touch /run/test-tailnet-ready")
        server.succeed(
            "systemctl start cached-user-share-tailnet-ready.service "
            ">/tmp/tailnet-ready-start.log 2>&1 &"
        )
        server.wait_until_succeeds("test -e /run/test-tailnet-first-failure")
        server.fail("systemctl is-active --quiet nfs-server.service")
        server.succeed("printf 192.168.1.3 > /run/test-tailnet-ip")
        server.wait_until_succeeds(
            "test \"$(systemctl show -P Result "
            "cached-user-share-tailnet-ready.service)\" = success"
        )
        server.succeed(
            "test \"$(systemctl show -P NRestarts "
            "cached-user-share-tailnet-ready.service)\" -ge 1"
        )
        server.wait_for_unit("nfs-server.service")
        server.succeed("ss -ltn | grep -q '192.168.1.3:2049'")

    with subtest("tailscaled restart re-arms server readiness and NFS"):
        waits_before = server.succeed("wc -l < /run/test-tailnet-waits").strip()
        server.succeed("systemctl restart tailscaled.service")
        server.wait_until_succeeds(
            f"test $(wc -l < /run/test-tailnet-waits) -gt {waits_before}"
        )
        server.wait_for_unit("cached-user-share-tailnet-ready.service")
        server.wait_for_unit("nfs-server.service")
        server.succeed("ss -ltn | grep -q '192.168.1.3:2049'")

    with subtest("the real mount waits for client tailnet readiness"):
        client.succeed(
            "(cat /mnt/user-share/from-server > /tmp/share-data; "
            "touch /tmp/share-read-complete) >/dev/null 2>&1 &"
        )
        client.wait_until_succeeds(
            "systemctl show -P ActiveState cached-user-share-tailnet-ready.service "
            "| grep -qx activating"
        )
        client.fail("test -e /tmp/share-read-complete")
        client.succeed("printf 192.168.1.1 > /run/test-tailnet-ip")
        client.succeed("touch /run/test-tailnet-ready")
        client.wait_for_unit("cached-user-share-tailnet-ready.service")
        client.wait_until_succeeds("test -e /tmp/share-read-complete")
        client.succeed("test \"$(cat /tmp/share-data)\" = server-data")
        client.wait_for_unit("mnt-user\\x2dshare.mount")

    with subtest("the client uses NFS 4.2 and FS-Cache"):
        client.succeed("findmnt -n -o FSTYPE /mnt/user-share | grep -Eq '^nfs4?$'")
        client.succeed("findmnt -n -o OPTIONS /mnt/user-share | grep -q 'vers=4.2'")
        client.succeed("findmnt -n -o OPTIONS /mnt/user-share | grep -q 'fsc'")

    with subtest("all client identities map to the declared owner"):
        client.succeed("printf mapped > /mnt/user-share/from-client-root")
        server.succeed("test \"$(stat -c '%u:%g' /srv/user-share/from-client-root)\" = 1234:1234")

    with subtest("the export rejects another client address"):
        other.succeed("mkdir -p /mnt")
        other.fail(
            "timeout 10s mount -t nfs "
            "-o vers=4.2,proto=tcp,soft,timeo=5,retrans=1 192.168.1.3:/ /mnt"
        )

    with subtest("the cache uses all six percentage watermarks"):
        client.succeed("grep -d skip -Fx 'bstop 20%' /nix/store/*-cachefilesd.conf")
        client.succeed("grep -d skip -Fx 'bcull 25%' /nix/store/*-cachefilesd.conf")
        client.succeed("grep -d skip -Fx 'brun 30%' /nix/store/*-cachefilesd.conf")
        client.succeed("grep -d skip -Fx 'fstop 20%' /nix/store/*-cachefilesd.conf")
        client.succeed("grep -d skip -Fx 'fcull 25%' /nix/store/*-cachefilesd.conf")
        client.succeed("grep -d skip -Fx 'frun 30%' /nix/store/*-cachefilesd.conf")

    with subtest("the textfile collector receives cache metrics"):
        client.wait_for_unit("prometheus-node-exporter.service")
        client.succeed("systemctl start cached-user-share-metrics.service")
        client.succeed(
            "test $(stat -c %a /var/lib/prometheus-node-exporter/cached_user_share.prom) = 644"
        )
        client.succeed(
            "${lib.getExe pkgs.curl} -fsS http://127.0.0.1:9100/metrics "
            "> /tmp/node-exporter-metrics"
        )
        client.succeed(
            "grep -Eq '^keystone_cached_user_share_cache_filesystem_free_bytes [-+0-9.eE]+$' "
            "/tmp/node-exporter-metrics"
        )
        client.succeed(
            "grep -Eq '^keystone_fscache_io_(rd|wr) [-+0-9.eE]+$' "
            "/tmp/node-exporter-metrics"
        )
  '';
}
