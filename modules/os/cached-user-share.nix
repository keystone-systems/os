{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatStringsSep
    mkIf
    mkDefault
    ;

  cfg = config.keystone.services.cachedUserShare;
  hosts = builtins.attrValues config.keystone.hosts;
  currentHostname = config.networking.hostName;

  hostByHostname = hostname: lib.findFirst (host: host.hostname == hostname) null hosts;
  server = if cfg.serverHost == null then null else hostByHostname cfg.serverHost;
  client = if cfg.clientHost == null then null else hostByHostname cfg.clientHost;
  serverIP = if server == null then null else server.tailscaleIP;
  clientIP = if client == null then null else client.tailscaleIP;
  serverIPString = if serverIP == null then "" else serverIP;
  clientIPString = if clientIP == null then "" else clientIP;

  isServer = cfg.enable && currentHostname == cfg.serverHost;
  isClient = cfg.enable && currentHostname == cfg.clientHost;
  isShareHost = isServer || isClient;
  expectedIP = if isServer then serverIP else clientIP;
  expectedIPString = if expectedIP == null then "" else expectedIP;
  cache = cfg.client.cache;
  textfileDirectory = config.keystone.os.observability.nodeExporter.textfileDirectory;
  expectedTextfileFlag = "--collector.textfile.directory=${textfileDirectory}";
  textfileCollectorEnabled =
    config.services.prometheus.exporters.node.enable
    && lib.elem "textfile" config.services.prometheus.exporters.node.enabledCollectors;
  textfileDirectoryConfigured = lib.elem expectedTextfileFlag config.services.prometheus.exporters.node.extraFlags;
  metricsEnabled = isClient && textfileCollectorEnabled;

  isLiteralIPv4 =
    address:
    let
      octets =
        if address == null then
          null
        else
          builtins.match "([0-9]+)\\.([0-9]+)\\.([0-9]+)\\.([0-9]+)" address;
    in
    octets != null
    && builtins.all (
      octet:
      let
        value = lib.toInt octet;
      in
      value >= 0 && value <= 255
    ) octets;

  isSafeAbsolutePath =
    path:
    let
      components = lib.tail (lib.splitString "/" path);
    in
    lib.hasPrefix "/" path
    && path != "/"
    && !(lib.hasInfix "//" path)
    && builtins.all (
      component:
      component != ""
      && component != "."
      && component != ".."
      && builtins.match "[A-Za-z0-9._+-]+" component != null
    ) components;

  tailnetReadyScript = pkgs.writeShellScript "cached-user-share-tailnet-ready" ''
    set -eu
    ${lib.getExe config.services.tailscale.package} wait${lib.optionalString isServer " --timeout=2m"}
    ${lib.getExe config.services.tailscale.package} ip --assert=${lib.escapeShellArg expectedIPString}
  '';

  cacheMetricsScript = pkgs.writeShellScript "cached-user-share-metrics" ''
    set -eu

    outfile=${lib.escapeShellArg "${textfileDirectory}/cached_user_share.prom"}
    tmpfile="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg "${textfileDirectory}/.cached_user_share.prom.XXXXXX"})"
    trap '${pkgs.coreutils}/bin/rm -f "$tmpfile"' EXIT

    if [ -r /proc/fs/fscache/stats ]; then
      ${pkgs.gawk}/bin/awk '
        /^[A-Za-z][A-Za-z0-9]*[[:space:]]*:/ {
          section = $1
          sub(/:$/, "", section)
          section = tolower(section)
          for (field = 2; field <= NF; field++) {
            if ($field ~ /^[A-Za-z][A-Za-z0-9_]*=[0-9]+$/) {
              split($field, pair, "=")
              name = tolower(pair[1])
              printf "keystone_fscache_%s_%s %s\n", section, name, pair[2]
            }
          }
        }
      ' /proc/fs/fscache/stats > "$tmpfile"
    else
      : > "$tmpfile"
    fi

    available="$(${pkgs.coreutils}/bin/df --block-size=1 --output=avail -- ${lib.escapeShellArg cache.directory} | ${pkgs.coreutils}/bin/tail -n 1 | ${pkgs.coreutils}/bin/tr -d '[:space:]')"
    case "$available" in
      ""|*[!0-9]*) exit 1 ;;
    esac
    printf 'keystone_cached_user_share_cache_filesystem_free_bytes %s\n' "$available" >> "$tmpfile"

    ${pkgs.coreutils}/bin/chmod 0644 "$tmpfile"
    ${pkgs.coreutils}/bin/mv "$tmpfile" "$outfile"
    trap - EXIT
  '';
