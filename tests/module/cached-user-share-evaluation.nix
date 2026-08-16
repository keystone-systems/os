{
  pkgs,
  lib,
  self,
}:
let
  nixosSystem = import "${pkgs.path}/nixos/lib/eval-config.nix";

  topology = {
    keystone.hosts = {
      server = {
        hostname = "workstation";
        role = "client";
        tailscaleIP = "100.64.0.10";
      };
      client = {
        hostname = "laptop";
        role = "client";
        tailscaleIP = "100.64.0.20";
      };
    };

    keystone.services.cachedUserShare = {
      enable = true;
      serverHost = "workstation";
      clientHost = "laptop";
      exportPath = "/srv/user-share";
      owner = {
        uid = 1000;
        gid = 100;
      };
      client = {
        mountPoint = "/mnt/user-share";
      };
    };
  };

  observedClient = lib.recursiveUpdate topology {
    services.prometheus.exporters.node = {
      enable = true;
      enabledCollectors = [ "textfile" ];
      extraFlags = [
        "--collector.textfile.directory=/var/lib/prometheus-node-exporter"
      ];
    };
  };

  evaluate =
    hostname: module:
    nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.operating-system
        {
          system.stateVersion = "25.05";
          networking.hostName = hostname;
        }
        module
      ];
    };

  server = evaluate "workstation" topology;
  client = evaluate "laptop" observedClient;
  clientWithoutObservability = evaluate "laptop" topology;
  clientWithoutTextfileDirectory = evaluate "laptop" (
    lib.recursiveUpdate topology {
      services.prometheus.exporters.node = {
        enable = true;
        enabledCollectors = [ "textfile" ];
      };
    }
  );
  clientWithWrongTextfileDirectory = evaluate "laptop" (
    lib.recursiveUpdate topology {
      services.prometheus.exporters.node = {
        enable = true;
        enabledCollectors = [ "textfile" ];
        extraFlags = [
          "--collector.textfile.directory=/var/lib/wrong-directory"
        ];
      };
    }
  );

  failingMessages =
    evaluation:
    map (assertion: assertion.message) (
      builtins.filter (assertion: !assertion.assertion) evaluation.config.assertions
    );
  hasFailure = needle: evaluation: builtins.any (lib.hasInfix needle) (failingMessages evaluation);

  unsafePaths = [
    "/"
    "//"
    "/."
    "/.."
    "/srv/./share"
    "/srv/../share"
    "/srv//share"
    "/srv/share with space"
    "/srv/share\twith-tab"
    "/srv/share\nwith-newline"
    "/srv/share#comment"
    "/srv/share(options)"
    "/srv/share\\escape"
    "/srv/share*glob"
    "/srv/share?glob"
    "/srv/share,comma"
    "/srv/share:colon"
  ];
  invalidExport =
    path:
    evaluate "workstation" (
      lib.recursiveUpdate topology {
        keystone.services.cachedUserShare.exportPath = path;
      }
    );
  invalidMount =
    path:
    evaluate "laptop" (
      lib.recursiveUpdate topology {
        keystone.services.cachedUserShare.client.mountPoint = path;
      }
    );
  invalidCache =
    path:
    evaluate "laptop" (
      lib.recursiveUpdate topology {
        keystone.services.cachedUserShare.client.cache.directory = path;
      }
    );
  invalidServerHost = evaluate "workstation" (
    lib.recursiveUpdate topology {
      keystone.services.cachedUserShare.serverHost = "missing";
    }
  );
  missingServerIP = evaluate "workstation" (
    lib.recursiveUpdate topology {
      keystone.hosts.server.tailscaleIP = null;
    }
  );
  serverExport = server.config.services.nfs.server.exports;
  serverReady = server.config.systemd.services.cached-user-share-tailnet-ready;
  clientReady = client.config.systemd.services.cached-user-share-tailnet-ready;
  clientMount = builtins.head client.config.systemd.mounts;
  clientAutomount = builtins.head client.config.systemd.automounts;
  serverReadyScript = builtins.readFile serverReady.serviceConfig.ExecStart;
  clientReadyScript = builtins.readFile clientReady.serviceConfig.ExecStart;
  metricsService = client.config.systemd.services.cached-user-share-metrics;
  metricsScript = builtins.readFile metricsService.serviceConfig.ExecStart;

  expectedCacheConfig = lib.concatStringsSep "\n" [
    "brun 30%"
    "bcull 25%"
    "bstop 20%"
    "frun 30%"
    "fcull 25%"
    "fstop 20%"
  ];
