# Keystone Desktop — NixOS-level system configuration.
# Implements REQ-002 (Keystone Desktop)
# See conventions/process.enable-by-default.md
{
  config,
  lib,
  options,
  pkgs,
  keystoneInputs,
  ...
}:
with lib;
let
  cfg = config.keystone.desktop;
in
{
  # nix-flatpak is imported via flake.nix nixosModules.desktop (hoisted to avoid
  # _module.args infinite recursion when keystoneInputs is used in imports)
  options.keystone.desktop = {
    enable = mkEnableOption "Keystone Desktop - Core desktop packages and utilities";

    obs = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable OBS Studio for screen recording and streaming";
      };
      # TODO: Teach hosts to declare their GPU type and derive this default
      # automatically so desktop systems do not need to set OBS GPU support
      # manually.
      gpuType = mkOption {
        type = types.nullOr (
          types.enum [
            "amd"
            "intel"
            "nvidia"
          ]
        );
        default = null;
        description = ''
          GPU type for hardware-accelerated encoding in OBS.
          - amd: enables VA-API and Vulkan capture plugins
          - intel: enables VA-API plugin
          - nvidia: enables Vulkan capture plugin (NVENC is built into OBS core)
          When null, only PipeWire audio capture is included (no GPU-specific plugins).
          Future desktop hosts SHOULD declare their GPU type so Keystone can
          select this automatically.
        '';
      };
    };

    user = mkOption {
      type = types.str;
      description = "Primary desktop user for the Hyprland session";
    };
  };

  config = mkIf cfg.enable {
    # Walker dispatches `ks update --approve` through `systemd-inhibit`
    # so suspend/shutdown can't wedge a switch. systemd-inhibit runs
    # without AllowInteractive, and walker.service lives in user@.service
    # (no logind seat session), so polkit's subject.active and
    # subject.local are both false for it. Grant the admin user the
    # inhibit-* actions directly — gating on session attributes would
    # re-break walker.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (subject.user == "${config.keystone.os.adminUsername}" &&
            action.id.indexOf("org.freedesktop.login1.inhibit-") == 0) {
          return polkit.Result.YES;
        }
      });
    '';

    # Flatpak support (declarative via nix-flatpak)
    services.flatpak.enable = mkDefault true;

    # Hyprland with UWSM (using official flake for latest features)
    programs.hyprland = {
      enable = mkDefault true;
      withUWSM = mkDefault true;
      package = mkDefault keystoneInputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
      portalPackage = mkDefault pkgs.xdg-desktop-portal-hyprland; # Use stable nixpkgs version to fix Qt version mismatch
    };

    # Mesa and GPU drivers for Wayland compositors (Hyprland requires DRM/KMS).
    # Enables virtio-gpu support in VMs and hardware GPU on bare metal.
    hardware.graphics.enable = mkDefault true;

    # Greetd launches the user's Hyprland session directly. Startup
    # authentication happens inside Hyprland via keystone-startup-lock, which
    # MUST fail closed if hyprlock cannot come up securely.
    # CRITICAL: XDG_SESSION_CLASS=user must be in the command environment so pam_systemd.so
    # sees it before registering the logind session. The PAM class= argument alone is not
    # sufficient — pam_systemd gives XDG_SESSION_CLASS env var highest precedence.
    # Without this, the session registers as Class=greeter on seat0, causing polkit's
    # allow_active=yes policy to deny access — breaking pcscd, YubiKey PIV, and power management.
    # uwsm 0.26.4 (nixpkgs 26.11) gained a readability check in
    # `check_path()`. Resolving the bare name "Hyprland" lands on
    # `/run/wrappers/bin/Hyprland` (setuid wrapper, mode 4750), which
    # has no read bit, so env-preloader fails before Hyprland starts.
    # Pass the unwrapped binary path; this drops CAP_SYS_NICE but
    # keeps the compositor launchable.
    services.greetd = {
      enable = mkDefault true;
      settings.default_session = {
        command = mkDefault "env XDG_SESSION_CLASS=user uwsm start -F ${config.programs.hyprland.package}/bin/Hyprland";
        user = cfg.user;
      };
    };

    # The desktop session depends on Home Manager activation having already
    # materialized mutable theme links like ~/.config/keystone/current/theme
    # and ~/.config/keystone/current/background. Without explicit ordering,
    # display-manager can start the Hyprland session before home-manager-$user
    # has finished on a fresh install, which leaves the first session without
    # wallpaper and increases the chance of startup errors in user services.
    systemd.services."home-manager-${cfg.user}" = mkIf (options ? home-manager) {
      before = [ "display-manager.service" ];
    };
    systemd.services.display-manager = mkIf (options ? home-manager) {
      wants = [ "home-manager-${cfg.user}.service" ];
      after = [ "home-manager-${cfg.user}.service" ];
    };

    # Configure PAM to register greetd session as wayland type
    # This enables loginctl lock-session to work properly
    security.pam.services.greetd.rules.session.systemd.settings = {
      type = "wayland";
      # Belt-and-suspenders: also set class=user in PAM for any code path that doesn't
      # inherit the env var. The env var takes precedence per pam_systemd docs.
      class = "user";
    };

    # Pipewire audio stack
    security.rtkit.enable = mkDefault true;
    services.pulseaudio.enable = mkDefault false;
    services.pipewire = {
      enable = mkDefault true;
      alsa.enable = mkDefault true;
      pulse.enable = mkDefault true;
      jack.enable = mkDefault true;
    };

    # Bluetooth
    hardware.bluetooth.enable = mkDefault true;
    services.blueman.enable = mkDefault true;

    # Fingerprint reader daemon — required for fprintd-enroll/verify/delete to
    # find the D-Bus service. PAM integration (fprintAuth) is intentionally
    # deferred; enable the daemon first so enrollment via the Walker menu works.
    services.fprintd.enable = mkDefault true;

    # Printing (CUPS + Avahi/mDNS discovery)
    services.printing.enable = mkDefault true;
    services.avahi = {
      enable = mkDefault true;
      nssmdns4 = mkDefault true;
      openFirewall = mkDefault true;
    };

    # Networking (for laptops, portables, and thin clients)
    networking.networkmanager.enable = mkDefault true;
    # Route the desktop default through keystone.os so the core OS module stays
    # the single writer of services.resolved.enable.
    keystone.os.services.resolved.enable = mkDefault true;
    # Required for Tailscale MagicDNS to work with systemd-resolved
    # https://github.com/NixOS/nixpkgs/issues/231191#issuecomment-1664053176
    environment.etc."resolv.conf".mode = "direct-symlink";

    # Fonts
    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-color-emoji
      nerd-fonts.jetbrains-mono
      nerd-fonts.caskaydia-mono
    ];

    # System packages for desktop environment
    environment.systemPackages =
      with pkgs;
      [
        # Screen recording
        gpu-screen-recorder

        # Media
        ## Video Editor
        ## kdenlive disabled: broken in nixpkgs unstable (missing shaderc link in ffmpeg-full)
        # kdePackages.kdenlive
        ## Video Player
        mpv

        # Browser
        chromium

        # File management
        nautilus
        file-roller
        sushi
        loupe

        # Fingerprint CLI tools — enrollment terminal inherits user PATH, not
        # the wrapper's runtimeInputs, so the binaries must be globally present.
        fprintd

        # System utilities
        pavucontrol
        networkmanagerapplet
        # blueberry was removed from nixpkgs (unmaintained upstream);
        # blueman is the supported replacement.
        blueman

        # XDG portals and desktop integration
        xdg-utils
        xdg-user-dirs

        # Polkit agent
        keystone.hyprpolkitagent

        # GTK themes and cursor themes
        gnome-themes-extra
        adwaita-icon-theme

        # Additional Hyprland tools
        hyprsunset
        hyprlock
        hypridle
        hyprpaper
      ]
      ++ optionals cfg.obs.enable [
        (wrapOBS {
          plugins =
            with obs-studio-plugins;
            [
              obs-pipewire-audio-capture
            ]
            ++ optionals (cfg.obs.gpuType == "amd") [
              obs-vaapi
              obs-vkcapture
            ]
            ++ optionals (cfg.obs.gpuType == "intel") [
              obs-vaapi
            ]
            ++ optionals (cfg.obs.gpuType == "nvidia") [
              obs-vkcapture
            ];
        })
      ];

    # Enable polkit
    security.polkit.enable = mkDefault true;

    # XDG portal configuration
    xdg.portal = {
      enable = mkDefault true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
      ];
    };

    # This allows shell scripts to resolve /bin/bash
    systemd.tmpfiles.rules = [
      "L+ /bin/bash - - - - ${pkgs.bash}/bin/bash"
    ];

    # OOM Killer configuration
    # Prioritize killing docker/podman rootless processes over Hyprland.
    # Hyprland (via UWSM wayland-wm@ template) uses the systemd default of 0.
    # Setting docker/podman to +1000 ensures they are killed first in OOM scenarios.
    #
    # NOTE: We cannot set OOMScoreAdjust for wayland-wm@Hyprland directly because
    # NixOS creates a replacement unit instead of a drop-in override, which removes
    # ExecStart and breaks the UWSM template-based service entirely.
    systemd.user.services = {
      docker.serviceConfig.OOMScoreAdjust = 1000;
      podman.serviceConfig.OOMScoreAdjust = 1000;
    };
  };
}