in
{
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = server != null;
        message = "keystone.services.cachedUserShare.serverHost must match a host registry entry.";
      }
      {
        assertion = client != null;
        message = "keystone.services.cachedUserShare.clientHost must match a host registry entry.";
      }
      {
        assertion = isLiteralIPv4 serverIP;
        message = "The cached user-share server host must declare a literal IPv4 tailscaleIP.";
      }
      {
        assertion = isLiteralIPv4 clientIP;
        message = "The cached user-share client host must declare a literal IPv4 tailscaleIP.";
      }
      {
        assertion = isSafeAbsolutePath cfg.exportPath;
        message = ''
          keystone.services.cachedUserShare.exportPath must be an absolute non-root path.
          It must use normalized components with only letters, numbers, dot, underscore, plus, or hyphen.
        '';
      }
      {
        assertion = cfg.owner.uid > 0;
        message = "keystone.services.cachedUserShare.owner.uid must be greater than zero.";
      }
      {
        assertion = cfg.owner.gid > 0;
        message = "keystone.services.cachedUserShare.owner.gid must be greater than zero.";
      }
      {
        assertion = isSafeAbsolutePath cfg.client.mountPoint;
        message = ''
          keystone.services.cachedUserShare.client.mountPoint must be an absolute non-root path.
          It must use normalized components with only letters, numbers, dot, underscore, plus, or hyphen.
        '';
      }
      {
        assertion = isSafeAbsolutePath cache.directory;
        message = ''
          keystone.services.cachedUserShare.client.cache.directory must be an absolute non-root path.
          It must use normalized components with only letters, numbers, dot, underscore, plus, or hyphen.
        '';
      }
      {
        assertion = !isClient || textfileCollectorEnabled;
        message = ''
          The cached user-share client must enable the Prometheus node exporter textfile collector.
        '';
      }
      {
        assertion = !isClient || textfileDirectoryConfigured;
        message = ''
          The cached user-share client node exporter must read textfile metrics from ${textfileDirectory}.
          Set services.prometheus.exporters.node.extraFlags to include ${expectedTextfileFlag}.
        '';
      }
      {
        assertion = cache.stopPercent < cache.cullPercent;
        message = "keystone.services.cachedUserShare.client.cache.stopPercent must be less than cullPercent.";
      }
      {
        assertion = cache.cullPercent < cache.runPercent;
        message = "keystone.services.cachedUserShare.client.cache.cullPercent must be less than runPercent.";
      }
    ];

    services.tailscale.enable = mkIf isShareHost (mkDefault true);

    systemd.services.tailscaled.wants = mkIf isServer [ "cached-user-share-tailnet-ready.service" ];

    systemd.services.cached-user-share-tailnet-ready = mkIf isShareHost {
      description = "Wait for the cached user-share tailnet address";
      after = [ "tailscaled.service" ];
      requires = [ "tailscaled.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = tailnetReadyScript;
      }
      // lib.optionalAttrs isServer {
        ExecStartPost = "${pkgs.systemd}/bin/systemctl --no-block start nfs-server.service";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    services.nfs.server = mkIf isServer {
      enable = true;
      hostName = serverIPString;
      createMountPoints = false;
      exports = {
        "${cfg.exportPath}" = {
          "${clientIPString}" = [
            "rw"
            "sync"
            "no_subtree_check"
            "all_squash"
            "anonuid=${toString cfg.owner.uid}"
            "anongid=${toString cfg.owner.gid}"
            "fsid=0"
          ];
        };
      };
    };

    services.nfs.settings.nfsd = mkIf isServer {
      tcp = true;
      udp = false;
      vers3 = false;
      vers4 = true;
      "vers4.0" = false;
      "vers4.1" = true;
      "vers4.2" = true;
    };

    systemd.services.nfs-server = mkIf isServer {
      after = [ "cached-user-share-tailnet-ready.service" ];
      requires = [ "cached-user-share-tailnet-ready.service" ];
    };

    networking.firewall.interfaces.tailscale0.allowedTCPPorts = mkIf isServer [ 2049 ];

    boot.supportedFilesystems = mkIf isClient [ "nfs" ];

    services.cachefilesd = mkIf isClient {
      enable = true;
      cacheDir = cache.directory;
      extraConfig = concatStringsSep "\n" [
        "brun ${toString cache.runPercent}%"
        "bcull ${toString cache.cullPercent}%"
        "bstop ${toString cache.stopPercent}%"
        "frun ${toString cache.runPercent}%"
        "fcull ${toString cache.cullPercent}%"
        "fstop ${toString cache.stopPercent}%"
      ];
    };

    systemd.tmpfiles.rules = lib.mkIf metricsEnabled [ "d ${textfileDirectory} 0755 root root -" ];

    systemd.services.cached-user-share-metrics = lib.mkIf metricsEnabled {
      description = "Export cached user-share FS-Cache metrics";
      after = [ "cachefilesd.service" ];
      requires = [ "cachefilesd.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = cacheMetricsScript;
      };
    };

    systemd.timers.cached-user-share-metrics = lib.mkIf metricsEnabled {
      description = "Update cached user-share FS-Cache metrics";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "1min";
        Unit = "cached-user-share-metrics.service";
      };
    };

    systemd.mounts = mkIf isClient [
      {
        what = "${serverIPString}:/";
        where = cfg.client.mountPoint;
        type = "nfs";
        options = "vers=4.2,proto=tcp,hard,fsc,nofail,_netdev";
        after = [ "cached-user-share-tailnet-ready.service" ];
        requires = [ "cached-user-share-tailnet-ready.service" ];
      }
    ];

    systemd.automounts = mkIf isClient [
      {
        where = cfg.client.mountPoint;
        wantedBy = [ "multi-user.target" ];
        automountConfig.TimeoutIdleSec = "10min";
      }
    ];
  };
}
