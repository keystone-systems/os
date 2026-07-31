//! Nix configuration template generation.
//!
//! Generates flake.nix, configuration.nix, and hardware.nix from
//! user-provided configuration parameters.

pub(crate) const DISK_PLACEHOLDER: &str = "__KEYSTONE_DISK__";
pub(crate) const HOST_ID_PLACEHOLDER: &str = "00000000";

/// Machine type determines which Keystone modules are included.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MachineType {
    Server,
    Workstation,
    Laptop,
}

impl MachineType {
    pub fn label(&self) -> &'static str {
        match self {
            MachineType::Server => "Server (headless)",
            MachineType::Workstation => "Workstation (desktop + ZFS)",
            MachineType::Laptop => "Laptop (desktop + ext4 + hibernate)",
        }
    }

    /// The Keystone host kind string used in mkSystemFlake `hosts` inventory.
    pub fn kind(&self) -> &'static str {
        match self {
            MachineType::Server => "server",
            MachineType::Workstation => "workstation",
            MachineType::Laptop => "laptop",
        }
    }
}

/// Storage backend type.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StorageType {
    Zfs,
    Ext4,
}

impl StorageType {
    pub fn label(&self) -> &'static str {
        match self {
            StorageType::Zfs => "ZFS (snapshots, compression)",
            StorageType::Ext4 => "ext4 (simple, hibernation-compatible)",
        }
    }

    pub fn nix_value(&self) -> &'static str {
        match self {
            StorageType::Zfs => "zfs",
            StorageType::Ext4 => "ext4",
        }
    }
}

/// User configuration for a Keystone machine.
pub struct UserConfig {
    pub username: String,
    pub password: String,
    pub authorized_keys: Vec<String>,
}

/// Remote unlock configuration.
pub struct RemoteUnlockConfig {
    pub enable: bool,
    pub authorized_keys: Vec<String>,
}

/// Full configuration for generating Nix files.
pub struct GenerateConfig {
    pub hostname: String,
    pub machine_type: MachineType,
    pub storage_type: StorageType,
    pub disk_device: Option<String>,
    pub github_username: Option<String>,
    pub time_zone: String,
    pub state_version: String,
    pub user: UserConfig,
    pub remote_unlock: RemoteUnlockConfig,
    /// Owner's display name (for mkSystemFlake owner.name). Defaults to username.
    pub owner_name: Option<String>,
    /// Owner's email (for mkSystemFlake owner.email). Defaults to username@localhost.
    pub owner_email: Option<String>,
}

/// Generate a flake.nix file from configuration.
///
/// Produces a flake calling `keystone.lib.mkSystemFlake` with a single
/// `keystone` input. The host inventory, owner identity, and defaults
/// are all expressed declaratively in the mkSystemFlake call.
pub fn generate_flake_nix(config: &GenerateConfig) -> String {
    let owner_name = config
        .owner_name
        .as_deref()
        .unwrap_or(&config.user.username);
    let default_email = format!("{}@localhost", config.user.username);
    let owner_email = config.owner_email.as_deref().unwrap_or(&default_email);

    format!(
        r#"# keystone-config-version: 1.0.0
{{
  description = "{owner_name_esc} Keystone System Configuration";

  inputs = {{
    keystone.url = "github:ncrmro/keystone";
  }};

  outputs =
    {{ keystone, ... }}:
    keystone.lib.mkSystemFlake {{
      owner = {{
        name = "{owner_name_esc}";
        username = "{username_esc}";
        email = "{owner_email_esc}";
      }};
      defaults = {{
        timeZone = "{time_zone_esc}";
      }};
      hostsRoot = ./hosts;
      hosts = {{
        "{hostname_esc}" = {{
          kind = "{kind}";
        }};
      }};
    }}
    // {{
      devShells.x86_64-linux.default =
        keystone.inputs.nixpkgs.legacyPackages.x86_64-linux.mkShell {{
          packages = with keystone.inputs.nixpkgs.legacyPackages.x86_64-linux; [
            nixfmt
            nil
          ];
        }};
    }};
}}
"#,
        owner_name_esc = escape_nix_string(owner_name),
        username_esc = escape_nix_string(&config.user.username),
        owner_email_esc = escape_nix_string(owner_email),
        time_zone_esc = escape_nix_string(&config.time_zone),
        hostname_esc = escape_nix_string(&config.hostname),
        kind = config.machine_type.kind(),
    )
}

