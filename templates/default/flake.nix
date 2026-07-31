{
  description = "Your Name Keystone System Configuration"; # TODO: Change to your name

  inputs = {
    # By default this template only pins Keystone and reuses Keystone's pinned
    # `nixpkgs`. If you want the more standard flake pattern instead, add your
    # own top-level `nixpkgs` input and uncomment `keystone.inputs.nixpkgs.follows`
    # below so Keystone follows that shared pin.
    #
    # You can override other Keystone inputs the same way. Common examples:
    # - `llm-agents` for AI CLI/tooling versions:
    #   `keystone.inputs.llm-agents.follows = "llm-agents";`
    # - `browser-previews` for Chrome/browser preview builds used by Keystone's
    #   browser tooling:
    #   `keystone.inputs.browser-previews.follows = "browser-previews";`
    #
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # llm-agents.url = "github:numtide/llm-agents.nix";
    # browser-previews.url = "github:nix-community/browser-previews";
    keystone = {
      url = "github:ncrmro/keystone";
      # inputs.nixpkgs.follows = "nixpkgs";
      # inputs.llm-agents.follows = "llm-agents";
      # inputs.browser-previews.follows = "browser-previews";
    };

    # No separate `agenix` input is needed: Keystone's operating-system module
    # already imports `agenix.nixosModules.default`, so `age.secrets.*` is
    # available on every host out of the box. See Step 8 of
    # docs/keystone/onboarding.md for how to start using it.
  };

  outputs =
    {
      keystone,
      ...
    }:
    keystone.lib.mkSystemFlake {
      admin = {
        username = "keystone"; # TODO: Change to your login username
        fullName = "Your Name"; # TODO: Change to your full name
        email = "admin@example.com"; # TODO: Change to your email
        initialPassword = "changeme";
        sshKeys = [ ]; # TODO: Add SSH public keys for remote access
      };
      defaults = {
        timeZone = "UTC"; # TODO: Set your default timezone
        updateChannel = "stable"; # "stable" | "unstable" — see docs/releasing.md
      };
      hostsRoot = ./hosts;
      shared = {
        # Home Manager user packages — installed per-user on every host.
        # Start here for tools that should follow your login environment.
        userModules = [
          (
            { pkgs, ... }:
            {
              home.packages = with pkgs; [
                # fd
              ];
            }
          )
        ];

        # NixOS system modules — OS-wide on every host. Use only when something
        # truly belongs at the system level (root-owned packages, services,
        # packages needed for other users).
        systemModules = [
          (
            { pkgs, ... }:
            {
              environment.systemPackages = with pkgs; [
                # btop
              ];
            }
          )
        ];

        # Home Manager desktop packages — per-user on laptop and workstation
        # hosts only, not servers. Use for GUI apps.
        # desktopUserModules = [
        #   (
        #     { pkgs, ... }:
        #     {
        #       home.packages = with pkgs; [
        #         obsidian
        #         vscode
        #         bitwarden-desktop
        #       ];
        #     }
        #   )
        # ];
      };
      keystoneServices = {
        # Shared infrastructure services are placed globally here.
        #
        # Keystone validates that each `*.host` matches a host declared below,
        # then the matching machine auto-enables the corresponding service.
        #
        # Examples:
        # git.host = "server";
        # mail.host = "server";
      };

      # Each block below represents a single host in this Keystone system.
      #
      # Common host shapes:
      # - laptop
      # - workstation
      # - server
      # - macbook
      hosts = {
        # ----------------------------------------------------------------------
        # Laptop config
        # ----------------------------------------------------------------------
        laptop = {
          kind = "laptop";

          nixosModules = [
            # keystone.nixosModules.server
          ];
        };

        # ----------------------------------------------------------------------
        # Server config
        # ----------------------------------------------------------------------
        server = {
          kind = "server";
          # The host attribute name above is also the hostname by default.
          # Rename `server` to whatever fits — keep the directory under
          # hosts/<name>/ in sync. Override only if hostname must differ
          # from the attribute name: `hostname = "...";`.
        };

        # ----------------------------------------------------------------------
        # Macbook config — Home Manager only, no NixOS system.
        #
        # `kind = "macbook"` makes mkSystemFlake emit a `homeConfigurations.<name>`
        # output (not `nixosConfigurations`). The macbook host has no
        # hardware.nix, no system services, no agenix — it's just Home Manager
        # packages + dotfiles for a user on someone else's macOS install.
        # See hosts/macbook/configuration.nix for the module shape and deploy
        # command.
        # ----------------------------------------------------------------------
        macbook = {
          kind = "macbook";
        };
      };
    }
    // (
      let
        pkgs = keystone.inputs.nixpkgs.legacyPackages.x86_64-linux;
        # `nix flake new -t` does not preserve executable bits when copying
        # the template, so `./bin/<script>` from a freshly-scaffolded repo
        # comes out 644 and fails with "permission denied" until the user
        # remembers to `chmod +x bin/*`. Wrap each script as a Nix
        # derivation so its executable bit is set in /nix/store, and
        # surface it on the dev shell's PATH — `nix develop -c iso-burn-usb`
        # works immediately, with zero setup beyond entering the shell.
        scriptBin = name: pkgs.writeShellScriptBin name (builtins.readFile (./bin + "/${name}"));
        isoBurnUsb = scriptBin "iso-burn-usb";
        isoVmPreview = scriptBin "iso-vm-preview";
        osAgentsE2e = scriptBin "os-agents-e2e";
      in
      {
        devShells.x86_64-linux.default = pkgs.mkShell {
          packages = [
            pkgs.jq
            pkgs.nixfmt
            pkgs.nil
            pkgs.imagemagick # PPM→PNG conversion for e2e screenshots
            pkgs.nix-serve # local binary cache for e2e VM installs
            isoBurnUsb
            isoVmPreview
            osAgentsE2e
          ];
          shellHook = ''
            cat <<'BANNER'
            Keystone dev shell — helper scripts on PATH:
              iso-burn-usb    write result/iso/*.iso to a USB stick (guided)
              iso-vm-preview  boot result/iso/*.iso in a local QEMU VM
              os-agents-e2e   validate installed OS agents, or no-op if none configured
            Run `iso-burn-usb --help` or `iso-vm-preview --help` for options.
            BANNER
          '';
        };
      }
    );
}
