# template-special-args — verify fleet/host composition of `shared.specialArgs`
# and per-host `hosts.<name>.specialArgs` through `mkSystemFlake`.
#
# Covers three scenarios:
#
#   1. `shared.specialArgs = { injected = "fleet-value"; }` propagates to every
#      Linux host's nixosSystem call, where the probe module reads `injected`
#      both as a module function arg and inside its `imports = [ ... ]` list.
#   2. A per-host `specialArgs = { injected = "host-value"; }` overrides the
#      fleet default for that host only, leaving siblings on the fleet value
#      (shallow last-write-wins merge: `sharedSpecialArgs // hostCfg.specialArgs`).
#   3. With neither `shared.specialArgs` nor a per-host override, the fleet
#      still evaluates without crashing.
#
# The whole point of `specialArgs` over `_module.args` is that values are
# available at *module-import time*, not just *config-eval time*. So the probe
# module references `injected` inside its `imports = [ ... ]` list. If a future
# refactor regresses `lib/templates.nix` to use `_module.args` (or drops the
# `inherit system specialArgs;` line), this test fails with "infinite recursion"
# or "missing argument 'injected'", not a silent false positive.
{
  pkgs,
  lib ? pkgs.lib,
  self,
}:
let
  mkFleet =
    { shared, hosts }:
    self.lib.mkSystemFlake {
      admin = {
        username = "admin";
        fullName = "Fleet Owner";
        email = "fleet@example.com";
        initialPassword = "changeme";
      };
      defaults = {
        timeZone = "UTC";
      };
      inherit shared hosts;
    };

  # Probe module that requires `injected` to be a specialArg, not a
  # _module.args value. The `imports = lib.optionals (injected != null) [ ]`
  # line forces module-import-time evaluation of `injected`; with
  # `_module.args` plumbing this triggers infinite recursion because
  # `_module.args` resolution itself depends on `config`, which depends on
  # imports being resolved.
  probeModule =
    { injected, lib, ... }:
    {
      imports = lib.optionals (injected != null) [ ];
      config.environment.etc."ks-special-arg-probe".text = injected;
    };

  probeOf = system: system.config.environment.etc."ks-special-arg-probe".text;

  # Minimal host configs that are accepted by mkLaptop / mkServer without a
  # hardware.nix file. networking.hostId satisfies the ZFS server check.
  minimalLaptop =
    extra:
    {
      kind = "laptop";
      hardware = null;
      configuration = null;
      storage.devices = [ "/dev/disk/by-id/nvme-laptop-root-001" ];
      modules = [
        { networking.hostId = "11111111"; }
        probeModule
      ];
    }
    // extra;

  minimalServer =
    extra:
    {
      kind = "server";
      hardware = null;
      configuration = null;
      storage.devices = [ "/dev/disk/by-id/nvme-server-root-001" ];
      modules = [
        { networking.hostId = "22222222"; }
        probeModule
      ];
    }
    // extra;

  # Variant for scenario 3 — no probeModule, since neither shared nor host
  # provides `injected`. Used only to confirm a fleet without specialArgs
  # still evaluates.
  bareLaptop = {
    kind = "laptop";
    hardware = null;
    configuration = null;
    storage.devices = [ "/dev/disk/by-id/nvme-laptop-root-001" ];
    modules = [
      { networking.hostId = "11111111"; }
    ];
  };

  # Scenario 1: shared specialArgs propagates to every host.
  fleetShared = mkFleet {
    shared = {
      specialArgs = {
        injected = "fleet-value";
      };
    };
    hosts = {
      laptop = minimalLaptop { };
      server = minimalServer { };
    };
  };

  # Scenario 2: per-host specialArgs overrides shared for that host only.
  fleetMixed = mkFleet {
    shared = {
      specialArgs = {
        injected = "fleet-value";
      };
    };
    hosts = {
      laptop = minimalLaptop { };
      server = minimalServer {
        specialArgs = {
          injected = "host-value";
        };
      };
    };
  };

  # Scenario 3: no specialArgs anywhere — fleet still evaluates.
  fleetBare = mkFleet {
    shared = { };
    hosts = {
      laptop = bareLaptop;
    };
  };

  expect =
    label: actual: expected:
    if actual == expected then
      "ok: ${label} = ${actual}"
    else
      throw "FAIL: ${label} expected '${expected}', got '${actual}'";

  # Forcing evaluation of a NixOS configuration's drvPath proves the module
  # tree resolves end-to-end without infinite recursion.
  evalsOk =
    label: system:
    let
      _ = system.config.system.build.toplevel.drvPath;
    in
    "ok: ${label} evaluated";

  assertions = [
    # Scenario 1 — shared propagates to every host's probe module.
    (expect "fleetShared.laptop.probe" (probeOf fleetShared.nixosConfigurations.laptop) "fleet-value")
    (expect "fleetShared.server.probe" (probeOf fleetShared.nixosConfigurations.server) "fleet-value")

    # Scenario 2 — per-host override wins for that host only.
    (expect "fleetMixed.laptop.probe" (probeOf fleetMixed.nixosConfigurations.laptop) "fleet-value")
    (expect "fleetMixed.server.probe" (probeOf fleetMixed.nixosConfigurations.server) "host-value")

    # Scenario 3 — fleet without specialArgs still evaluates.
    (evalsOk "fleetBare.laptop" fleetBare.nixosConfigurations.laptop)
  ];
in
pkgs.runCommand "test-template-special-args" { } ''
  mkdir -p "$out"
  cat > "$out/report.txt" <<'REPORT'
  ${lib.concatStringsSep "\n" assertions}
  REPORT
''
