//! Integration tests that evaluate/build generated Nix configs against the real flake.
//!
//! These require a working Nix installation, so they are `#[ignore]`d by
//! default. Run explicitly with:
//!
//! ```sh
//! cargo test config_evaluates -- --ignored   # eval only (~30s)
//! cargo test config_builds -- --ignored      # full build + ISO (minutes)
//! ```

use ks::template::{GenerateConfig, MachineType, RemoteUnlockConfig, StorageType, UserConfig};
use std::path::PathBuf;
use std::process::Command;

// ---------------------------------------------------------------------------
// Eval tests — fast, catches type errors and missing options
// ---------------------------------------------------------------------------

#[test]
#[ignore]
fn test_generated_server_config_evaluates() {
    eval_generated_config("eval-server", MachineType::Server, StorageType::Zfs);
}

#[test]
#[ignore]
fn test_generated_laptop_config_evaluates() {
    eval_generated_config("eval-laptop", MachineType::Laptop, StorageType::Ext4);
}

#[test]
#[ignore]
fn test_generated_workstation_config_evaluates() {
    eval_generated_config(
        "eval-workstation",
        MachineType::Workstation,
        StorageType::Zfs,
    );
}

// ---------------------------------------------------------------------------
// Build tests — slow, catches missing packages and broken derivations.
// Also builds the installer ISO since that's the first thing users do
// after generating their config.
// ---------------------------------------------------------------------------

#[test]
#[ignore]
fn test_generated_server_config_builds() {
    build_generated_config("build-server", MachineType::Server, StorageType::Zfs);
}

#[test]
#[ignore]
fn test_generated_laptop_config_builds() {
    build_generated_config("build-laptop", MachineType::Laptop, StorageType::Ext4);
}

#[test]
#[ignore]
fn test_generated_workstation_config_builds() {
    build_generated_config(
        "build-workstation",
        MachineType::Workstation,
        StorageType::Zfs,
    );
}

/// Build the keystone installer ISO from the local repo.
/// This is what users boot on target hardware before deploying their
/// generated config via nixos-anywhere.
#[test]
#[ignore]
fn test_keystone_iso_builds() {
    let root = repo_root();
    let iso_link = root.join("result-iso");

    let flake_ref = format!("path:{}#packages.x86_64-linux.iso", root.display(),);

    let output = Command::new("nix")
        .args([
            "build",
            &flake_ref,
            "--out-link",
            &iso_link.display().to_string(),
        ])
        .current_dir(&root)
        .output()
        .expect("failed to execute `nix build` for ISO");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    assert!(
        output.status.success(),
        "nix build failed for keystone ISO\n\
         exit code: {:?}\nstdout:\n{stdout}\nstderr:\n{stderr}",
        output.status.code(),
    );

    // Verify the ISO artifact exists
    let iso_dir = std::fs::read_link(&iso_link).expect("result-iso symlink missing");
    assert!(
        iso_dir.exists(),
        "ISO build output does not exist at {}",
        iso_dir.display(),
    );
    eprintln!("ISO built: {}", iso_dir.display());
}

/// Build a pre-baked installer ISO that embeds a generated NixOS config.
/// This tests the new ISO workflow: user generates config on dev machine,
/// builds an ISO with the config baked in, boots target from USB.
#[test]
#[ignore]
fn test_prebaked_iso_evaluates() {
    let config = make_config("prebaked-laptop", MachineType::Laptop, StorageType::Ext4);
    let local_root = repo_root();
    let hostname = &config.hostname;

    // Generate the target machine's config files
    let target_flake = ks::template::generate_flake_nix(&config).replace(
        "keystone.url = \"github:ncrmro/keystone\"",
        &format!("keystone.url = \"path:{}\"", local_root.display()),
    );
    let target_config = ks::template::generate_configuration_nix(&config);
    let target_hardware = ks::template::generate_hardware_nix(&config);

    // Generate the ISO flake that wraps the config
    let iso_flake = ks::template::generate_iso_flake_nix(&config).replace(
        "url = \"github:ncrmro/keystone\"",
        &format!("url = \"path:{}\"", local_root.display()),
    );

    let dir = tempfile::tempdir().expect("failed to create temp dir");

    // Write the ISO flake
    std::fs::write(dir.path().join("flake.nix"), &iso_flake)
        .expect("failed to write ISO flake.nix");

    // Write the target config in the expected subdirectory with hosts/ layout
    let target_dir = dir.path().join("target-config");
    let target_host_dir = target_dir.join("hosts").join(hostname);
    std::fs::create_dir_all(&target_host_dir).expect("failed to create target-config/hosts/");
    std::fs::write(target_dir.join("flake.nix"), &target_flake)
        .expect("failed to write target flake.nix");
    std::fs::write(target_host_dir.join("configuration.nix"), &target_config)
        .expect("failed to write target configuration.nix");
    std::fs::write(target_host_dir.join("hardware.nix"), &target_hardware)
        .expect("failed to write target hardware.nix");

    // Evaluate the ISO configuration to prove it type-checks
    let eval_expr = format!(
        concat!(
            "let sys = (builtins.getFlake \"{path}\").nixosConfigurations.keystoneIso; ",
            "in builtins.seq sys.config.system.build.toplevel.drvPath \"ok\"",
        ),
        path = dir.path().display(),
    );

    let output = Command::new("nix")
        .args(["eval", "--impure", "--expr", &eval_expr])
        .current_dir(dir.path())
        .output()
        .expect("failed to execute `nix eval` for pre-baked ISO");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    assert!(
        output.status.success(),
        "nix eval failed for pre-baked ISO\n\
         exit code: {:?}\nstdout:\n{stdout}\nstderr:\n{stderr}",
        output.status.code(),
    );
}