in
assert server.config.services.nfs.server.enable;
assert server.config.services.nfs.server.hostName == "100.64.0.10";
assert
  serverExport
  == "/srv/user-share 100.64.0.20(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=100,fsid=0)";
assert
  server.config.services.nfs.settings.nfsd == {
    tcp = true;
    udp = false;
    vers3 = false;
    vers4 = true;
    "vers4.0" = false;
    "vers4.1" = true;
    "vers4.2" = true;
  };
assert server.config.networking.firewall.interfaces.tailscale0.allowedTCPPorts == [ 2049 ];
assert serverReady.after == [ "tailscaled.service" ];
assert serverReady.requires == [ "tailscaled.service" ];
assert serverReady.serviceConfig.Restart == "on-failure";
assert serverReady.serviceConfig.RestartSec == "5s";
assert serverReady.serviceConfig.RemainAfterExit;
assert lib.hasSuffix "/bin/systemctl --no-block start nfs-server.service"
  serverReady.serviceConfig.ExecStartPost;
assert lib.hasInfix "tailscale wait --timeout=2m" serverReadyScript;
assert lib.hasInfix "tailscale ip --assert=100.64.0.10" serverReadyScript;
assert
  server.config.systemd.services.tailscaled.wants == [
    "cached-user-share-tailnet-ready.service"
  ];
assert lib.elem "cached-user-share-tailnet-ready.service"
  server.config.systemd.services.nfs-server.after;
assert lib.elem "cached-user-share-tailnet-ready.service"
  server.config.systemd.services.nfs-server.requires;
assert client.config.services.cachefilesd.enable;
assert client.config.services.cachefilesd.extraConfig == expectedCacheConfig;
assert
  client.config.services.prometheus.exporters.node.extraFlags == [
    "--collector.textfile.directory=/var/lib/prometheus-node-exporter"
  ];
assert clientReady.after == [ "tailscaled.service" ];
assert clientReady.requires == [ "tailscaled.service" ];
assert clientReady.serviceConfig.RemainAfterExit;
assert !lib.hasInfix "--timeout" clientReadyScript;
assert lib.hasInfix "tailscale ip --assert=100.64.0.20" clientReadyScript;
assert clientMount.what == "100.64.0.10:/";
assert clientMount.type == "nfs";
assert clientMount.options == "vers=4.2,proto=tcp,hard,fsc,nofail,_netdev";
assert clientMount.after == [ "cached-user-share-tailnet-ready.service" ];
assert clientMount.requires == [ "cached-user-share-tailnet-ready.service" ];
assert clientAutomount.automountConfig.TimeoutIdleSec == "10min";
assert clientAutomount.after == [ ];
assert clientAutomount.requires == [ ];
assert builtins.all (
  path: hasFailure "exportPath must be an absolute non-root path" (invalidExport path)
) unsafePaths;
assert builtins.all (
  path: hasFailure "mountPoint must be an absolute non-root path" (invalidMount path)
) unsafePaths;
assert builtins.all (
  path: hasFailure "cache.directory must be an absolute non-root path" (invalidCache path)
) unsafePaths;
assert metricsService.after == [ "cachefilesd.service" ];
assert lib.hasInfix "/proc/fs/fscache/stats" metricsScript;
assert lib.hasInfix "[[:space:]]*:" metricsScript;
assert lib.hasInfix "chmod 0644" metricsScript;
assert lib.hasInfix "keystone_cached_user_share_cache_filesystem_free_bytes" metricsScript;
assert hasFailure "node exporter textfile collector" clientWithoutObservability;
assert hasFailure "must read textfile metrics from" clientWithoutTextfileDirectory;
assert hasFailure "must read textfile metrics from" clientWithWrongTextfileDirectory;
assert hasFailure "serverHost" invalidServerHost;
assert hasFailure "literal IPv4 tailscaleIP" missingServerIP;
pkgs.runCommand "cached-user-share-evaluation" { } ''
  touch "$out"
''