/// Generate a per-host configuration.nix file.
///
/// With mkSystemFlake, the admin user, desktop defaults, storage defaults,
/// hostname, and timezone are all derived from the flake-level `owner`,
/// host `kind`, and `defaults` blocks. The per-host configuration.nix
/// only contains host-specific overrides.
pub fn generate_configuration_nix(_config: &GenerateConfig) -> String {
    r#"{
  pkgs,
  ...
}:
{
  # Host-specific overrides.
  #
  # The core machine shape (admin user, desktop, storage, timezone) is
  # derived by mkSystemFlake from the flake-level owner, host kind, and
  # defaults blocks. Add only host-only settings here.

  environment.systemPackages = with pkgs; [
    git
    helix
  ];

  # Examples:
  # services.printing.enable = true;
  # networking.firewall.allowedTCPPorts = [ 22 80 443 ];
}
"#
    .to_string()
}

/// Generate a flake.nix for a pre-baked installer ISO.
///
/// The ISO embeds the user's generated config files (flake.nix and
/// hosts/<hostname>/{configuration,hardware}.nix) at `/etc/keystone/install-config/`
/// so the TUI installer on the target machine can run disko + nixos-install.
pub fn generate_iso_flake_nix(config: &GenerateConfig) -> String {
    let ssh_keys_nix = format_nix_string_list(&config.user.authorized_keys, 12);
    let hostname_esc = escape_nix_string(&config.hostname);
    let username_esc = escape_nix_string(&config.user.username);
    let github_username_esc = escape_nix_string(config.github_username.as_deref().unwrap_or(""));

    format!(
        r#"{{
  description = "Keystone Installer ISO — {hostname_esc}";

  inputs = {{
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    keystone = {{
      url = "github:ncrmro/keystone";
      inputs.nixpkgs.follows = "nixpkgs";
    }};
    home-manager = {{
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    }};
  }};

  outputs = {{
    self,
    nixpkgs,
    keystone,
    home-manager,
    ...
  }}: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${{system}};
  in {{
    nixosConfigurations.keystoneIso = nixpkgs.lib.nixosSystem {{
      inherit system;
      modules = [
        "${{nixpkgs}}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        keystone.nixosModules.isoInstaller
        {{
          # SSH keys for remote access during installation
          keystone.installer.sshKeys = {ssh_keys_nix};

          # Embed the user's NixOS config files into the ISO filesystem.
          # The TUI installer reads these from /etc/keystone/install-config/
          # to run disko + nixos-install on the target machine.
          environment.etc."keystone/install-config/flake.nix".source = ./target-config/flake.nix;
          environment.etc."keystone/install-config/hosts/{hostname_esc}/configuration.nix".source = ./target-config/hosts/{hostname_esc}/configuration.nix;
          environment.etc."keystone/install-config/hosts/{hostname_esc}/hardware.nix".source = ./target-config/hosts/{hostname_esc}/hardware.nix;
          environment.etc."keystone/install-config/hostname".text = "{hostname_esc}";
          environment.etc."keystone/install-config/username".text = "{username_esc}";
          environment.etc."keystone/install-config/github_username".text = "{github_username_esc}";

          # Pin kernel to match upstream keystone ISO (6.12)
          boot.kernelPackages = nixpkgs.lib.mkForce pkgs.linuxPackages_6_12;
        }}
      ];
    }};
  }};
}}
"#,
        hostname_esc = hostname_esc,
        username_esc = username_esc,
        github_username_esc = github_username_esc,
        ssh_keys_nix = ssh_keys_nix,
    )
}

/// Generate a hardware.nix in the mkSystemFlake `{ system; module; }` format.
///
/// The hardware.nix exports `system` (architecture) and a `module` attribute
/// containing hardware-specific NixOS configuration: hostId, storage devices,
/// boot modules, and firmware settings.
pub fn generate_hardware_nix(config: &GenerateConfig) -> String {
    let host_id = generate_host_id();
    let raw_disk = config.disk_device.as_deref().unwrap_or(DISK_PLACEHOLDER);
    let disk_device = escape_nix_string(raw_disk);

    format!(
        r#"let
  system = "x86_64-linux";
in
{{
  inherit system;

  module =
    {{
      config,
      lib,
      pkgs,
      modulesPath,
      ...
    }}:
    {{
      imports = [
        (modulesPath + "/profiles/qemu-guest.nix")
      ];

      networking.hostId = "{host_id}";

      keystone.os.storage.devices = [
        "{disk_device}"
      ];
      keystone.os.storage.mode = "single";

      boot.initrd.availableKernelModules = [
        "ahci"
        "nvme"
        "sd_mod"
        "sr_mod"
        "usb_storage"
        "xhci_pci"
        "ehci_pci"
        "usbhid"
        "virtio_pci"
        "virtio_blk"
        "virtio_scsi"
        "virtio_net"
      ];

      boot.kernelModules = [
        "kvm-intel"
      ];

      hardware.cpu.intel.updateMicrocode =
        lib.mkDefault config.hardware.enableRedistributableFirmware;
      hardware.enableRedistributableFirmware = true;
    }};
}}
"#,
        host_id = host_id,
        disk_device = disk_device,
    )
}