/// Build a pre-baked installer ISO that embeds a generated NixOS config.
/// This is the full build — produces an actual ISO image artifact.
#[test]
#[ignore]
fn test_prebaked_iso_builds() {
    let config = make_config("prebaked-laptop", MachineType::Laptop, StorageType::Ext4);
    let local_root = repo_root();
    let hostname = &config.hostname;

    // Generate the target machine's config files
    let target_flake = ks::template::generate_flake_nix(&config).replace(
        "keystone.url = \"github:ncrmro/keystone\"",
        &format!("keystone.url = \"path:{}\"", local_root.display()),
    );
    let target_config = ks::template::generate_configuration_nix(&config);
    let target_hardware = ks::template::generate_hardware_nix(&config);

    // Generate the ISO flake that wraps the config
    let iso_flake = ks::template::generate_iso_flake_nix(&config).replace(
        "url = \"github:ncrmro/keystone\"",
        &format!("url = \"path:{}\"", local_root.display()),
    );

    let dir = tempfile::tempdir().expect("failed to create temp dir");

    // Write the ISO flake
    std::fs::write(dir.path().join("flake.nix"), &iso_flake)
        .expect("failed to write ISO flake.nix");

    // Write the target config in the expected subdirectory with hosts/ layout
    let target_dir = dir.path().join("target-config");
    let target_host_dir = target_dir.join("hosts").join(hostname);
    std::fs::create_dir_all(&target_host_dir).expect("failed to create target-config/hosts/");
    std::fs::write(target_dir.join("flake.nix"), &target_flake)
        .expect("failed to write target flake.nix");
    std::fs::write(target_host_dir.join("configuration.nix"), &target_config)
        .expect("failed to write target configuration.nix");
    std::fs::write(target_host_dir.join("hardware.nix"), &target_hardware)
        .expect("failed to write target hardware.nix");

    // Build the ISO image with a stable output link in the repo root (gitignored via result-*)
    let iso_link = local_root.join("result-iso");
    let flake_ref = format!(
        "path:{}#nixosConfigurations.keystoneIso.config.system.build.isoImage",
        dir.path().display(),
    );

    let output = Command::new("nix")
        .args([
            "build",
            &flake_ref,
            "--out-link",
            &iso_link.display().to_string(),
        ])
        .current_dir(dir.path())
        .output()
        .expect("failed to execute `nix build` for pre-baked ISO");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    assert!(
        output.status.success(),
        "nix build failed for pre-baked ISO\n\
         exit code: {:?}\nstdout:\n{stdout}\nstderr:\n{stderr}",
        output.status.code(),
    );

    // Verify the ISO artifact exists at the stable path
    let iso_target = std::fs::read_link(&iso_link).expect("result-iso symlink missing");
    assert!(
        iso_target.exists(),
        "ISO build output does not exist at {}",
        iso_target.display(),
    );

    // Find the .iso file inside
    let iso_dir = iso_link.join("iso");
    if iso_dir.exists() {
        for entry in std::fs::read_dir(&iso_dir).expect("failed to read iso/") {
            let entry = entry.expect("failed to read dir entry");
            if entry.path().extension().is_some_and(|e| e == "iso") {
                eprintln!("Pre-baked ISO built: {}", entry.path().display());
            }
        }
    }
    eprintln!("ISO output link: {}", iso_link.display());
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Resolve the keystone repo root from the crate directory.
/// The crate is at packages/ks/, so the repo root is two levels up.
fn repo_root() -> PathBuf {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    manifest_dir
        .parent()
        .and_then(|p| p.parent())
        .expect("could not find repo root from CARGO_MANIFEST_DIR")
        .to_path_buf()
}

/// Build a `GenerateConfig` with sensible test defaults for the given machine/storage type.
fn make_config(
    hostname: &str,
    machine_type: MachineType,
    storage_type: StorageType,
) -> GenerateConfig {
    GenerateConfig {
        hostname: hostname.to_string(),
        machine_type,
        storage_type,
        disk_device: Some("/dev/disk/by-id/nvme-TEST_DISK_001".to_string()),
        github_username: None,
        time_zone: "UTC".to_string(),
        state_version: "25.05".to_string(),
        user: UserConfig {
            username: "testuser".to_string(),
            password: "testpass".to_string(),
            authorized_keys: vec!["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest test@host".to_string()],
        },
        remote_unlock: RemoteUnlockConfig {
            enable: machine_type == MachineType::Server,
            authorized_keys: if machine_type == MachineType::Server {
                vec!["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest test@host".to_string()]
            } else {
                vec![]
            },
        },
        owner_name: None,
        owner_email: None,
    }
}

/// Generate Nix files from a config and write them to a temp dir.
/// Uses the hosts/<hostname>/ layout matching mkSystemFlake convention.
fn write_generated_config(
    hostname: &str,
    machine_type: MachineType,
    storage_type: StorageType,
) -> tempfile::TempDir {
    let config = make_config(hostname, machine_type, storage_type);

    let flake_nix = ks::template::generate_flake_nix(&config);
    let configuration_nix = ks::template::generate_configuration_nix(&config);
    let hardware_nix = ks::template::generate_hardware_nix(&config);

    // Point at the local repo so we test uncommitted module changes instead
    // of whatever is on GitHub.
    let local_root = repo_root();
    let flake_nix = flake_nix.replace(
        "keystone.url = \"github:ncrmro/keystone\"",
        &format!("keystone.url = \"path:{}\"", local_root.display()),
    );

    let dir = tempfile::tempdir().expect("failed to create temp dir");
    let host_dir = dir.path().join("hosts").join(hostname);
    std::fs::create_dir_all(&host_dir).expect("failed to create hosts/<hostname> directory");

    std::fs::write(dir.path().join("flake.nix"), &flake_nix).expect("failed to write flake.nix");
    std::fs::write(host_dir.join("configuration.nix"), &configuration_nix)
        .expect("failed to write configuration.nix");
    std::fs::write(host_dir.join("hardware.nix"), &hardware_nix)
        .expect("failed to write hardware.nix");

    dir
}

/// Generate a config, write it to a temp dir, and run `nix eval` to prove the
/// NixOS configuration evaluates without errors.
fn eval_generated_config(hostname: &str, machine_type: MachineType, storage_type: StorageType) {
    let dir = write_generated_config(hostname, machine_type, storage_type);

    let eval_expr = format!(
        concat!(
            "let sys = (builtins.getFlake \"{path}\").nixosConfigurations.{host}; ",
            "in builtins.seq sys.config.system.build.toplevel.drvPath \"ok\"",
        ),
        path = dir.path().display(),
        host = hostname,
    );

    let output = Command::new("nix")
        .args(["eval", "--impure", "--expr", &eval_expr])
        .current_dir(dir.path())
        .output()
        .expect("failed to execute `nix eval`");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    assert!(
        output.status.success(),
        "nix eval failed for {hostname} ({machine_type:?}/{storage_type:?})\n\
         exit code: {:?}\nstdout:\n{stdout}\nstderr:\n{stderr}",
        output.status.code(),
    );
}

/// Generate a config, write it to a temp dir, and run `nix build` to prove the
/// NixOS configuration builds successfully. This catches missing packages and
/// broken derivations that evaluation alone misses.
fn build_generated_config(hostname: &str, machine_type: MachineType, storage_type: StorageType) {
    let dir = write_generated_config(hostname, machine_type, storage_type);

    let flake_ref = format!(
        "path:{}#nixosConfigurations.{}.config.system.build.toplevel",
        dir.path().display(),
        hostname,
    );

    let output = Command::new("nix")
        .args(["build", &flake_ref, "--no-link"])
        .current_dir(dir.path())
        .output()
        .expect("failed to execute `nix build`");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    assert!(
        output.status.success(),
        "nix build failed for {hostname} ({machine_type:?}/{storage_type:?})\n\
         exit code: {:?}\nstdout:\n{stdout}\nstderr:\n{stderr}",
        output.status.code(),
    );
}
