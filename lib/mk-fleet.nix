# mkFleet: turn a hosts/ directory into flake outputs plus a unified
# vm/machine test harness.
#
# Every host is a plain NixOS module directory under hostsDir (the directory
# name is the hostname). The harness knows two *realizations* of a host:
#
#   vm      — QEMU vmVariant. Fresh-install semantics: what boots here is
#             what a real install produces. ssh is forwarded from
#             basePort + index; the graphical console is served by QEMU's
#             built-in VNC server on display vncDisplayBase + index
#             (unauthenticated — reach it over a tailnet or ssh tunnel).
#   machine — a physical deployment target (a test box like ks-test-delltop)
#             reached over ssh and driven with nixos-rebuild.
#
# `targets.<host>` declares the machine endpoint, the preferred default
# realization, and per-host vm sizing. `fleetMeta` exports the entire
# realization table as plain data; the ks-fleet runner consumes it to deploy
# and smoke-test a *mixed* fleet — some hosts as VMs, some as baremetal —
# in one invocation.
#
# devModules.<host> (a list of modules merged into that host's vmVariant)
# yields an additional `vm-dev-<host>` app carrying deliberate impurities
# (live 9p config mounts, auto-login) for fast iteration; dev variants
# never feed the fleet app or the primary vm packages.
{ nixpkgs }:
{
  # Directory whose subdirectories are host declarations.
  hostsDir,
  # Optional shared fleet configuration file (an attrset); only meaningful
  # once the keystone module set (providing `keystone.fleet`) is imported
  # via baseModules.
  fleetFile ? null,
  # Modules applied to every host before its own directory (module sets,
  # e.g. the keystone defaults).
  baseModules ? [ ],
  # Extra modules applied to every host after its own directory.
  extraModules ? [ ],
  # Per-host extra vmVariant modules for the -dev vm apps.
  devModules ? { },
  # Per-host realization declarations:
  #   targets.<host> = {
  #     machine = {
  #       sshTarget = "192.168.1.64";   # DNS name or address
  #       user = "root";                # ssh/deploy user
  #       hostPublicKey = "ssh-ed25519 ..."; # pinned machine identity
  #       buildOnRemote = false;        # nixos-rebuild --build-host target
  #     };
  #     default = "machine";            # preferred realization for fleet
  #                                     # runs; defaults to "machine" when a
  #                                     # machine target exists, else "vm"
  #     vm = { memorySize = 8192; cores = 4; };   # sizing overrides,
  #                                               # or `false` to disable
  #   };
  targets ? { },
  system ? "x86_64-linux",
  basePort ? 2200,
  vncDisplayBase ? 0,
}:
let
  lib = nixpkgs.lib;
  pkgs = nixpkgs.legacyPackages.${system};

  # attrNames is sorted, so port and display assignment is stable.
  hostNames = builtins.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir hostsDir)
  );
  indexed = lib.imap0 (i: name: { inherit i name; }) hostNames;

  target = name: targets.${name} or { };
  installOpts = name: (target name).install or null;
  vmEnabled = name: (target name).vm or { } != false;
  vmOpts = name: if vmEnabled name then (target name).vm or { } else { };
  defaultRealization =
    name: (target name).default or (if (target name) ? machine then "machine" else "vm");

  # Hosts with an install target get an emulated TPM2 (swtpm via
  # virtualisation.tpm) and optionally a canokey virtual FIDO2 token in the
  # disko test VM, so LUKS enrollment/unlock flows are testable pre-hardware.
  installModule =
    name:
    let
      io = installOpts name;
      tpmAndFido = {
        virtualisation.tpm.enable = io.tpm or true;
        virtualisation.qemu = lib.optionalAttrs (io.fido2 or false) {
          # Canokey needs a QEMU built with canokeySupport. The fleet runs on
          # x86_64, so avoid compiling emulators for unrelated architectures.
          package = pkgs.qemu_kvm.override { canokeySupport = true; };
          options = [ "-device canokey,file=/tmp/canokey-state" ];
        };
      };
    in
    lib.optionals (io != null) [
      ../modules/disko-vm-tools-compat.nix
      {
        # Disko imports tests.extraConfig into both its interactive install VM
        # and test machine. Declare the emulated TPM/Canokey module once.
        disko.tests.extraConfig = tpmAndFido;
      }
    ];

  mkHost =
    name:
    lib.nixosSystem {
      inherit system;
      modules =
        baseModules
        ++ [
          (hostsDir + "/${name}")
          { networking.hostName = lib.mkDefault name; }
        ]
        ++ lib.optional (fleetFile != null) { keystone.fleet = import fleetFile; }
        ++ installModule name
        ++ extraModules;
    };

  nixosConfigurations = lib.genAttrs hostNames mkHost;

  vncDisplay = i: vncDisplayBase + i;
  vncPort = i: 5900 + vncDisplay i;

  vmFor =
    i: name: extraVmModules:
    (nixosConfigurations.${name}.extendModules {
      modules = [
        {
          virtualisation.vmVariant = {
            imports = extraVmModules;
            virtualisation = {
              memorySize = (vmOpts name).memorySize or 4096;
              cores = (vmOpts name).cores or 2;
              graphics = true;
              qemu.options = [ "-vnc :${toString (vncDisplay i)}" ];
              forwardPorts = [
                {
                  from = "host";
                  host.port = basePort + i;
                  guest.port = 22;
                }
              ];
            };
          };
        }
      ];
    }).config.system.build.vm;

  vmHosts = builtins.filter ({ name, ... }: vmEnabled name) indexed;

  installPackages = lib.listToAttrs (
    map (
      { name, ... }:
      {
        name = "install-${name}";
        value = nixosConfigurations.${name}.config.system.build.vmWithDisko;
      }
    ) (builtins.filter ({ name, ... }: installOpts name != null) indexed)
  );

  vmPackages = lib.listToAttrs (
    map (
      { i, name }:
      {
        name = "vm-${name}";
        value = vmFor i name [ ];
      }
    ) vmHosts
  );

  mkVmApp = i: name: extraVmModules: suffix: {
    type = "app";
    program = toString (
      pkgs.writeShellScript "run-${name}${suffix}-vm" ''
        echo "${name}${suffix}: ssh -p ${toString (basePort + i)} localhost | vnc display :${toString (vncDisplay i)} (port ${toString (vncPort i)})"
        exec ${vmFor i name extraVmModules}/bin/run-${name}-vm "$@"
      ''
    );
  };

  vmApps = lib.listToAttrs (
    map (
      { i, name }:
      {
        name = "vm-${name}";
        value = mkVmApp i name [ ] "";
      }
    ) vmHosts
  );

  devVmApps = lib.listToAttrs (
    map (
      { i, name }:
      {
        name = "vm-dev-${name}";
        value = mkVmApp i name devModules.${name} "-dev";
      }
    ) (builtins.filter ({ name, ... }: devModules ? ${name} && vmEnabled name) indexed)
  );

  # `nix run .#fleet` boots the hosts whose *default* realization is vm —
  # hosts standing in for live baremetal are left to their machines. Use
  # ks-fleet (or `--as vm`) for mixed and forced runs.
  fleetVmHosts = builtins.filter ({ name, ... }: defaultRealization name == "vm") vmHosts;

  fleetScript = pkgs.writeShellScript "run-fleet" ''
    set -euo pipefail
    dir="''${KS_FLEET_DIR:-$PWD/.fleet}"
    mkdir -p "$dir"
    cd "$dir"
    pids=()
    ${lib.concatMapStrings (
      { i, name }:
      ''
        echo "starting ${name} (ssh -p ${toString (basePort + i)} localhost | vnc port ${toString (vncPort i)})"
        ${vmFor i name [ ]}/bin/run-${name}-vm >"${name}.log" 2>&1 &
        pids+=($!)
      ''
    ) fleetVmHosts}
    echo "fleet of ${toString (builtins.length fleetVmHosts)} VM(s) running; disks and logs in $dir"
    echo "Ctrl-C stops the fleet"
    trap 'kill ''${pids[@]} 2>/dev/null || true' INT TERM
    wait
  '';

  fleetMeta = {
    inherit system basePort;
    hosts = lib.listToAttrs (
      map (
        { i, name }:
        {
          inherit name;
          value = {
            default = defaultRealization name;
            vm =
              if vmEnabled name then
                {
                  sshPort = basePort + i;
                  vncDisplay = vncDisplay i;
                  vncPort = vncPort i;
                }
              else
                null;
            install =
              let
                io = installOpts name;
              in
              if io == null then
                null
              else
                {
                  tpm = io.tpm or true;
                  fido2 = io.fido2 or false;
                };
            machine =
              if (target name) ? machine then
                {
                  sshTarget = (target name).machine.sshTarget;
                  user = (target name).machine.user or "root";
                  hostPublicKey = (target name).machine.hostPublicKey or null;
                  buildOnRemote = (target name).machine.buildOnRemote or false;
                }
              else
                null;
          };
        }
      ) indexed
    );
  };
in
{
  inherit nixosConfigurations fleetMeta;
  packages.${system} = vmPackages // installPackages;
  apps.${system} =
    vmApps
    // devVmApps
    // {
      fleet = {
        type = "app";
        program = toString fleetScript;
      };
    };
}
