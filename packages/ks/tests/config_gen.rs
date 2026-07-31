//! Tests for Nix configuration generation with mkSystemFlake template.

use ks::template::{GenerateConfig, MachineType, RemoteUnlockConfig, StorageType, UserConfig};

fn test_config() -> GenerateConfig {
    GenerateConfig {
        hostname: "test-host".to_string(),
        machine_type: MachineType::Server,
        storage_type: StorageType::Zfs,
        disk_device: Some("/dev/disk/by-id/nvme-test".to_string()),
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
fn test_flake_uses_mksystemflake() {
    let config = test_config();
    let flake = ks::template::generate_flake_nix(&config);

    assert!(
        flake.contains("keystone.lib.mkSystemFlake"),
        "flake should call mkSystemFlake"
    );
    assert!(
        flake.contains(r#"kind = "server""#),
        "server config should have kind = server"
    );
    assert!(
        flake.contains(r#""test-host" ="#),
        "flake should contain hostname as host key"
    );
}

#[test]
fn test_flake_contains_owner() {
    let config = GenerateConfig {
        owner_name: Some("Noah".to_string()),
        owner_email: Some("noah@example.com".to_string()),
        ..test_config()
    };

    let flake = ks::template::generate_flake_nix(&config);
    assert!(flake.contains(r#"name = "Noah""#));
    assert!(flake.contains(r#"email = "noah@example.com""#));
    assert!(flake.contains(r#"username = "admin""#));
}

#[test]
fn test_hardware_nix_contains_storage_config() {
    let config = test_config();
    let hardware = ks::template::generate_hardware_nix(&config);

    assert!(
        hardware.contains("/dev/disk/by-id/nvme-test"),
        "hardware.nix should contain disk device"
    );
    assert!(
        hardware.contains("networking.hostId"),
        "hardware.nix should contain hostId"
    );
    assert!(
        hardware.contains("inherit system"),
        "hardware.nix should export system"
    );
}

#[test]
fn test_laptop_kind_in_flake() {
    let config = GenerateConfig {
        hostname: "my-laptop".to_string(),
        machine_type: MachineType::Laptop,
        storage_type: StorageType::Ext4,
        disk_device: Some("/dev/nvme0n1".to_string()),
        ..test_config()
    };

    let flake = ks::template::generate_flake_nix(&config);
    assert!(
        flake.contains(r#"kind = "laptop""#),
        "laptop config should have kind = laptop"
    );
}
