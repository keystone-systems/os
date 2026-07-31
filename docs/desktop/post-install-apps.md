# Post-install applications

After a fresh Keystone laptop install, the desktop ships with core utilities
and Chromium. Additional applications are added in your config flake.

## Where to add packages

| Where | Scope | Installed via | Example |
|-------|-------|---------------|---------|
| `shared.desktopUserModules` | Desktop hosts only | Home Manager (per-user) | Obsidian, VS Code, Bitwarden |
| `shared.userModules` | Every host | Home Manager (per-user) | fd, ripgrep |
| `shared.systemModules` | Every host | NixOS (OS-wide) | btop, 1Password NixOS module |
| `hosts/<name>/configuration.nix` | One host | NixOS (OS-wide) | GPU-specific tools |

Desktop user modules apply to laptop and workstation hosts but not servers.
GUI apps belong in `desktopUserModules` — installed per-user via Home Manager,
not at the OS level.

## flake.nix example

```nix
keystone.lib.mkSystemFlake {
  admin = { /* ... */ };
  hostsRoot = ./hosts;

  shared = {
    # Installed in your user profile via Home Manager on every host.
    userModules = [
      ({ pkgs, ... }: { home.packages = with pkgs; [ fd ]; })
    ];

    # Installed OS-wide via NixOS on every host.
    systemModules = [
      ({ pkgs, ... }: { environment.systemPackages = with pkgs; [ btop ]; })
    ];

    # Installed in your user profile via Home Manager on desktop hosts only.
    # Each entry is a Nix function that receives { pkgs, ... } and returns
    # config. As the list grows, you can extract it to a file:
    #   desktopUserModules = [ (import ./modules/home/desktop-apps.nix) ];
    desktopUserModules = [
      (
        { pkgs, ... }:
        {
          home.packages = with pkgs; [
            # obsidian              # Knowledge management (vaults at ~/notes/)
            # vscode                # VS Code (supports Claude Code extension)
            # zed-editor
            # bitwarden-desktop
          ];
        }
      )
    ];
  };

  # Default browser — Chromium ships by default, bound to $mod+B.
  # Uncomment to switch:
  # keystone.desktop.browser = "google-chrome-stable";
  # keystone.desktop.browser = "firefox";

  hosts = {
    laptop = { kind = "laptop"; };          # gets desktopUserModules
    workstation = { kind = "workstation"; }; # gets desktopUserModules
    server-ocean = { kind = "server"; };     # does not
  };
}
```

## Finding packages

Search for available packages and NixOS service options at:

- [Packages](https://search.nixos.org/packages?channel=unstable) — find the attribute name to use in `home.packages` or `environment.systemPackages`
- [Options](https://search.nixos.org/options?channel=unstable) — find NixOS module options like `programs._1password-gui.enable`

## Default browser

Chromium ships by default and is bound to `$mod+B`. To switch browsers, set
`keystone.desktop.browser` to the binary name:

```nix
keystone.desktop.browser = "google-chrome-stable";  # Chrome
keystone.desktop.browser = "firefox";               # Firefox
keystone.desktop.browser = "chromium";               # Chromium (default)
```

Set this in a shared module or per-host config. Remember to also add the
browser package in `desktopUserModules`.

## Notes

- **Helix** ships by default via the terminal module with automatic theme
  integration.
- OS-level desktop settings (like `programs._1password-gui.enable`) go in
  per-host `configuration.nix` or `shared.systemModules` if needed everywhere.

## Applying changes

```bash
ks build        # verify it compiles
ks switch       # apply immediately (requires approval)
```