/// Generate a random 8-character hex host ID.
pub(crate) fn generate_host_id() -> String {
    use std::io::Read;
    let mut buf = [0u8; 4];
    if let Ok(mut f) = std::fs::File::open("/dev/urandom") {
        let _ = f.read_exact(&mut buf);
    }
    // Fallback: use a simple hash of the current time
    if buf == [0u8; 4] {
        let t = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        buf = (t as u32).to_le_bytes();
    }
    format!("{:02x}{:02x}{:02x}{:02x}", buf[0], buf[1], buf[2], buf[3])
}

/// Escape a string for safe embedding inside a Nix double-quoted string literal.
///
/// Escapes: `\` → `\\`, `"` → `\"`, `${` → `\${`
/// Newlines are also escaped so multi-line values don't break the generated Nix.
fn escape_nix_string(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace("${", "\\${")
        .replace('\n', "\\n")
}

/// Format a Vec<String> as a Nix list of strings with proper indentation.
fn format_nix_string_list(items: &[String], indent: usize) -> String {
    if items.is_empty() {
        return "[]".to_string();
    }
    let pad = " ".repeat(indent);
    let mut result = String::from("[\n");
    for item in items {
        result.push_str(&format!("{}  \"{}\"\n", pad, escape_nix_string(item)));
    }
    result.push_str(&format!("{}]", pad));
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_config() -> GenerateConfig {
        GenerateConfig {
            hostname: "test-host".to_string(),
            machine_type: MachineType::Server,
            storage_type: StorageType::Zfs,
            disk_device: Some("/dev/disk/by-id/test-disk".to_string()),
            github_username: None,
            time_zone: "UTC".to_string(),
            state_version: "25.05".to_string(),
            user: UserConfig {
                username: "admin".to_string(),
                password: "changeme".to_string(),
                authorized_keys: vec![],
            },
            remote_unlock: RemoteUnlockConfig {
                enable: false,
                authorized_keys: vec![],
            },
            owner_name: None,
            owner_email: None,
        }
    }

    #[test]
    fn test_escape_nix_string() {
        assert_eq!(escape_nix_string(r#"hello"world"#), r#"hello\"world"#);
        assert_eq!(escape_nix_string(r"back\slash"), r"back\\slash");
        assert_eq!(escape_nix_string("${inject}"), r"\${inject}");
        assert_eq!(escape_nix_string("line1\nline2"), r"line1\nline2");
        assert_eq!(escape_nix_string("plain"), "plain");
    }

    #[test]
    fn test_format_nix_string_list_empty() {
        assert_eq!(format_nix_string_list(&[], 0), "[]");
    }

    #[test]
    fn test_format_nix_string_list_with_keys() {
        let keys = vec![
            "ssh-ed25519 AAAAC3test key1".to_string(),
            "ssh-ed25519 AAAAC3test key2".to_string(),
        ];
        let result = format_nix_string_list(&keys, 8);
        assert!(result.contains("\"ssh-ed25519 AAAAC3test key1\""));
        assert!(result.contains("\"ssh-ed25519 AAAAC3test key2\""));
        assert!(result.starts_with('['));
        assert!(result.ends_with(']'));
    }

    #[test]
    fn test_generate_flake_uses_mksystemflake() {
        let config = test_config();
        let flake = generate_flake_nix(&config);

        // Must parse cleanly
        let root = rnix::Root::parse(&flake);
        assert!(
            root.errors().is_empty(),
            "flake.nix has parse errors: {:?}",
            root.errors()
        );

        // Single keystone input
        let inputs = crate::nix::extract_flake_inputs(&flake);
        assert_eq!(inputs.len(), 1, "should have exactly one input (keystone)");
        assert_eq!(inputs[0].name, "keystone");
        assert_eq!(inputs[0].url.as_deref(), Some("github:ncrmro/keystone"),);

        // Must contain mkSystemFlake call
        assert!(
            flake.contains("keystone.lib.mkSystemFlake"),
            "should call mkSystemFlake"
        );

        // Must contain host kind
        assert!(
            flake.contains(r#"kind = "server""#),
            "server config should have kind = server"
        );
    }

    #[test]
    fn test_generate_flake_host_kinds() {
        for (machine_type, expected_kind) in [
            (MachineType::Server, "server"),
            (MachineType::Workstation, "workstation"),
            (MachineType::Laptop, "laptop"),
        ] {
            let config = GenerateConfig {
                machine_type,
                ..test_config()
            };
            let flake = generate_flake_nix(&config);
            assert!(
                flake.contains(&format!(r#"kind = "{}""#, expected_kind)),
                "MachineType::{:?} should produce kind = {:?}",
                machine_type,
                expected_kind,
            );
        }
    }

    #[test]
    fn test_generate_flake_owner_fields() {
        let config = GenerateConfig {
            owner_name: Some("Noah".to_string()),
            owner_email: Some("noah@example.com".to_string()),
            ..test_config()
        };
        let flake = generate_flake_nix(&config);
        assert!(flake.contains(r#"name = "Noah""#));
        assert!(flake.contains(r#"email = "noah@example.com""#));
        assert!(flake.contains(r#"username = "admin""#));
    }

    #[test]
    fn test_generate_flake_owner_defaults() {
        let config = test_config();
        let flake = generate_flake_nix(&config);
        // Without owner_name, falls back to username
        assert!(flake.contains(r#"name = "admin""#));
        assert!(flake.contains(r#"email = "admin@localhost""#));
    }

    #[test]
    fn test_generate_flake_timezone() {
        let config = GenerateConfig {
            time_zone: "America/New_York".to_string(),
            ..test_config()
        };
        let flake = generate_flake_nix(&config);
        assert!(flake.contains(r#"timeZone = "America/New_York""#));
    }

    #[test]
    fn test_generate_flake_parses_with_nix_parser() {
        let config = test_config();
        let flake = generate_flake_nix(&config);

        // Round-trip: generate and parse back
        let hosts = crate::nix::extract_nixos_configurations_from_str(&flake);
        assert_eq!(hosts.len(), 1, "should find one host");
        assert_eq!(hosts[0].name, "test-host");
    }

    #[test]
    fn test_generate_configuration_nix_parses() {
        let config = test_config();
        let nix = generate_configuration_nix(&config);

        let root = rnix::Root::parse(&nix);
        assert!(
            root.errors().is_empty(),
            "configuration.nix has parse errors: {:?}",
            root.errors()
        );
    }

    #[test]
    fn test_generate_hardware_nix_with_disk() {
        let config = test_config();
        let nix = generate_hardware_nix(&config);

        let root = rnix::Root::parse(&nix);
        assert!(
            root.errors().is_empty(),
            "hardware.nix has parse errors: {:?}",
            root.errors()
        );

        assert!(nix.contains("inherit system"), "should export system");
        assert!(nix.contains("module ="), "should export module");
        assert!(
            nix.contains("/dev/disk/by-id/test-disk"),
            "should contain disk device"
        );
        assert!(nix.contains("networking.hostId"), "should contain hostId");
    }

    #[test]
    fn test_generate_hardware_nix_no_disk() {
        let config = GenerateConfig {
            disk_device: None,
            ..test_config()
        };
        let nix = generate_hardware_nix(&config);
        assert!(nix.contains("__KEYSTONE_DISK__"));
    }

    #[test]
    fn test_generate_host_id_format() {
        let id = generate_host_id();
        assert_eq!(id.len(), 8);
        assert!(id.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn test_generate_iso_flake() {
        let config = GenerateConfig {
            hostname: "my-laptop".to_string(),
            machine_type: MachineType::Laptop,
            github_username: Some("octocat".to_string()),
            ..test_config()
        };

        let iso_flake = generate_iso_flake_nix(&config);

        // Must parse cleanly
        let root = rnix::Root::parse(&iso_flake);
        assert!(
            root.errors().is_empty(),
            "ISO flake has parse errors: {:?}",
            root.errors()
        );

        // Verify inputs via AST
        let inputs = crate::nix::extract_flake_inputs(&iso_flake);
        let input_names: Vec<&str> = inputs.iter().map(|i| i.name.as_str()).collect();
        assert!(input_names.contains(&"keystone"));
        assert!(input_names.contains(&"nixpkgs"));

        // Verify the keystoneIso host exists
        let hosts = crate::nix::extract_nixos_configurations_from_str(&iso_flake);
        assert_eq!(hosts.len(), 1);
        assert_eq!(hosts[0].name, "keystoneIso");

        // Verify isoInstaller module is referenced
        assert!(
            hosts[0]
                .keystone_modules
                .contains(&"isoInstaller".to_string()),
            "ISO config must include isoInstaller module"
        );

        // Verify hosts/ directory layout in embedded paths
        assert!(
            iso_flake.contains("hosts/my-laptop/configuration.nix"),
            "ISO should embed hosts/<hostname>/configuration.nix"
        );
        assert!(
            iso_flake.contains("hosts/my-laptop/hardware.nix"),
            "ISO should embed hosts/<hostname>/hardware.nix"
        );
    }

    #[test]
    fn test_machine_type_kind() {
        assert_eq!(MachineType::Server.kind(), "server");
        assert_eq!(MachineType::Workstation.kind(), "workstation");
        assert_eq!(MachineType::Laptop.kind(), "laptop");
    }
}
